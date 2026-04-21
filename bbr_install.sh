#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

if [[ ! -t 1 ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PLAIN=''
fi

VERSION="2.0.0"

ROOT_DIR="/"
DRY_RUN=0

LOCK_FILE="/var/lock/bbr-optimizer.lock"
STATE_FILE="/var/lib/bbr-optimizer/state.env"
SYSCTL_FILE="/etc/sysctl.d/99-bbr-optimizer.conf"
LIMITS_FILE="/etc/security/limits.d/99-bbr-optimizer.conf"
LOG_FILE="/var/log/bbr-optimizer.log"
LOGROTATE_FILE="/etc/logrotate.d/bbr-optimizer"

info() { echo -e "${GREEN}[信息]${PLAIN} $*"; }
warn() { echo -e "${YELLOW}[警告]${PLAIN} $*"; }
err() { echo -e "${RED}[错误]${PLAIN} $*"; }
die() { err "$*"; exit 1; }

path_join() {
    local base="$1"
    local p="$2"
    if [[ "$base" == "/" ]]; then
        echo "$p"
    else
        echo "${base%/}$p"
    fi
}

log_append() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_path
    log_path="$(path_join "$ROOT_DIR" "$LOG_FILE")"
    mkdir -p "$(dirname "$log_path")"
    touch "$log_path"
    chmod 600 "$log_path" 2>/dev/null || true
    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$log_path"
}

run() {
    local desc="$1"
    shift
    log_append "INFO" "$desc: $*"
    "$@"
}

require_root() {
    if [[ "$DRY_RUN" -eq 1 && "$ROOT_DIR" != "/" ]]; then
        return
    fi
    [[ ${EUID:-$(id -u)} -eq 0 ]] || die "本脚本必须以 root 身份运行"
}

with_lock() {
    local lock_path
    lock_path="$(path_join "$ROOT_DIR" "$LOCK_FILE")"
    if command -v flock >/dev/null 2>&1; then
        mkdir -p "$(dirname "$lock_path")"
        exec 9>"$lock_path"
        flock -n 9 || die "已有实例正在运行（锁：$lock_path）"
        "$@"
        return
    fi
    local lock_dir="${lock_path}.d"
    if mkdir "$lock_dir" 2>/dev/null; then
        trap 'rmdir "'"$lock_dir"'" 2>/dev/null || true' EXIT
        "$@"
        return
    fi
    die "已有实例正在运行（锁目录：$lock_dir）"
}

read_os_release() {
    local f
    f="$(path_join "$ROOT_DIR" "/etc/os-release")"
    if [[ -r "$f" ]]; then
        set +u
        source "$f"
        set -u
        echo "${ID:-unknown}" "${VERSION_ID:-unknown}" "${PRETTY_NAME:-unknown}"
        return
    fi
    echo "unknown" "unknown" "unknown"
}

kernel_release() {
    if [[ -n "${BBR_OPTIMIZER_KERNEL_RELEASE:-}" ]]; then
        echo "$BBR_OPTIMIZER_KERNEL_RELEASE"
        return
    fi
    uname -r 2>/dev/null || echo "unknown"
}

sysctl_path_for_key() {
    local k="$1"
    echo "/proc/sys/${k//./\/}"
}

sysctl_key_supported() {
    local k="$1"
    if [[ "$ROOT_DIR" != "/" ]]; then
        return 0
    fi
    [[ -e "$(sysctl_path_for_key "$k")" ]]
}

sysctl_get() {
    local k="$1"
    if [[ "$ROOT_DIR" != "/" ]]; then
        return 1
    fi
    sysctl -n "$k" 2>/dev/null || return 1
}

available_cc() {
    if [[ -n "${BBR_OPTIMIZER_AVAILABLE_CC:-}" ]]; then
        echo "$BBR_OPTIMIZER_AVAILABLE_CC"
        return
    fi
    if [[ "$ROOT_DIR" == "/" && -r /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
        cat /proc/sys/net/ipv4/tcp_available_congestion_control
        return
    fi
    sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true
}

choose_cc() {
    local requested="$1"
    local avail
    avail="$(available_cc)"
    if [[ -n "$requested" && "$requested" != "auto" ]]; then
        if [[ " $avail " == *" $requested "* ]]; then
            echo "$requested"
            return
        fi
        die "拥塞控制算法不可用：$requested（可用：$avail）"
    fi
    if [[ " $avail " == *" bbr "* ]]; then echo "bbr"; return; fi
    if [[ " $avail " == *" cubic "* ]]; then echo "cubic"; return; fi
    if [[ " $avail " == *" reno "* ]]; then echo "reno"; return; fi
    local cur
    cur="$(sysctl_get net.ipv4.tcp_congestion_control || true)"
    if [[ -n "$cur" ]]; then echo "$cur"; return; fi
    echo "cubic"
}

measure_rtt_ms() {
    local host="$1"
    if [[ -n "${BBR_OPTIMIZER_RTT_MS:-}" ]]; then
        echo "$BBR_OPTIMIZER_RTT_MS"
        return
    fi
    command -v ping >/dev/null 2>&1 || return 1
    local out line right avg
    out="$(ping -c 3 -W 1 "$host" 2>/dev/null || true)"
    line="$(printf '%s\n' "$out" | tail -n 1)"
    if [[ "$line" == *"="*"/"* ]]; then
        right="${line#*= }"
        avg="$(printf '%s' "$right" | awk -F'/' '{print $2}')"
        if [[ -n "$avg" ]]; then
            printf '%.0f\n' "$avg"
            return
        fi
    fi
    return 1
}

buf_max_for_rtt() {
    local rtt="${1:-0}"
    if [[ "$rtt" -ge 150 ]]; then echo 134217728; return; fi
    if [[ "$rtt" -ge 50 ]]; then echo 67108864; return; fi
    echo 33554432
}

write_kv_file() {
    local file_path="$1"
    shift
    local tmp
    tmp="$(mktemp)"
    : > "$tmp"
    local kv
    for kv in "$@"; do
        printf '%s\n' "$kv" >> "$tmp"
    done
    mkdir -p "$(dirname "$file_path")"
    install -m 0644 "$tmp" "$file_path"
    rm -f "$tmp"
}

save_state_once() {
    local state_path
    state_path="$(path_join "$ROOT_DIR" "$STATE_FILE")"
    if [[ -f "$state_path" ]]; then
        return
    fi
    mkdir -p "$(dirname "$state_path")"
    local orig_cc="" orig_qdisc=""
    if sysctl_key_supported net.ipv4.tcp_congestion_control; then orig_cc="$(sysctl_get net.ipv4.tcp_congestion_control || true)"; fi
    if sysctl_key_supported net.core.default_qdisc; then orig_qdisc="$(sysctl_get net.core.default_qdisc || true)"; fi
    {
        printf 'ORIG_CC=%q\n' "$orig_cc"
        printf 'ORIG_QDISC=%q\n' "$orig_qdisc"
        printf 'SAVED_AT=%q\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    } > "$state_path"
    chmod 600 "$state_path" 2>/dev/null || true
}

apply_sysctl_live() {
    if [[ "$DRY_RUN" -eq 1 || "$ROOT_DIR" != "/" ]]; then
        return
    fi
    if sysctl --system >/dev/null 2>&1; then
        return
    fi
    sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
}

apply_sysctl_one() {
    local k="$1"
    local v="$2"
    if [[ "$DRY_RUN" -eq 1 || "$ROOT_DIR" != "/" ]]; then
        return
    fi
    sysctl -w "$k=$v" >/dev/null 2>&1 || true
}

build_sysctl_kv() {
    local cc="$1"
    local qdisc="$2"
    local rtt_ms="$3"
    local max_buf
    max_buf="$(buf_max_for_rtt "$rtt_ms")"

    local kvs=()

    if sysctl_key_supported net.ipv4.tcp_congestion_control; then kvs+=("net.ipv4.tcp_congestion_control = $cc"); fi
    if sysctl_key_supported net.core.default_qdisc; then kvs+=("net.core.default_qdisc = $qdisc"); fi

    if sysctl_key_supported fs.file-max; then kvs+=("fs.file-max = 1000000"); fi
    if sysctl_key_supported net.core.rmem_max; then kvs+=("net.core.rmem_max = $max_buf"); fi
    if sysctl_key_supported net.core.wmem_max; then kvs+=("net.core.wmem_max = $max_buf"); fi
    if sysctl_key_supported net.core.netdev_max_backlog; then kvs+=("net.core.netdev_max_backlog = 250000"); fi
    if sysctl_key_supported net.core.somaxconn; then kvs+=("net.core.somaxconn = 4096"); fi

    if sysctl_key_supported net.ipv4.tcp_syncookies; then kvs+=("net.ipv4.tcp_syncookies = 1"); fi
    if sysctl_key_supported net.ipv4.tcp_sack; then kvs+=("net.ipv4.tcp_sack = 1"); fi
    if sysctl_key_supported net.ipv4.tcp_timestamps; then kvs+=("net.ipv4.tcp_timestamps = 1"); fi
    if sysctl_key_supported net.ipv4.tcp_window_scaling; then kvs+=("net.ipv4.tcp_window_scaling = 1"); fi
    if sysctl_key_supported net.ipv4.tcp_slow_start_after_idle; then kvs+=("net.ipv4.tcp_slow_start_after_idle = 0"); fi
    if sysctl_key_supported net.ipv4.tcp_tw_reuse; then kvs+=("net.ipv4.tcp_tw_reuse = 1"); fi
    if sysctl_key_supported net.ipv4.tcp_fin_timeout; then kvs+=("net.ipv4.tcp_fin_timeout = 30"); fi
    if sysctl_key_supported net.ipv4.tcp_keepalive_time; then kvs+=("net.ipv4.tcp_keepalive_time = 1200"); fi
    if sysctl_key_supported net.ipv4.tcp_keepalive_intvl; then kvs+=("net.ipv4.tcp_keepalive_intvl = 30"); fi
    if sysctl_key_supported net.ipv4.tcp_keepalive_probes; then kvs+=("net.ipv4.tcp_keepalive_probes = 10"); fi
    if sysctl_key_supported net.ipv4.ip_local_port_range; then kvs+=("net.ipv4.ip_local_port_range = 10000 65000"); fi
    if sysctl_key_supported net.ipv4.tcp_max_syn_backlog; then kvs+=("net.ipv4.tcp_max_syn_backlog = 8192"); fi
    if sysctl_key_supported net.ipv4.tcp_max_tw_buckets; then kvs+=("net.ipv4.tcp_max_tw_buckets = 5000"); fi
    if sysctl_key_supported net.ipv4.tcp_fastopen; then kvs+=("net.ipv4.tcp_fastopen = 3"); fi
    if sysctl_key_supported net.ipv4.tcp_rmem; then kvs+=("net.ipv4.tcp_rmem = 4096 87380 $max_buf"); fi
    if sysctl_key_supported net.ipv4.tcp_wmem; then kvs+=("net.ipv4.tcp_wmem = 4096 65536 $max_buf"); fi
    if sysctl_key_supported net.ipv4.tcp_mtu_probing; then kvs+=("net.ipv4.tcp_mtu_probing = 1"); fi

    if sysctl_key_supported net.netfilter.nf_conntrack_max; then kvs+=("net.netfilter.nf_conntrack_max = 262144"); fi
    if sysctl_key_supported net.netfilter.nf_conntrack_tcp_timeout_established; then kvs+=("net.netfilter.nf_conntrack_tcp_timeout_established = 7200"); fi

    printf '%s\n' "${kvs[@]}"
}

write_limits() {
    local limits_path dir
    limits_path="$(path_join "$ROOT_DIR" "$LIMITS_FILE")"
    dir="$(dirname "$limits_path")"
    [[ -d "$dir" ]] || return 0
    write_kv_file "$limits_path" \
        "* soft nofile 51200" \
        "* hard nofile 51200" \
        "root soft nofile 51200" \
        "root hard nofile 51200"
}

write_logrotate() {
    if [[ "$ROOT_DIR" != "/" ]]; then
        return
    fi
    [[ -d /etc/logrotate.d ]] || return
    write_kv_file "$LOGROTATE_FILE" \
        "$LOG_FILE {" \
        "  daily" \
        "  rotate 7" \
        "  compress" \
        "  missingok" \
        "  notifempty" \
        "  create 0600 root root" \
        "}"
}

apply_optimizer() {
    local requested_cc="$1"
    local requested_qdisc="$2"
    local rtt_host="$3"

    save_state_once

    local cc qdisc rtt_ms sysctl_path
    cc="$(choose_cc "$requested_cc")"

    qdisc="$requested_qdisc"
    if [[ -z "$qdisc" || "$qdisc" == "auto" ]]; then
        if [[ "$cc" == "bbr" ]]; then qdisc="fq"; else qdisc="fq_codel"; fi
    fi

    rtt_ms="0"
    if [[ -n "$rtt_host" ]]; then
        rtt_ms="$(measure_rtt_ms "$rtt_host" || echo 0)"
    fi

    sysctl_path="$(path_join "$ROOT_DIR" "$SYSCTL_FILE")"
    mapfile -t kvs < <(build_sysctl_kv "$cc" "$qdisc" "$rtt_ms")
    write_kv_file "$sysctl_path" "${kvs[@]}"
    write_limits
    write_logrotate
    apply_sysctl_live

    info "已生成配置：$SYSCTL_FILE"
    info "拥塞控制：$cc"
    info "队列算法：$qdisc"
    if [[ -n "$rtt_host" ]]; then info "探测 RTT：${rtt_ms}ms（host=$rtt_host）"; fi
}

restore_optimizer() {
    local sysctl_path limits_path state_path logrotate_path
    sysctl_path="$(path_join "$ROOT_DIR" "$SYSCTL_FILE")"
    limits_path="$(path_join "$ROOT_DIR" "$LIMITS_FILE")"
    state_path="$(path_join "$ROOT_DIR" "$STATE_FILE")"
    logrotate_path="$(path_join "$ROOT_DIR" "$LOGROTATE_FILE")"

    rm -f "$sysctl_path" "$limits_path" "$logrotate_path" 2>/dev/null || true
    apply_sysctl_live

    if [[ "$ROOT_DIR" == "/" && -f "$state_path" ]]; then
        set +u
        source "$state_path"
        set -u
        if [[ -n "${ORIG_CC:-}" ]] && sysctl_key_supported net.ipv4.tcp_congestion_control; then
            apply_sysctl_one net.ipv4.tcp_congestion_control "$ORIG_CC"
        fi
        if [[ -n "${ORIG_QDISC:-}" ]] && sysctl_key_supported net.core.default_qdisc; then
            apply_sysctl_one net.core.default_qdisc "$ORIG_QDISC"
        fi
    fi
    info "已移除优化配置"
}

monitor_status() {
    local id ver name
    read -r id ver name < <(read_os_release)
    info "系统：$name（$id $ver）"
    info "内核：$(kernel_release)"
    if [[ "$ROOT_DIR" != "/" ]]; then
        warn "--root 模式下不读取运行态指标"
        return
    fi
    if sysctl_key_supported net.ipv4.tcp_congestion_control; then
        info "当前拥塞控制：$(sysctl_get net.ipv4.tcp_congestion_control || echo unknown)"
    fi
    if sysctl_key_supported net.core.default_qdisc; then
        info "当前队列算法：$(sysctl_get net.core.default_qdisc || echo unknown)"
    fi
    if command -v ss >/dev/null 2>&1; then ss -s || true; fi
}

autotune_loop() {
    local interval="$1"
    local iterations="$2"
    local rtt_host="$3"

    [[ "$ROOT_DIR" == "/" ]] || die "autotune 仅支持真实系统运行（不支持 --root）"
    [[ "$DRY_RUN" -eq 0 ]] || die "autotune 不支持 --dry-run"

    local i=0
    while true; do
        i=$((i + 1))
        local cc qdisc rtt_ms desired cur_rmem cur_wmem
        cc="$(sysctl_get net.ipv4.tcp_congestion_control || echo auto)"
        qdisc="$(sysctl_get net.core.default_qdisc || echo auto)"
        rtt_ms="$(measure_rtt_ms "${rtt_host:-1.1.1.1}" || echo 0)"
        desired="$(buf_max_for_rtt "$rtt_ms")"
        cur_rmem="$(sysctl_get net.core.rmem_max || true)"
        cur_wmem="$(sysctl_get net.core.wmem_max || true)"

        if [[ -n "$cur_rmem" && "$cur_rmem" != "$desired" ]]; then
            apply_optimizer "$cc" "$qdisc" "${rtt_host:-1.1.1.1}"
        elif [[ -n "$cur_wmem" && "$cur_wmem" != "$desired" ]]; then
            apply_optimizer "$cc" "$qdisc" "${rtt_host:-1.1.1.1}"
        else
            info "autotune: rtt=${rtt_ms}ms buf_max=${desired}（无需变更）"
        fi

        if command -v ss >/dev/null 2>&1; then ss -s || true; fi

        if [[ "$iterations" -gt 0 && "$i" -ge "$iterations" ]]; then
            break
        fi
        sleep "$interval"
    done
}

install_xanmod() {
    local id
    read -r id _ < <(read_os_release)
    [[ "$ROOT_DIR" == "/" ]] || die "--root 模式不支持内核安装"
    if [[ "$id" != "ubuntu" && "$id" != "debian" ]]; then
        die "仅支持 Ubuntu/Debian 安装 XanMod（当前：$id）"
    fi
    command -v apt-get >/dev/null 2>&1 || die "未找到 apt-get"
    read -p "是否继续安装 XanMod 内核? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "安装已取消"
        return
    fi
    run "apt-get update" apt-get update -y
    run "安装依赖" apt-get install -y wget gnupg ca-certificates
    run "添加密钥" bash -lc "wget -qO - https://dl.xanmod.org/gpg.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes"
    run "添加源" bash -lc "echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] https://deb.xanmod.org releases main' > /etc/apt/sources.list.d/xanmod-release.list"
    run "apt-get update" apt-get update -y
    run "安装内核" apt-get install -y linux-xanmod-x64v1
    info "XanMod 内核安装完成（需要重启生效）"
}

usage() {
    cat <<EOF
用法:
  $0 [选项] [命令]

命令:
  --enable-bbr                 兼容旧用法：启用 bbr + fq
  enable                       应用拥塞控制与队列算法，并写入 sysctl.d/limits.d
  optimize                     应用系统优化（等价 enable + RTT 自适应 buffer）
  --optimize                   兼容旧用法：等价 optimize
  restore                      移除优化配置（保留内核安装）
  --restore                    兼容旧用法：等价 restore
  --uninstall                  同 restore（保留向后兼容）
  monitor                      输出运行态概要
  autotune                     定时探测 RTT 并自动调整 buffer 上限
  --install-xanmod             安装 XanMod（仅 Ubuntu/Debian）

选项:
  --cc=auto|bbr|cubic|reno     拥塞控制算法
  --qdisc=auto|fq|fq_codel|pfifo_fast
  --rtt-host=HOST              通过 ping 探测 RTT 以自适应 buffer（可选）
  --interval=SEC               autotune 间隔秒数（默认 10）
  --iterations=N               autotune 迭代次数（默认 0 表示持续运行）
  --dry-run                    仅生成文件，不应用 sysctl
  --root=PATH                  将 /etc 等根目录映射到 PATH（用于测试/离线生成）

EOF
}

main() {
    local cmd=""
    local cc="auto"
    local qdisc="auto"
    local rtt_host=""
    local interval="10"
    local iterations="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h) usage; exit 0 ;;
            --version) echo "$VERSION"; exit 0 ;;
            --dry-run) DRY_RUN=1; shift ;;
            --root=*) ROOT_DIR="${1#*=}"; shift ;;
            --cc=*) cc="${1#*=}"; shift ;;
            --qdisc=*) qdisc="${1#*=}"; shift ;;
            --rtt-host=*) rtt_host="${1#*=}"; shift ;;
            --interval=*) interval="${1#*=}"; shift ;;
            --iterations=*) iterations="${1#*=}"; shift ;;
            --enable-bbr) cmd="enable"; cc="bbr"; qdisc="fq"; shift ;;
            --optimize) cmd="optimize"; shift ;;
            --restore) cmd="restore"; shift ;;
            --uninstall) cmd="restore"; shift ;;
            --install-xanmod) cmd="install-xanmod"; shift ;;
            enable|optimize|restore|monitor|autotune|install-xanmod) cmd="$1"; shift ;;
            *) die "未知参数/命令：$1（使用 --help 查看用法）" ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        cmd="menu"
    fi

    require_root

    case "$cmd" in
        enable)
            with_lock apply_optimizer "$cc" "$qdisc" "$rtt_host"
            ;;
        optimize)
            with_lock apply_optimizer "$cc" "$qdisc" "${rtt_host:-1.1.1.1}"
            ;;
        restore)
            with_lock restore_optimizer
            ;;
        monitor)
            monitor_status
            ;;
        autotune)
            with_lock autotune_loop "$interval" "$iterations" "$rtt_host"
            ;;
        install-xanmod)
            with_lock install_xanmod
            ;;
        menu)
            while true; do
                clear
                echo -e "${BLUE}================================================${PLAIN}"
                echo -e "${BLUE}   BBR Optimizer (Linux 多发行版) v${VERSION}   ${PLAIN}"
                echo -e "${BLUE}================================================${PLAIN}"
                local id ver name
                read -r id ver name < <(read_os_release)
                echo -e "系统: $name"
                echo -e "内核: $(kernel_release)"
                if [[ "$ROOT_DIR" == "/" ]] && sysctl_key_supported net.ipv4.tcp_congestion_control; then
                    echo -e "当前算法: $(sysctl_get net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
                fi
                echo -e "${BLUE}================================================${PLAIN}"
                echo -e "1. 智能启用/切换拥塞控制（auto）"
                echo -e "2. 指定启用 BBR"
                echo -e "3. 指定切换 CUBIC"
                echo -e "4. 指定切换 Reno"
                echo -e "5. 应用系统优化（含 RTT 自适应 buffer）"
                echo -e "6. 监控（当前状态）"
                echo -e "7. 自动调优（RTT 探测循环）"
                echo -e "8. 还原/卸载优化"
                echo -e "9. 安装 XanMod（Ubuntu/Debian）"
                echo -e "0. 退出"
                echo -e "${BLUE}================================================${PLAIN}"
                read -p "请输入选项 [0-9]: " choice
                case "$choice" in
                    1) with_lock apply_optimizer "auto" "auto" "" ;;
                    2) with_lock apply_optimizer "bbr" "fq" "" ;;
                    3) with_lock apply_optimizer "cubic" "fq_codel" "" ;;
                    4) with_lock apply_optimizer "reno" "pfifo_fast" "" ;;
                    5) with_lock apply_optimizer "auto" "auto" "1.1.1.1" ;;
                    6) monitor_status ;;
                    7) with_lock autotune_loop "$interval" "$iterations" "${rtt_host:-1.1.1.1}" ;;
                    8) with_lock restore_optimizer ;;
                    9) with_lock install_xanmod ;;
                    0) exit 0 ;;
                    *) warn "无效选项" ;;
                esac
                read -p "按回车键继续..."
            done
            ;;
        *)
            die "未知命令：$cmd"
            ;;
    esac
}

main "$@"
