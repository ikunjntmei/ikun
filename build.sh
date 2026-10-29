#!/usr/bin/env bash
set -e

IMAGE_NAME="debian12-amd64.img"
ROOT_PASS="${DEFAULT_PASS:-abc123456}"
TARGET_DIR="/mnt/target"

echo "=== 安装构建依赖 ==="
apt-get update -y
apt-get install -y debootstrap parted dosfstools e2fsprogs xz-utils kpartx grub-pc-bin grub-efi-amd64-bin curl

echo "=== 创建 2.5GB 虚拟磁盘并划分 GPT 分区 ==="
dd if=/dev/zero of=${IMAGE_NAME} bs=1M count=2560
LOOP_DEV=$(losetup -Pf --show ${IMAGE_NAME})

parted -s "$LOOP_DEV" mklabel gpt
parted -s "$LOOP_DEV" mkpart bios 1MiB 3MiB
parted -s "$LOOP_DEV" set 1 bios_grub on
parted -s "$LOOP_DEV" mkpart efi fat32 3MiB 203MiB
parted -s "$LOOP_DEV" set 2 boot on
parted -s "$LOOP_DEV" set 2 esp on
parted -s "$LOOP_DEV" mkpart root ext4 203MiB 100%

mkfs.fat -F32 "${LOOP_DEV}p2"
mkfs.ext4 -F -L "ROOTFS" "${LOOP_DEV}p3"

mkdir -p ${TARGET_DIR}
mount "${LOOP_DEV}p3" ${TARGET_DIR}
mkdir -p ${TARGET_DIR}/boot/efi
mount "${LOOP_DEV}p2" ${TARGET_DIR}/boot/efi

echo "=== 部署基础系统 ==="
debootstrap --arch=amd64 bookworm ${TARGET_DIR} https://deb.debian.org/debian/

for d in /dev /dev/pts /proc /sys /run; do
  mount --bind "$d" "${TARGET_DIR}$d"
done

echo "=== 进入 chroot 配置驱动、网络与引导 ==="
cat << EOF | chroot ${TARGET_DIR} /bin/bash
set -e

cat << 'SOURCES' > /etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
SOURCES

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  linux-image-cloud-amd64 grub-pc grub-efi-amd64 openssh-server \
  systemd-networkd systemd-resolved cloud-guest-utils curl

# 注入 AWS ENA / VirtIO / NVMe 驱动
cat << 'MODULES' >> /etc/initramfs-tools/modules
nvme
xen-blkfront
virtio_blk
virtio_net
ena
MODULES
update-initramfs -u -k all

# 设置 Root 密码与 SSH 密码登录放行
echo "root:${ROOT_PASS}" | chpasswd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config

# 配置全网卡通用 DHCP
cat << 'NET' > /etc/systemd/network/10-dhcp.network
[Match]
Name=en* eth*

[Network]
DHCP=yes
NET
systemctl enable systemd-networkd
systemctl enable systemd-resolved

# 挂载表
cat << 'FSTAB' > /etc/fstab
LABEL=ROOTFS    /           ext4    defaults,noatime    0 1
FSTAB
EFI_UUID=\$(blkid -s UUID -o value \$(df --output=source /boot/efi | tail -1))
echo "UUID=\$EFI_UUID  /boot/efi  vfat  defaults,nofail  0 2" >> /etc/fstab

# GRUB 串口控制台与引导安装（双引导）
cat << 'GRUB' > /etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR="Debian"
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200 rootdelay=10"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB

grub-install --target=i386-pc --recheck ${LOOP_DEV}
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck --no-nvram
mkdir -p /boot/efi/EFI/boot
cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/boot/bootx64.efi
update-grub

# 开机自启自动扩容磁盘服务
cat << 'EXPAND' > /etc/systemd/system/expand-root.service
[Unit]
Description=Expand root partition on first boot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "DISK=\\\$(findmnt -n -o SOURCE / | sed -r 's/p?[0-9]+\\\$//'); PART=\\\$(findmnt -n -o SOURCE / | grep -o '[0-9]*\\\$'); growpart \\\$DISK \\\$PART || true; resize2fs /dev/disk/by-label/ROOTFS || true"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EXPAND
systemctl enable expand-root.service
EOF

echo "=== 卸载设备与打包压缩 ==="
umount ${TARGET_DIR}/boot/efi
for d in run sys proc dev/pts dev; do
  umount ${TARGET_DIR}/$d
done
umount ${TARGET_DIR}
losetup -d "$LOOP_DEV"

xz -z -9 -T0 "${IMAGE_NAME}"