#!/bin/bash
set -e

# Script to install Arch Linux from Ubuntu Live ISO running in QEMU VM
# This script should be run inside the Ubuntu live environment

echo "============================================"
echo "Arch Linux QEMU Installation Script"
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
apt-get install -y wget arch-install-scripts

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
echo "Step 5: Downloading Arch Linux bootstrap..."
cd /tmp
ARCH_VERSION=$(date +%Y.%m.01)
BOOTSTRAP_URL="https://mirrors.kernel.org/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"

echo "Downloading from: $BOOTSTRAP_URL"
wget -O archlinux-bootstrap.tar.zst "$BOOTSTRAP_URL"

echo ""
echo "Step 6: Extracting bootstrap..."
tar -xf archlinux-bootstrap.tar.zst
rm archlinux-bootstrap.tar.zst

echo ""
echo "Step 7: Setting up bootstrap environment..."
# Copy DNS configuration
cp /etc/resolv.conf root.x86_64/etc/resolv.conf

# Select a mirror
echo 'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch' > root.x86_64/etc/pacman.d/mirrorlist

echo ""
echo "Step 8: Installing base system..."
# Mount necessary filesystems for chroot
mount --bind /mnt root.x86_64/mnt

# Initialize pacman keyring and install base system
root.x86_64/bin/arch-chroot root.x86_64 /bin/bash <<'CHROOT_INSTALL'
set -e
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
pacman -Su --noconfirm
pacstrap /mnt base linux linux-firmware vim dhcpcd grub
CHROOT_INSTALL

echo ""
echo "Step 9: Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo ""
echo "Step 10: Configuring system..."
arch-chroot /mnt /bin/bash <<'CHROOT_CONFIG'
set -e

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "archlinux-qemu" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 archlinux-qemu.localdomain archlinux-qemu" >> /etc/hosts

# Configure mkinitcpio with VirtIO modules
sed -i 's/^MODULES=.*/MODULES=(virtio virtio_blk virtio_pci virtio_net)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "root:root" | chpasswd
echo ""
echo "Root password set to: root"
echo "CHANGE THIS AFTER FIRST LOGIN!"

# Enable networking
systemctl enable dhcpcd

# Install and configure GRUB
grub-install --target=i386-pc /dev/vda
grub-mkconfig -o /boot/grub/grub.cfg

CHROOT_CONFIG

echo ""
echo "============================================"
echo "Installation Complete!"
echo "============================================"
echo ""
echo "IMPORTANT:"
echo "1. Root password is set to: root"
echo "2. Change it immediately after first login!"
echo "3. Hostname: archlinux-qemu"
echo "4. Networking: dhcpcd is enabled"
echo ""
echo "Unmounting filesystems..."
umount -R /mnt

echo ""
echo "You can now shut down the VM and boot from disk."
echo "Remove the Ubuntu ISO and restart the VM."
echo ""
echo "After booting into Arch Linux:"
echo "  - Change root password: passwd"
echo "  - Update system: pacman -Syu"
echo "  - Create a user: useradd -m -G wheel username"
echo ""
