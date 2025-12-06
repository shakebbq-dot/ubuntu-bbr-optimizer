#!/bin/bash
#
# Uninstall Script for BBR Optimization
#

RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'

SYSCTL_CONF="/etc/sysctl.conf"

echo -e "${RED}Warning: This will remove network optimizations and BBR configuration.${PLAIN}"
read -p "Are you sure? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Clean sysctl
echo "Cleaning sysctl.conf..."
sed -i '/--- BBR Script Optimizations ---/,/# ------------------------------/d' "$SYSCTL_CONF"
sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"

# Apply changes
sysctl -p

# Remove XanMod Repo if exists
if [[ -f /etc/apt/sources.list.d/xanmod-release.list ]]; then
    echo "Detected XanMod repository."
    read -p "Do you want to remove the XanMod repository source? (Kernel will remain) [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f /etc/apt/sources.list.d/xanmod-release.list
        rm -f /usr/share/keyrings/xanmod-archive-keyring.gpg
        echo "XanMod repository removed."
    fi
fi

echo -e "${GREEN}Uninstall complete. Original network settings restored.${PLAIN}"
