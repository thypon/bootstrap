#!/bin/bash
set -e

# Script to install Void Linux from Ubuntu Live ISO running in QEMU VM
# This script should be run inside the Ubuntu live environment

echo "============================================"
echo "Void Linux QEMU Installation Script"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (use sudo)"
    exit 1
fi

# Detect VirtIO disk
DISK=""
for disk in /dev/vda /dev/sda /dev/nvme0n1; do
    if [ -b "$disk" ]; then
        DISK="$disk"
        echo "Found disk: $DISK"
        break
    fi
done

if [ -z "$DISK" ]; then
    echo "ERROR: No suitable disk found"
    exit 1
fi

# Get disk size
DISK_SIZE=$(lsblk -b -d -n -o SIZE "$DISK")
DISK_SIZE_GB=$((DISK_SIZE / 1024 / 1024 / 1024))
echo "Disk size: ${DISK_SIZE_GB}GB"

# Get available memory
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "Available memory: ${TOTAL_MEM}MB"

echo ""
echo "WARNING: This will ERASE ALL DATA on $DISK"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo "Step 1: Installing required packages..."
apt-get update
apt-get install -y wget ca-certificates

echo ""
echo "Step 2: Partitioning disk..."
# Clear partition table
wipefs -a "$DISK"

# Create partitions:
# - 512MB boot partition
# - Rest for root partition (no swap)

if [ "$DISK_SIZE_GB" -lt 5 ]; then
    echo "ERROR: Disk too small (minimum 5GB required)"
    exit 1
fi

echo "Creating partitions: 512MB boot, rest for root (no swap)"

# Partition the disk
if [[ "$DISK" == /dev/nvme* ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

# Use parted for cleaner partitioning
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 513MiB
parted -s "$DISK" set 1 boot on
parted -s "$DISK" mkpart primary ext4 513MiB 100%

# Wait for partitions to be ready
sleep 2
partprobe "$DISK"
sleep 2

echo ""
echo "Step 3: Formatting partitions..."
mkfs.ext4 -F "$PART1"
mkfs.ext4 -F "$PART2"

echo ""
echo "Step 4: Mounting partitions..."
mount "$PART2" /mnt
mkdir -p /mnt/boot
mount "$PART1" /mnt/boot

echo ""
echo "Step 5: Downloading xbps-static..."
cd /tmp
XBPS_STATIC_VERSION="latest"
XBPS_STATIC_URL="https://repo-default.voidlinux.org/static/xbps-static-latest.x86_64-musl.tar.xz"

echo "Downloading from: $XBPS_STATIC_URL"
wget -O xbps-static.tar.xz "$XBPS_STATIC_URL"

echo ""
echo "Step 6: Extracting xbps-static..."
tar -xf xbps-static.tar.xz
rm xbps-static.tar.xz

# Make xbps-static tools executable and available
chmod +x usr/bin/*
export PATH="/tmp/usr/bin:$PATH"

echo ""
echo "Step 7: Installing base system..."
# Set architecture for glibc system
export XBPS_ARCH=x86_64

# Set up Void Linux repository
REPO="https://repo-default.voidlinux.org/current"

# Install base system to /mnt
echo "Installing base packages..."
xbps-install.static -y -S -R "$REPO" -r /mnt \
    base-system \
    linux \
    linux-firmware \
    grub \
    vim \
    dhcpcd \
    sudo

echo ""
echo "Step 8: Configuring system..."

# Copy DNS configuration
mkdir -p /mnt/etc
cp /etc/resolv.conf /mnt/etc/

# Set hostname
echo "voidlinux-qemu" > /mnt/etc/hostname

# Configure hosts file
cat > /mnt/etc/hosts <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 voidlinux-qemu.localdomain voidlinux-qemu
EOF

# Create manager user
chroot /mnt useradd -m -G wheel manager
echo "manager:password" | chroot /mnt chpasswd
echo "Manager user created with password: password"

# Configure sudoers for wheel group
mkdir -p /mnt/etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel
chmod 440 /mnt/etc/sudoers.d/wheel

# Disable root login
chroot /mnt passwd -l root
echo "Root login disabled"

# Configure fstab
echo "Generating fstab..."
BOOT_UUID=$(blkid -s UUID -o value "$PART1")
ROOT_UUID=$(blkid -s UUID -o value "$PART2")

cat > /mnt/etc/fstab <<EOF
# <file system> <dir> <type> <options> <dump> <pass>
UUID=$ROOT_UUID / ext4 defaults 0 1
UUID=$BOOT_UUID /boot ext4 defaults 0 2
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
EOF

# Set locale
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/default/libc-locales
chroot /mnt xbps-reconfigure -f glibc-locales

# Configure dracut to include VirtIO modules
mkdir -p /mnt/etc/dracut.conf.d
cat > /mnt/etc/dracut.conf.d/virtio.conf <<EOF
add_drivers+=" virtio virtio_blk virtio_pci virtio_net "
EOF

echo ""
echo "Step 9: Installing and configuring GRUB..."
# Mount necessary filesystems for chroot
mount --bind /dev /mnt/dev
mount -t proc /proc /mnt/proc
mount -t sysfs /sys /mnt/sys

# Install GRUB
chroot /mnt grub-install "$DISK"
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Reconfigure all packages to ensure everything is set up
echo ""
echo "Step 10: Reconfiguring system packages..."
chroot /mnt xbps-reconfigure -fa

echo ""
echo "Step 11: Enabling services..."
# Enable essential services using runit
chroot /mnt ln -sf /etc/sv/dhcpcd /etc/runit/runsvdir/default/
chroot /mnt ln -sf /etc/sv/sshd /etc/runit/runsvdir/default/ 2>/dev/null || true

echo ""
echo "============================================"
echo "Installation Complete!"
echo "============================================"
echo ""
echo "IMPORTANT:"
echo "1. User: manager"
echo "2. Password: password"
echo "3. Hostname: voidlinux-qemu"
echo "4. Networking: dhcpcd is enabled"
echo "5. Init system: runit"
echo "6. Root login is DISABLED"
echo "7. Manager user has sudo access"
echo ""
echo "Unmounting filesystems..."
umount /mnt/dev
umount /mnt/proc
umount /mnt/sys
umount /mnt/boot
umount /mnt

echo ""
echo "You can now shut down the VM and boot from disk."
echo "Remove the Ubuntu ISO and restart the VM."
echo ""
echo "After booting into Void Linux:"
echo "  - Login as: manager / password"
echo "  - Change password: passwd"
echo "  - Update system: sudo xbps-install -Su"
echo "  - Install additional packages: sudo xbps-install <package>"
echo ""
