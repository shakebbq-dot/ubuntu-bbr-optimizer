#!/bin/bash
#
# BBR & System Optimization Script for Ubuntu
# Supports: Ubuntu 18.04/20.04/22.04
# Author: TraeAI
# Version: 1.0.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# Paths
SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_BACKUP="/etc/sysctl.conf.bak.$(date +%F_%H-%M-%S)"
LIMITS_CONF="/etc/security/limits.conf"
LOG_FILE="/var/log/bbr_install.log"

# Check Root
[[ $EUID -ne 0 ]] && echo -e "${RED}Error: This script must be run as root!${PLAIN}" && exit 1

# Logging
log() {
    local level=$1
    shift
    local msg="$@"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${msg}" >> "${LOG_FILE}"
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${PLAIN} ${msg}" ;;
        "WARN") echo -e "${YELLOW}[WARN]${PLAIN} ${msg}" ;;
        "ERROR") echo -e "${RED}[ERROR]${PLAIN} ${msg}" ;;
    esac
}

# Check OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log "WARN" "This script is optimized for Ubuntu. Detected: $ID. Continuing anyway..."
        fi
    else
        log "ERROR" "Unsupported OS. /etc/os-release not found."
        exit 1
    fi
}

# Backup Config
backup_config() {
    if [[ ! -f "$SYSCTL_BACKUP" ]]; then
        cp "$SYSCTL_CONF" "$SYSCTL_BACKUP"
        log "INFO" "Backup created: $SYSCTL_BACKUP"
    else
        log "INFO" "Backup already exists for this session."
    fi
}

# Install XanMod Kernel
install_xanmod() {
    log "INFO" "Preparing to install XanMod Kernel..."
    log "WARN" "This will add the XanMod repository and install the kernel."
    
    read -p "Do you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Installation cancelled."
        return
    fi

    apt-get update -y
    apt-get install -y wget gnupg
    
    log "INFO" "Adding XanMod GPG key..."
    wget -qO - https://dl.xanmod.org/gpg.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
    
    log "INFO" "Adding XanMod Repository..."
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
    
    log "INFO" "Installing XanMod Kernel..."
    apt-get update -y
    # Install generic compatible version
    apt-get install -y linux-xanmod-x64v1
    
    log "INFO" "XanMod Kernel installed. Please reboot to apply changes."
    echo -e "${YELLOW}System needs to reboot to load the new kernel.${PLAIN}"
    read -p "Reboot now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
}

# Enable BBR
enable_bbr() {
    local algo=$1
    local qdisc=$2
    
    [[ -z "$algo" ]] && algo="bbr"
    [[ -z "$qdisc" ]] && qdisc="fq"

    log "INFO" "Enabling TCP Congestion Control: $algo with Qdisc: $qdisc"
    
    backup_config
    
    # Remove existing BBR lines
    sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
    sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
    
    # Add new config
    echo "net.core.default_qdisc = $qdisc" >> "$SYSCTL_CONF"
    echo "net.ipv4.tcp_congestion_control = $algo" >> "$SYSCTL_CONF"
    
    sysctl -p >/dev/null 2>&1
    
    verify_bbr
}

# Verify BBR
verify_bbr() {
    local current_algo=$(sysctl -n net.ipv4.tcp_congestion_control)
    local current_qdisc=$(sysctl -n net.core.default_qdisc)
    
    if [[ "$current_algo" == *"bbr"* || "$current_algo" == *"xanmod"* ]]; then
        log "INFO" "BBR is active! (Algo: $current_algo, Qdisc: $current_qdisc)"
        echo -e "${GREEN}Success: BBR is running.${PLAIN}"
    else
        log "WARN" "BBR might not be active. Current: $current_algo / $current_qdisc"
    fi
}

# System Optimizations
optimize_system() {
    log "INFO" "Applying system optimizations..."
    backup_config
    
    cat >> "$SYSCTL_CONF" <<EOF

# --- BBR Script Optimizations ---
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

    # Optimize Limits
    echo "* soft nofile 51200" >> "$LIMITS_CONF"
    echo "* hard nofile 51200" >> "$LIMITS_CONF"
    echo "root soft nofile 51200" >> "$LIMITS_CONF"
    echo "root hard nofile 51200" >> "$LIMITS_CONF"
    
    sysctl -p >/dev/null 2>&1
    log "INFO" "System optimizations applied."
}

# Configure Timezone
configure_timezone() {
    log "INFO" "Configuring Timezone..."
    dpkg-reconfigure tzdata
    apt-get install -y ntpdate
    ntpdate pool.ntp.org
    log "INFO" "Time synchronized."
}

# Uninstall / Restore
restore_defaults() {
    log "INFO" "Restoring default settings..."
    
    if [[ -f "$SYSCTL_BACKUP" ]]; then
        cp "$SYSCTL_BACKUP" "$SYSCTL_CONF"
        sysctl -p >/dev/null 2>&1
        log "INFO" "Restored sysctl.conf from backup."
    else
        # Manual cleanup if no backup
        sed -i '/--- BBR Script Optimizations ---/,/# ------------------------------/d' "$SYSCTL_CONF"
        sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
        sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
        log "INFO" "Cleaned up sysctl.conf manually."
    fi
    
    echo -e "${GREEN}System restored to previous state (kernel remains installed).${PLAIN}"
}

# Main Menu
show_menu() {
    clear
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "${BLUE}       Ubuntu BBR & Optimization Script         ${PLAIN}"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "OS: $(source /etc/os-release && echo $PRETTY_NAME)"
    echo -e "Kernel: $(uname -r)"
    echo -e "Current Algo: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'Unknown')"
    echo -e "${BLUE}================================================${PLAIN}"
    echo -e "1. Enable Standard BBR"
    echo -e "2. Install XanMod Kernel (Advanced BBR/CAKE)"
    echo -e "3. Switch to CUBIC"
    echo -e "4. Switch to Reno"
    echo -e "5. Apply System Optimizations (Limits, Sysctl)"
    echo -e "6. Configure Timezone & Sync"
    echo -e "7. Restore Defaults / Uninstall"
    echo -e "0. Exit"
    echo -e "${BLUE}================================================${PLAIN}"
    
    read -p "Enter choice [0-7]: " choice
    
    case $choice in
        1) enable_bbr "bbr" "fq" ;;
        2) install_xanmod ;;
        3) enable_bbr "cubic" "pfifo_fast" ;;
        4) enable_bbr "reno" "pfifo_fast" ;;
        5) optimize_system ;;
        6) configure_timezone ;;
        7) restore_defaults ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid choice${PLAIN}" ;;
    esac
}

# Argument Parsing
if [[ $# -gt 0 ]]; then
    case $1 in
        --enable-bbr) enable_bbr "bbr" "fq" ;;
        --install-xanmod) install_xanmod ;;
        --optimize) optimize_system ;;
        --restore) restore_defaults ;;
        *) echo "Usage: $0 [--enable-bbr | --install-xanmod | --optimize | --restore]" ;;
    esac
else
    check_os
    while true; do
        show_menu
        read -p "Press Enter to continue..."
    done
fi
