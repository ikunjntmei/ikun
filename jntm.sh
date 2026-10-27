cat << 'EOF' > /root/reinstall.sh
#!/bin/bash
export tmpVER='amd64'
export tmpDIST='bookworm'
export Relese='Debian'
export sshPORT='22'
export ipDNS='8.8.8.8'
export myPASSWORD='$1$dHrZeCtS$CgyDymS3YgpfZa1bHDmlp.'

[[ "$EUID" -ne '0' ]] && echo "Error: This script must be run as root!" && exit 1

echo "==> [1/4] 安装必要工具依赖..."
apt-get update -y && apt-get install -y wget cpio gzip iproute2 grub2-common || yum install -y wget cpio gzip iproute grub2-tools

echo "==> [2/4] 获取当前网络参数..."
MAIN_IF=$(ip route show default | awk '/default/ {print $5}' | head -n1)
iAddr=$(ip -4 addr show dev "$MAIN_IF" | grep -w inet | head -n1 | awk '{print $2}')
IPv4=$(echo "$iAddr" | cut -d'/' -f1)
PREFIX=$(echo "$iAddr" | cut -d'/' -f2)
GATE=$(ip route show default | awk '/default/ {print $3}' | head -n1)

case $PREFIX in
    8)  MASK="255.0.0.0" ;;
    16) MASK="255.255.0.0" ;;
    24) MASK="255.255.255.0" ;;
    25) MASK="255.255.255.128" ;;
    26) MASK="255.255.255.192" ;;
    27) MASK="255.255.255.224" ;;
    28) MASK="255.255.255.240" ;;
    29) MASK="255.255.255.248" ;;
    30) MASK="255.255.255.252" ;;
    *)  MASK="255.255.255.0" ;;
esac

echo "    网卡: $MAIN_IF | 本机 IP: $IPv4 | 网关: $GATE"

echo "==> [3/4] 下载官方 Netboot 内核并注入无人值守配置..."
LinuxMirror="http://deb.debian.org/debian"
wget --no-check-certificate -qO '/tmp/initrd.img' "${LinuxMirror}/dists/${tmpDIST}/main/installer-${tmpVER}/current/images/netboot/debian-installer/${tmpVER}/initrd.gz"
wget --no-check-certificate -qO '/tmp/vmlinuz' "${LinuxMirror}/dists/${tmpDIST}/main/installer-${tmpVER}/current/images/netboot/debian-installer/${tmpVER}/linux"

rm -rf /tmp/boot && mkdir -p /tmp/boot && cd /tmp/boot
mv -f /tmp/initrd.img /tmp/initrd.img.gz
gzip -d < /tmp/initrd.img.gz | cpio --extract --verbose --make-directories --no-absolute-filenames >>/dev/null 2>&1

cat >/tmp/boot/preseed.cfg<<PRESEED_CONF
d-i debian-installer/locale string en_US.UTF-8
d-i debian-installer/country string US
d-i debian-installer/language string en
d-i console-setup/layoutcode string us
d-i keyboard-configuration/xkb-keymap string us

d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean false
d-i netcfg/get_ipaddress string $IPv4
d-i netcfg/get_netmask string $MASK
d-i netcfg/get_gateway string $GATE
d-i netcfg/get_nameservers string $ipDNS
d-i netcfg/confirm_static boolean true

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password $myPASSWORD
d-i user-setup/allow-password-weak boolean true

d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i clock-setup/ntp boolean false

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/mount_style select uuid
d-i partman/choose_partition select finish
d-i partman-auto/method string regular
d-i partman-auto/init_automatically_partition select Guided - use entire disk
d-i partman-auto/choose_recipe select All files in one partition (recommended for new users)
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

tasksel tasksel/first multiselect minimal
d-i pkgsel/include string openssh-server curl
d-i pkgsel/upgrade select none

d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/reboot boolean true

d-i preseed/late_command string \\
sed -ri 's/^#?Port.*/Port 22/g' /target/etc/ssh/sshd_config; \\
sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/g' /target/etc/ssh/sshd_config; \\
sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/g' /target/etc/ssh/sshd_config;
PRESEED_CONF

find . | cpio -H newc --create --verbose | gzip -9 > /tmp/initrd.img
cp -f /tmp/initrd.img /boot/initrd.img
cp -f /tmp/vmlinuz /boot/vmlinuz

echo "==> [4/4] 配置 GRUB 引导..."
GRUBFILE=$(find /boot -type f -name "grub.cfg" 2>/dev/null | head -n1)
if [ -n "$GRUBFILE" ]; then
    sed -i '/menuentry.*Install Debian 12/,$d' "$GRUBFILE"
    cat <<'GRUB_CONF' >> "$GRUBFILE"
menuentry 'Install Debian 12' {
    insmod ext2
    set root=(hd0,1)
    linux /boot/vmlinuz auto=true priority=critical
    initrd /boot/initrd.img
}
GRUB_CONF
fi

which update-grub >/dev/null 2>&1 && update-grub || grub2-mkconfig -o /boot/grub2/grub.cfg
which grub-reboot >/dev/null 2>&1 && grub-reboot 'Install Debian 12' || grub2-reboot 'Install Debian 12'

echo "=========================================================="
echo "写入成功！3 秒后自动重启开始安装 Debian 12..."
echo "安装后默认密码: abc123456"
echo "=========================================================="
sleep 3
reboot
EOF
bash /root/reinstall.sh