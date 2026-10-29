#!/usr/bin/env bash
set -e

# 1. 安装基础依赖
apt-get update -y && apt-get install -y wget xz-utils util-linux || yum install -y wget xz util-linux

# 2. 自动定位物理系统主盘
TARGET_DISK=$(lsblk -ndo PKNAME $(findmnt -n -o SOURCE /) 2>/dev/null || findmnt -n -o SOURCE / | sed -r 's/p?[0-9]+$//')
TARGET_DISK=$(echo "$TARGET_DISK" | sed 's|^/dev/||')
echo "=== 检测到主系统盘为: /dev/$TARGET_DISK ==="

# 3. 开启硬件强制重启权限
echo 1 > /proc/sys/kernel/sysrq

# 4. 加速拉取并写入最新镜像
IMAGE_URL="https://gh.52056789.xyz/https://github.com/ikunjntmei/ikun/releases/download/debian12-40857574615/debian12-amd64.img.xz"
echo "=== 正在写入 Debian 12 镜像，请勿切断电源... ==="
wget -qO- "$IMAGE_URL" | xzcat | dd of="/dev/$TARGET_DISK" bs=4M status=progress

# 5. 立即硬件重启
sync
echo "=== 写入完成，系统立即重启 ==="
echo b > /proc/sysrq-trigger
