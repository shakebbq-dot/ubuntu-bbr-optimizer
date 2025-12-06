#!/bin/bash
#
# Ubuntu BBR 加速与优化脚本
# 支持: Ubuntu 18.04/20.04/22.04
# 作者: TraeAI
# 版本: 1.1.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 路径定义
SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_BACKUP="/etc/sysctl.conf.bak.$(date +%F_%H-%M-%S)"
LIMITS_CONF="/etc/security/limits.conf"
LOG_FILE="/var/log/bbr_install.log"

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 本脚本必须以 root 身份运行!${PLAIN}" && exit 1

# 日志函数
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${msg}" >> "${LOG_FILE}"
    
    case $level in
        "INFO") echo -e "${GREEN}[信息]${PLAIN} ${msg}" ;;
        "WARN") echo -e "${YELLOW}[警告]${PLAIN} ${msg}" ;;
        "ERROR") echo -e "${RED}[错误]${PLAIN} ${msg}" ;;
    esac
}

# 检查操作系统
check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log "WARN" "本脚本针对 Ubuntu 优化。检测到系统为: $ID。将继续执行..."
        fi
    else
        log "ERROR" "不支持的操作系统。未找到 /etc/os-release。"
        exit 1
    fi
}

# 备份配置
backup_config() {
    if [[ ! -f "$SYSCTL_BACKUP" ]]; then
        cp "$SYSCTL_CONF" "$SYSCTL_BACKUP"
        log "INFO" "已创建备份: $SYSCTL_BACKUP"
    else
        log "INFO" "本次会话已存在备份。"
    fi
}

# 安装 XanMod 内核
install_xanmod() {
    log "INFO" "准备安装 XanMod 内核..."
    log "WARN" "这将添加 XanMod 仓库并安装新内核。"
    
    read -p "是否继续? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "安装已取消。"
        return
    fi

    apt-get update -y
    apt-get install -y wget gnupg
    
    log "INFO" "添加 XanMod GPG 密钥..."
    wget -qO - https://dl.xanmod.org/gpg.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
    
    log "INFO" "添加 XanMod 仓库..."
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
    
    log "INFO" "正在安装 XanMod 内核..."
    apt-get update -y
    # 安装通用兼容版本
    apt-get install -y linux-xanmod-x64v1
    
    log "INFO" "XanMod 内核安装完成。请重启系统以生效。"
    echo -e "${YELLOW}系统需要重启以加载新内核。${PLAIN}"
    read -p "现在重启吗? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
}

# 启用 BBR
enable_bbr() {
    local algo=$1
    local qdisc=$2
    
    [[ -z "$algo" ]] && algo="bbr"
    [[ -z "$qdisc" ]] && qdisc="fq"

    log "INFO" "正在启用 TCP 拥塞控制: $algo (队列算法: $qdisc)"
    
    backup_config
    
    # 移除现有 BBR 配置
    sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
    sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
    
    # 添加新配置
    echo "net.core.default_qdisc = $qdisc" >> "$SYSCTL_CONF"
    echo "net.ipv4.tcp_congestion_control = $algo" >> "$SYSCTL_CONF"
    
    sysctl -p >/dev/null 2>&1
    
    verify_bbr
}

# 验证 BBR
verify_bbr() {
    local current_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    local current_qdisc=$(sysctl -n net.core.default_qdisc)
    
    if [[ "$current_algo" == *"bbr"* || "$current_algo" == *"xanmod"* ]]; then
        log "INFO" "BBR 已生效! (算法: $current_algo, 队列: $current_qdisc)"
        echo -e "${GREEN}成功: BBR 正在运行。${PLAIN}"
    else
        log "WARN" "BBR 可能未生效。当前状态: $current_algo / $current_qdisc"
    fi
}

# 系统优化
optimize_system() {
    log "INFO" "正在应用系统优化..."
    backup_config
    
    cat >> "$SYSCTL_CONF" <<EOF

# --- BBR 脚本优化配置 ---
fs.file-max = 1000000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
# ------------------------------
EOF

    # 优化资源限制
    echo "* soft nofile 51200" >> "$LIMITS_CONF"
    echo "* hard nofile 51200" >> "$LIMITS_CONF"
    echo "root soft nofile 51200" >> "$LIMITS_CONF"
    echo "root hard nofile 51200" >> "$LIMITS_CONF"
    
    sysctl -p >/dev/null 2>&1
    log "INFO" "系统优化已应用。"
}

# 配置时区
configure_timezone() {
    log "INFO" "正在配置时区..."
    dpkg-reconfigure tzdata
    apt-get install -y ntpdate
    ntpdate pool.ntp.org
    log "INFO" "时间已同步。"
}

# 还原/卸载
restore_defaults() {
    log "INFO" "正在还原默认设置..."
    
    if [[ -f "$SYSCTL_BACKUP" ]]; then
        cp "$SYSCTL_BACKUP" "$SYSCTL_CONF"
        sysctl -p >/dev/null 2>&1
        log "INFO" "已从备份还原 sysctl.conf。"
    else
        # 无备份时手动清理
        sed -i '/--- BBR 脚本优化配置 ---/,/# ------------------------------/d' "$SYSCTL_CONF"
        sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
        sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
        log "INFO" "已手动清理 sysctl.conf。"
    fi
    
    echo -e "${GREEN}系统已还原至先前状态 (内核保持安装)。${PLAIN}"
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}       Ubuntu BBR 加速与优化脚本                ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "操作系统: $(source /etc/os-release && echo $PRETTY_NAME)"
    echo -e "内核版本: $(uname -r)"
    echo -e "当前算法: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "1. 启用标准 BBR (推荐)"
    echo -e "2. 安装 XanMod 内核 (高级 BBR/CAKE)"
    echo -e "3. 切换至 CUBIC 算法"
    echo -e "4. 切换至 Reno 算法"
    echo -e "5. 应用系统优化 (连接数、Sysctl)"
    echo -e "6. 配置时区与同步时间"
    echo -e "7. 还原默认设置 / 卸载优化"
    echo -e "0. 退出脚本"
    echo -e "${BLUE}================================================${PLAIN}"
    
    read -p "请输入选项 [0-7]: " choice
    
    case $choice in
        1) enable_bbr "bbr" "fq" ;;
        2) install_xanmod ;;
        3) enable_bbr "cubic" "pfifo_fast" ;;
        4) enable_bbr "reno" "pfifo_fast" ;;
        5) optimize_system ;;
        6) configure_timezone ;;
        7) restore_defaults ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选项${PLAIN}" ;;
    esac
}

# 参数解析
if [[ $# -gt 0 ]]; then
    case $1 in
        --enable-bbr) enable_bbr "bbr" "fq" ;;
        --install-xanmod) install_xanmod ;;
        --optimize) optimize_system ;;
        --restore) restore_defaults ;;
        *) echo "用法: $0 [--enable-bbr | --install-xanmod | --optimize | --restore]" ;;
    esac
else
    check_os
    while true; do
        show_menu
        read -p "按回车键继续..."
    done
fi
