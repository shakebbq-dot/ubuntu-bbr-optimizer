#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'

echo -e "${RED}警告: 这将移除 bbr-optimizer 写入的所有优化配置。${PLAIN}"
read -p "确定要继续吗? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/bbr_install.sh" --uninstall
