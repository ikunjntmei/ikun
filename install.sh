#!/usr/bin/env bash
set -e

apt-get update -y && apt-get install -y wget xz-utils util-linux || yum install -y wget xz util-linux

TARGET_DISK=$(lsblk -ndo PKNAME $(findmnt -n -o SOURCE /) 2>/dev/null || findmnt -n -o SOURCE / | sed -r 's/p?[0-9]+$//')
TARGET_DISK=$(echo "$TARGET_DISK" | sed 's|^/dev/||')
echo "=== 检测到主系统盘为: /dev/$TARGET_DISK ==="

echo 1 > /proc/sys/kernel/sysrq

IMAGE_URL="https://gh.52056789.xyz/https://github.com/ikunjntmei/ikun/releases/download/latest/debian12-amd64.img.xz"
echo "=== 正在写入 Debian 12 镜像，请勿切断电源... ==="
wget -qO- "$IMAGE_URL" | xzcat | dd of="/dev/$TARGET_DISK" bs=4M status=progress

sync
echo "=== 写入完成，系统立即重启 ==="
echo b > /proc/sysrq-trigger
