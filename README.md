# QEMU Linux Installation Scripts

Automated scripts to install Linux distributions in QEMU VMs from an Ubuntu live environment.

## Overview

This repository contains scripts that install Linux distributions from within an Ubuntu live ISO running in a QEMU VM. The scripts handle partitioning, installation, and bootloader configuration automatically.

### Available Scripts

- `arch.sh` - Installs Arch Linux using bootstrap
- `void.sh` - Installs Void Linux using xbps-static

## Features

- **Automatic disk detection** - Detects VirtIO, SATA, and NVMe disks
- **No swap partition** - Uses entire disk for boot and root partitions
- **VirtIO support** - Properly configures kernel modules for QEMU VirtIO
- **Bootloader setup** - GRUB installation and configuration
- **Network-ready** - dhcpcd enabled and configured
- **Minimal installation** - Only essential packages

## Prerequisites

### Host System Requirements

- QEMU/KVM installed
- Ubuntu live ISO (20.04 or later recommended)
- Sufficient disk space for the VM

### Creating the QEMU VM

1. **Create a virtual disk:**
   ```bash
   qemu-img create -f qcow2 mydisk.qcow2 50G
   ```

2. **Boot Ubuntu live ISO:**
   ```bash
   qemu-system-x86_64 \
     -enable-kvm \
     -m 4G \
     -cpu host \
     -smp 4 \
     -drive file=mydisk.qcow2,if=virtio \
     -cdrom ubuntu-22.04-live-server-amd64.iso \
     -boot d \
     -net nic,model=virtio \
     -net user
   ```

3. **Boot into Ubuntu live environment** (choose "Try Ubuntu" or similar)

## Usage

### Step 1: Transfer Script to VM

From the Ubuntu live environment, download the script:

```bash
# Using wget (if you have network and the script hosted)
wget https://your-host/install-arch-in-qemu.sh
# or
wget https://your-host/install-void-in-qemu.sh

# Or copy-paste the script content into a new file
nano install-arch-in-qemu.sh
# (paste content, save with Ctrl+O, exit with Ctrl+X)
```

Make the script executable:
```bash
chmod +x install-arch-in-qemu.sh
# or
chmod +x install-void-in-qemu.sh
```

### Step 2: Run Installation

**For Arch Linux:**
```bash
sudo bash install-arch-in-qemu.sh
```

**For Void Linux:**
```bash
sudo bash install-void-in-qemu.sh
```

The script will:
1. Detect the disk (e.g., `/dev/vda`)
2. Warn you about data loss and wait for confirmation
3. Partition and format the disk
4. Download and install the base system
5. Configure the system and install GRUB
6. Complete installation

### Step 3: Boot Into New System

1. Shut down the VM
2. Remove the Ubuntu ISO from boot order
3. Restart the VM:
   ```bash
   qemu-system-x86_64 \
     -enable-kvm \
     -m 4G \
     -cpu host \
     -smp 4 \
     -drive file=mydisk.qcow2,if=virtio \
     -net nic,model=virtio \
     -net user
   ```

## What Gets Installed

### Arch Linux Installation

**Partitions:**
- `/dev/vda1` - 512MB ext4 boot partition
- `/dev/vda2` - Remaining space for root partition

**Packages:**
- base
- linux
- linux-firmware
- vim
- dhcpcd
- grub

**Configuration:**
- Hostname: `archlinux-qemu`
- Locale: `en_US.UTF-8`
- Timezone: `UTC`
- Root password: `root` (change immediately!)
- VirtIO modules in initramfs

### Void Linux Installation

**Partitions:**
- `/dev/vda1` - 512MB ext4 boot partition
- `/dev/vda2` - Remaining space for root partition

**Packages:**
- base-system
- linux
- linux-firmware
- grub
- vim
- dhcpcd

**Configuration:**
- Hostname: `voidlinux-qemu`
- Locale: `en_US.UTF-8`
- Root password: `root` (change immediately!)
- Init system: runit
- VirtIO modules in dracut config

## Post-Installation

### First Boot - Change Root Password

```bash
# Log in as root with password: root
passwd
# Enter a new secure password
```

### Update System

**Arch Linux:**
```bash
pacman -Syu
```

**Void Linux:**
```bash
xbps-install -Su
```

### Create a Regular User

**Arch Linux:**
```bash
useradd -m -G wheel username
passwd username
pacman -S sudo
EDITOR=vim visudo  # Uncomment %wheel line
```

**Void Linux:**
```bash
useradd -m -G wheel username
passwd username
xbps-install -S sudo
EDITOR=vim visudo  # Uncomment %wheel line
```

### Install Additional Software

**Arch Linux:**
```bash
pacman -S <package-name>
```

**Void Linux:**
```bash
xbps-install -S <package-name>
```

## Troubleshooting

### Disk Not Detected

If the script doesn't detect your disk:
1. Check available disks: `lsblk`
2. Edit the script and add your disk to the detection loop
3. Ensure VirtIO is used in QEMU (`if=virtio`)

### GRUB Installation Fails

If GRUB fails to install:
1. Check the disk device is correct
2. Ensure you're running as root
3. Try manual GRUB installation after chrooting

### System Won't Boot

If the system drops to emergency shell:
1. Boot Ubuntu live ISO again
2. Mount the root partition: `mount /dev/vda2 /mnt`
3. Mount boot: `mount /dev/vda1 /mnt/boot`
4. Chroot and fix issues

**Arch Linux:**
```bash
arch-chroot /mnt
# Regenerate initramfs
mkinitcpio -P
# Reinstall GRUB
grub-install /dev/vda
grub-mkconfig -o /boot/grub/grub.cfg
```

**Void Linux:**
```bash
mount --bind /dev /mnt/dev
mount -t proc /proc /mnt/proc
mount -t sysfs /sys /mnt/sys
chroot /mnt
# Reconfigure system
xbps-reconfigure -fa
# Reinstall GRUB
grub-install /dev/vda
grub-mkconfig -o /boot/grub/grub.cfg
```

### Network Not Working

**Arch Linux:**
```bash
systemctl start dhcpcd
systemctl enable dhcpcd
```

**Void Linux:**
```bash
sv start dhcpcd
ln -s /etc/sv/dhcpcd /var/service/
```

## Technical Details

### Partition Layout

Both scripts create a simple 2-partition layout:
- Boot partition (512MB) - Contains kernel and GRUB files
- Root partition (remaining space) - Contains entire system
- **No swap partition** - Swap can be added as a file if needed later

### VirtIO Module Configuration

**Arch Linux (mkinitcpio):**
```
MODULES=(virtio virtio_blk virtio_pci virtio_net)
```

**Void Linux (dracut):**
```
add_drivers+=" virtio virtio_blk virtio_pci virtio_net "
```

### Adding Swap File (Optional)

If you need swap after installation:

```bash
# Create 2GB swap file
dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make permanent - add to /etc/fstab:
echo '/swapfile none swap defaults 0 0' >> /etc/fstab
```

## References

- [Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Void Linux Installation Guide](https://docs.voidlinux.org/installation/index.html)
- [QEMU VIRTIO Forum Post](https://bbs.archlinux.org/viewtopic.php?id=133623)
- [xbps-static Documentation](https://docs.voidlinux.org/xbps/troubleshooting/static.html)

## License

MIT License - Feel free to modify and distribute these scripts.
