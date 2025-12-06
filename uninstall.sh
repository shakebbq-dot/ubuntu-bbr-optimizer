#!/bin/bash
#
# BBR 优化卸载脚本
#

RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'

SYSCTL_CONF="/etc/sysctl.conf"

echo -e "${RED}警告: 这将移除所有网络优化和 BBR 配置。${PLAIN}"
read -p "确定要继续吗? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# 清理 sysctl
echo "正在清理 sysctl.conf..."
sed -i '/--- BBR 脚本优化配置 ---/,/# ------------------------------/d' "$SYSCTL_CONF"
sed -i '/--- BBR Script Optimizations ---/,/# ------------------------------/d' "$SYSCTL_CONF"
sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"

# 应用更改
sysctl -p

# 移除 XanMod 仓库
if [[ -f /etc/apt/sources.list.d/xanmod-release.list ]]; then
    echo "检测到 XanMod 仓库。"
    read -p "是否移除 XanMod 仓库源? (内核将保留) [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f /etc/apt/sources.list.d/xanmod-release.list
        rm -f /usr/share/keyrings/xanmod-archive-keyring.gpg
        echo "XanMod 仓库已移除。"
    fi
fi

echo -e "${GREEN}卸载完成。原始网络设置已恢复。${PLAIN}"
