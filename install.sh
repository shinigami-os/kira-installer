#!/bin/sh

set -e

TARGET_DISK=""
ESP_PART=""
ROOT_PART=""
SWAP_PART=""
MOUNT_POINT="/mnt"
TARBALL="/installer/kira-base.tar.gz"

check_root() {
    echo "Checking root..."
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1  
    fi
}

network_setup() {
    echo "Network setup..."
    ip link
    read -p "Enter network interface: " NETWORK_INTERFACE
    echo
    if [ -d "/sys/class/net/$NETWORK_INTERFACE/wireless" ]; then
        read -p "Enter wireless SSID: " WIRELESS_SSID
        read -s -p "Enter wireless password: " WIRELESS_PASSWORD
        wpa_passphrase "$WIRELESS_SSID" "$WIRELESS_PASSWORD" > /tmp/wpa.conf
        wpa_supplicant -B -i "$NETWORK_INTERFACE" -c "/tmp/wpa.conf"
        dhcpcd "$NETWORK_INTERFACE"
    else
        dhcpcd "$NETWORK_INTERFACE"
    fi
    set +e
    ping -c 3 8.8.8.8
    set -e
}

select_disk() {
    echo "Disk selection..."
    lsblk -d -o NAME,SIZE,MODEL
    read -p "Enter disk name (e.g. sda, nvme0n1): " TARGET_DISK
    TARGET_DISK="/dev/$TARGET_DISK"
    if [ ! -b "$TARGET_DISK" ]; then
        echo "Error: $TARGET_DISK is not a valid block device."
        exit 1
    fi
}

confirm_disk() {
    echo "/!\ Confirm ? The disk $TARGET_DISK will be wiped. /!\ "
    read -p "Confirm (type 'yes' to confirm): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborting."
        exit 1
    fi
}

select_partition() {
    echo "Partition selection..."
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    read -p "Do you want a swap partition ? (y/n): " CONFIRM_SWAP
    case "$TARGET_DISK" in
        *[0-9]) PART_PREFIX="${TARGET_DISK}p" ;;
        *)      PART_PREFIX="${TARGET_DISK}" ;;
    esac
    if [ "$CONFIRM_SWAP" = "y" ]; then
        read -p "Enter swap size (in MiB): " SWAP_SIZE
        parted -s "$TARGET_DISK" mkpart swap linux-swap 513MiB "$((513 + SWAP_SIZE))MiB"
        parted -s "$TARGET_DISK" mkpart root ext4 "$((513 + SWAP_SIZE))MiB" 100%
    else
        parted -s "$TARGET_DISK" mkpart root ext4 513MiB 100%
    fi
    ESP_PART="${PART_PREFIX}1"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        SWAP_PART="${PART_PREFIX}2"
        ROOT_PART="${PART_PREFIX}3"
    else
        ROOT_PART="${PART_PREFIX}2"
    fi
}

format_partition() {
    echo "Partition formatting..."
    mkfs.fat -F 32 "$ESP_PART"
    mkfs.ext4 "$ROOT_PART"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        mkswap "$SWAP_PART"
    fi
}

mount_partition() {
    echo "Partition mounting..."
    mkdir -p "$MOUNT_POINT"
    mount "$ROOT_PART" "$MOUNT_POINT"
    mkdir -p "$MOUNT_POINT/boot/efi"
    mount "$ESP_PART" "$MOUNT_POINT/boot/efi"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        swapon "$SWAP_PART"
    fi
}

copy_tarball() {
    echo "Installing base system..."
    tar -xzpf "$TARBALL" -C "$MOUNT_POINT" \
        --exclude=./tmp \
        --exclude=./proc \
        --exclude=./sys  \
        --exclude=./dev \
        --exclude=./mnt \
        --exclude=./run \
        --exclude=./var/cache/flux \
        --exclude=./var/lib/flux/installed
    mkdir -p "$MOUNT_POINT/tmp" \
        "$MOUNT_POINT/proc" \
        "$MOUNT_POINT/sys" \
        "$MOUNT_POINT/dev" \
        "$MOUNT_POINT/mnt" \
        "$MOUNT_POINT/run" \
        "$MOUNT_POINT/var/cache/flux" \
        "$MOUNT_POINT/var/lib/flux"
    chmod 1777 "$MOUNT_POINT/tmp"
}

fstab_entry() {
    echo "Creating fstab..."
    cat > "$MOUNT_POINT/etc/fstab" << EOF
# Kira Linux fstab
UUID=$(blkid -s UUID -o value $ROOT_PART)  /           ext4    defaults    0 1
UUID=$(blkid -s UUID -o value $ESP_PART)   /boot/efi   vfat    defaults    0 2
EOF
    if [ "$CONFIRM_SWAP" = "y" ]; then
        echo "UUID=$(blkid -s UUID -o value $SWAP_PART)  none  swap  sw  0 0" >> "$MOUNT_POINT/etc/fstab"
    fi
}

set_hostname() {
    echo "Setting hostname..."
    read -p "Enter hostname: " HOSTNAME
    if [ -z "$HOSTNAME" ]; then
        echo "Kira" > "$MOUNT_POINT/etc/hostname"
    else
        echo "$HOSTNAME" > "$MOUNT_POINT/etc/hostname"
    fi
}

user_setup() {
    echo "Root setup..."
    chroot $MOUNT_POINT passwd root
    echo "User setup..."
    read -p "Enter username: " USERNAME
    if [ -z "$USERNAME" ]; then
        USERNAME="kira"
    fi
    chroot $MOUNT_POINT useradd -m -s /bin/zsh "$USERNAME"
    chroot $MOUNT_POINT passwd "$USERNAME"
}

chroot_setup() {
    echo "Binding Virtual File Systems..."
    mount --bind /dev $MOUNT_POINT/dev
    mount --bind /proc $MOUNT_POINT/proc
    mount --bind /sys $MOUNT_POINT/sys
}

bootloader_install() {
    echo "Installing GRUB..."
    chroot $MOUNT_POINT flux install grub
    chroot $MOUNT_POINT grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Kira Linux"
    chroot $MOUNT_POINT grub-mkconfig -o /boot/grub/grub.cfg
}

chroot_cleanup() {
    echo "Unbinding Virtual File Systems..."
    umount $MOUNT_POINT/sys
    umount $MOUNT_POINT/proc
    umount $MOUNT_POINT/dev
}

unmount_partition() {
    echo "Partition unmounting..."
    umount "$MOUNT_POINT/boot/efi"
    umount "$MOUNT_POINT"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        swapoff "$SWAP_PART"
    fi
}

finish() {
    echo "Kira Linux installed successfully ^^"
    read -p "Reboot now? (y/n): " REBOOT
    if [ "$REBOOT" = "y" ]; then
        reboot
    else
        echo "You can reboot manually when ready."
    fi
}

main() {
    echo "Welcome to Kira Linux installer !"
    check_root
    network_setup
    select_disk
    confirm_disk
    select_partition
    format_partition
    mount_partition
    copy_tarball
    fstab_entry
    set_hostname
    user_setup
    chroot_setup
    bootloader_install
    chroot_cleanup
    unmount_partition
    finish
}

main