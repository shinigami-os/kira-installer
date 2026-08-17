#!/bin/sh

set -e

TARGET_DISK=""
TARGET_DISK_SHORT=""
ESP_PART=""
ROOT_PART=""
SWAP_PART=""
PARTITION_MODE=""
ESP_EXTERNAL=0
MOUNT_POINT="/mnt"
KERNEL_IMAGE="/installer/bzImage"
INITRAMFS_IMAGE="/installer/initramfs.cpio.gz"
PACKAGES="shadow zsh zsh-plugins kira-branding kira-seat kira-login kira-net kira-session-bus make zlib flex bison pkgconf util-linux os-prober grub efivar efibootmgr nano sudo build-essential"
PACKAGES_SWAYFX="kira-desktop-swayFX netsurf git greetd"
PACKAGES_SLEEX="kira-desktop-sleex netsurf git greetd"
TARBALL="/installer/kira-base.tar.gz"
KIRA_TIER=$(cat /etc/kira-tier 2>/dev/null || echo "server")

check_root() {
    echo "Checking root..."
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1  
    fi
}

network_setup() {
    echo "Network setup..."
    nmcli device status
    read -p "Enter network interface: " NETWORK_INTERFACE
    echo
    if [ -d "/sys/class/net/$NETWORK_INTERFACE/wireless" ]; then
        echo "Wireless setup..."
        nmcli device wifi rescan ifname "$NETWORK_INTERFACE"
        sleep 2
        nmcli device wifi list ifname "$NETWORK_INTERFACE"
        read -p "Enter wireless SSID: " WIRELESS_SSID
        nmcli --ask device wifi connect "$WIRELESS_SSID" ifname "$NETWORK_INTERFACE"
    else
        echo "Ethernet setup..."
        nmcli device connect "$NETWORK_INTERFACE"
    fi
    set +e
    ping -c 3 8.8.8.8
    set -e
}

select_partition_mode() {
    echo "Partition mode selection..."
    read -p "Enter 1 for guided - whole disk | 2 for guided - use free space | 3 for full manual (not implemented): " PARTITION_MODE
    case "$PARTITION_MODE" in
        1) select_disk && confirm_disk && write_partition ;;
        2) select_disk && confirm_free_space && format_free_space ;;
        3) echo "Full manual mode not implemented yet. Aborting."; exit 1 ;;
        *) echo "Invalid selection. Aborting."; exit 1 ;;
    esac
}

get_live_disk() {
    # best-effort: find the physical disk backing the live/installer medium
    # (e.g. the boot USB) so we can warn/refuse if it's selected as the target
    LIVE_SRC=$(findmnt -no SOURCE /installer 2>/dev/null || findmnt -no SOURCE / 2>/dev/null)
    [ -z "$LIVE_SRC" ] && return 0
    LIVE_SRC=$(readlink -f "$LIVE_SRC" 2>/dev/null || echo "$LIVE_SRC")
    lsblk -no PKNAME "$LIVE_SRC" 2>/dev/null | head -1
}

select_disk() {
    echo "Disk selection..."
    lsblk -d -o NAME,SIZE,MODEL
    LIVE_DISK=$(get_live_disk)
    if [ -n "$LIVE_DISK" ]; then
        echo "(note: $LIVE_DISK appears to be the live/installer medium itself)"
    fi
    read -p "Enter disk name (e.g. sda, nvme0n1): " TARGET_DISK_SHORT
    TARGET_DISK="/dev/$TARGET_DISK_SHORT"
    if [ ! -b "$TARGET_DISK" ]; then
        echo "Error: $TARGET_DISK is not a valid block device."
        exit 1
    fi
    if [ -n "$LIVE_DISK" ] && [ "$TARGET_DISK_SHORT" = "$LIVE_DISK" ]; then
        echo "/!\ $TARGET_DISK looks like the live/installer medium you booted from, not an install target. /!\ "
        read -p "Type 'yes-erase-live-media' to proceed anyway, or anything else to abort: " LIVE_OVERRIDE
        if [ "$LIVE_OVERRIDE" != "yes-erase-live-media" ]; then
            echo "Aborting."
            exit 1
        fi
    fi
}

confirm_disk() {
    echo
    echo "About to COMPLETELY WIPE and repartition $TARGET_DISK:"
    lsblk "$TARGET_DISK" -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
    echo
    echo "/!\ ALL DATA on $TARGET_DISK will be permanently destroyed. /!\ "
    read -p "Type the disk name ($TARGET_DISK_SHORT) to confirm, or anything else to abort: " CONFIRM
    if [ "$CONFIRM" != "$TARGET_DISK_SHORT" ]; then
        echo "Aborting."
        exit 1
    fi
}

confirm_free_space() {
    echo
    echo "Current layout of $TARGET_DISK:"
    lsblk "$TARGET_DISK" -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
    echo
    echo "/!\ Confirm ? New partitions will be created in the free space on $TARGET_DISK. Existing partitions are left untouched. /!\ "
    read -p "Type the disk name ($TARGET_DISK_SHORT) to confirm, or anything else to abort: " CONFIRM
    if [ "$CONFIRM" != "$TARGET_DISK_SHORT" ]; then
        echo "Aborting."
        exit 1
    fi
}

find_esp() {
    echo "Finding ESP partition..."
    ESP_NUM=$(parted -s "$TARGET_DISK" print | awk '/esp/{print $1}' | head -1)
    if [ -n "$ESP_NUM" ]; then
        case "$TARGET_DISK" in
            *[0-9]) PART_PREFIX="${TARGET_DISK}p" ;;
            *)      PART_PREFIX="${TARGET_DISK}" ;;
        esac
        ESP_PART="${PART_PREFIX}${ESP_NUM}"
        return
    fi
    TARGET_SHORT=$(basename "$TARGET_DISK")
    for i in $(lsblk -d -o NAME --noheadings); do
        [ "$i" = "$TARGET_SHORT" ] && continue
        ESP_NUM=$(parted -s "/dev/$i" print 2>/dev/null | awk '/esp/{print $1}' | head -1)
        if [ -n "$ESP_NUM" ]; then
            ESP_EXTERNAL=1
            case "/dev/$i" in
                *[0-9]) EXT_PREFIX="/dev/${i}p" ;;
                *)      EXT_PREFIX="/dev/$i" ;;
            esac
            ESP_PART="${EXT_PREFIX}${ESP_NUM}"
            return
        fi
    done
    read -p "ESP partition not found. Enter full path (e.g. /dev/sda1) or press enter to abort: " ESP_PART
    if [ -z "$ESP_PART" ]; then
        echo "Aborting."
        exit 1
    fi
    ESP_EXTERNAL=1
}

format_free_space() {
    FREE=$(parted -s "$TARGET_DISK" unit MiB print free \
        | grep "Free Space" \
        | awk '{gsub(/MiB/,""); print $1, $2, $3}' \
        | sort -k3 -n \
        | tail -1)
    START=$(echo "$FREE" | awk '{print $1}')
    END=$(echo "$FREE" | awk '{print $2}')
    SIZE=$(echo "$FREE" | awk '{print $3}')

    if [ -z "$START" ]; then
        echo "No free space found on $TARGET_DISK. Aborting."
        exit 1
    fi
    # START/END are already MiB values here (units stripped above), so this
    # is a straight MiB comparison: require at least 15GiB of free space,
    # enough for a minimal Kira root without being an unreasonably high bar
    if [ $((END - START)) -lt 15360 ]; then
        echo "Not enough free space on $TARGET_DISK (need at least 15GiB, found $(((END - START) / 1024))GiB). Aborting."
        exit 1
    fi

    echo "Largest free region found: ${START}MiB - ${END}MiB ($(((END - START) / 1024))GiB)"
    LAST_PART=$(parted -s "$TARGET_DISK" print | awk '/^ [0-9]/{print $1}' | sort -n | tail -1)

    read -p "Do you want a swap partition ? (y/n): " CONFIRM_SWAP

    echo "Partitioning..."
    case "$TARGET_DISK" in
        *[0-9]) PART_PREFIX="${TARGET_DISK}p" ;;
        *)      PART_PREFIX="${TARGET_DISK}" ;;
    esac
    if [ "$CONFIRM_SWAP" = "y" ]; then
        read -p "Enter swap size (in MiB): " SWAP_SIZE
        parted -s "$TARGET_DISK" mkpart swap linux-swap "${START}MiB" "$((START + SWAP_SIZE))MiB"
        SWAP_PART="${PART_PREFIX}$((LAST_PART + 1))"
        parted -s "$TARGET_DISK" mkpart root ext4 "$((START + SWAP_SIZE))MiB" "${END}MiB"
        ROOT_PART="${PART_PREFIX}$((LAST_PART + 2))"
    else
        parted -s "$TARGET_DISK" mkpart root ext4 "${START}MiB" "${END}MiB"
        ROOT_PART="${PART_PREFIX}$((LAST_PART + 1))"
    fi
    find_esp
}

write_partition() {
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
    if [ "$PARTITION_MODE" = "1" ]; then
        mkfs.fat -F 32 "$ESP_PART"
    fi
    mkfs.ext4 -F "$ROOT_PART"
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
    if [ "$KIRA_TIER" = "desktop" ]; then
        mkdir -p "$MOUNT_POINT/var/lib/NetworkManager"
        chmod 755 "$MOUNT_POINT/var/lib/NetworkManager"
    fi
    chmod 1777 "$MOUNT_POINT/tmp"
    chown root:root "$MOUNT_POINT/var/empty"
    echo "$KIRA_TIER" > "$MOUNT_POINT/etc/kira-tier"
}

remove_live_user() {
    if [ "$KIRA_TIER" = "desktop" ]; then
        echo "Removing live user..."
        sed -i '/^kira:/d' "$MOUNT_POINT/etc/passwd"
        sed -i '/^kira:/d' "$MOUNT_POINT/etc/shadow"
        sed -i '/^kira:/d' "$MOUNT_POINT/etc/group"
        rm -rf "$MOUNT_POINT/home/kira"
    fi
}

copy_kernel() {
    echo "Copying kernel..."
    KERNEL_VERSION=$(cat /proc/version | awk '{print $3}')
    cp "$KERNEL_IMAGE" "$MOUNT_POINT/boot/vmlinuz-$KERNEL_VERSION"
    echo "Copying initramfs..."
    cp "$INITRAMFS_IMAGE" "$MOUNT_POINT/boot/initrd.img-$KERNEL_VERSION"
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
    read -s -p "Enter root password: " ROOT_PASS
    echo
    echo "root:$ROOT_PASS" | chroot $MOUNT_POINT /usr/sbin/chpasswd
    echo "User setup..."
    read -p "Enter username: " USERNAME
    if [ -z "$USERNAME" ]; then
        USERNAME="kira"
    fi
    chroot $MOUNT_POINT /usr/sbin/useradd -m -s /usr/bin/zsh -G wheel,video,input,audio "$USERNAME"
    read -s -p "Enter password for $USERNAME: " USER_PASS
    echo
    echo "$USERNAME:$USER_PASS" | chroot $MOUNT_POINT /usr/sbin/chpasswd
}

chroot_setup() {
    echo "Binding Virtual File Systems..."
    mount --bind /dev $MOUNT_POINT/dev
    mount --bind /proc $MOUNT_POINT/proc
    mount --bind /sys $MOUNT_POINT/sys
    mount --bind /sys/firmware/efi/efivars $MOUNT_POINT/sys/firmware/efi/efivars
    cp /etc/resolv.conf $MOUNT_POINT/etc/resolv.conf
}

select_tier() {
    echo "Select installation tier:"
    read -p "Enter 1 for desktop (Sleex) | 2 for desktop (SwayFX)  | 3 for server: " TIER_CHOICE
    case "$TIER_CHOICE" in
        1) KIRA_TIER="desktop-sleex";;
        2) KIRA_TIER="desktop-swayfx";;
        3) KIRA_TIER="server";;
        *) echo "Invalid choice, defaulting to server."; KIRA_TIER="server";;
    esac

    if [ "$KIRA_TIER" = "desktop-sleex" ]; then
        mkdir -p "$MOUNT_POINT/root/.config/kira-desktop"
        echo "sleex" > "$MOUNT_POINT/root/.config/kira-desktop/active-de"
        echo "kira-default" > "$MOUNT_POINT/root/.config/kira-desktop/current-theme"
        mkdir -p "$MOUNT_POINT/home/$USERNAME/.config/kira-desktop"
        echo "sleex" > "$MOUNT_POINT/home/$USERNAME/.config/kira-desktop/active-de"
        echo "kira-default" > "$MOUNT_POINT/home/$USERNAME/.config/kira-desktop/current-theme"
    fi

    if [ "$KIRA_TIER" = "desktop-swayfx" ]; then
        mkdir -p "$MOUNT_POINT/root/.config/kira-desktop"
        echo "swayFX" > "$MOUNT_POINT/root/.config/kira-desktop/active-de"
        echo "kira-default" > "$MOUNT_POINT/root/.config/kira-desktop/current-theme"
        mkdir -p "$MOUNT_POINT/home/$USERNAME/.config/kira-desktop"
        echo "swayFX" > "$MOUNT_POINT/home/$USERNAME/.config/kira-desktop/active-de"
        echo "kira-default" > "$MOUNT_POINT/home/$USERNAME/.config/kira-desktop/current-theme"
    fi
}

has_intel_wifi() {
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = "0x8086" ] || continue
        case "$(cat "$d/class" 2>/dev/null)" in 0x028*) return 0 ;; esac
    done
    return 1
}

has_nvidia_gpu() {
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = "0x10de" ] || continue
        case "$(cat "$d/class" 2>/dev/null)" in 0x03*) return 0 ;; esac
    done
    return 1
}

packages_install() {
    echo "Installing base packages..."
    chroot $MOUNT_POINT flux update
    for pkg in $PACKAGES; do
        chroot $MOUNT_POINT flux install -y "$pkg"
    done
    if [ "$KIRA_TIER" = "desktop-sleex" ]; then
        echo "Installing desktop packages (Sleex)..."
        for pkg in $PACKAGES_SLEEX; do
            chroot $MOUNT_POINT flux install -y "$pkg"
        done
    fi
    if [ "$KIRA_TIER" = "desktop-swayfx" ]; then
        echo "Installing desktop packages (SwayFX)..."
        for pkg in $PACKAGES_SWAYFX; do
            chroot $MOUNT_POINT flux install -y "$pkg"
        done
    fi
    if has_intel_wifi; then
        echo "Intel WiFi detected, installing iwlwifi-firmware..."
        chroot $MOUNT_POINT flux install -y iwlwifi-firmware
    fi
    if has_nvidia_gpu; then
        echo "NVIDIA GPU detected, installing nouveau-firmware..."
        chroot $MOUNT_POINT flux install -y nouveau-firmware
    fi
}

bootloader_install() {
    if [ "$PARTITION_MODE" = "1" ]; then
        echo "Installing GRUB..."
        chroot $MOUNT_POINT grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Kira Linux"
        chroot $MOUNT_POINT grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "Updating existing bootloader..."
        if [ "$ESP_EXTERNAL" = "1" ]; then
            mount "$ESP_PART" "$MOUNT_POINT/boot/efi"
            chroot $MOUNT_POINT grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Kira Linux"
            chroot $MOUNT_POINT grub-mkconfig -o /boot/grub/grub.cfg
            umount "$MOUNT_POINT/boot/efi"
        else
            chroot $MOUNT_POINT grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Kira Linux"
            chroot $MOUNT_POINT grub-mkconfig -o /boot/grub/grub.cfg
        fi
    fi
}

chroot_cleanup() {
    echo "Unbinding Virtual File Systems..."
    umount $MOUNT_POINT/sys/firmware/efi/efivars
    umount $MOUNT_POINT/sys
    umount $MOUNT_POINT/proc
    umount $MOUNT_POINT/dev
}

unmount_partition() {
    echo "Partition unmounting..."
    if [ "$ESP_EXTERNAL" = "0" ] || mountpoint -q "$MOUNT_POINT/boot/efi"; then
        umount "$MOUNT_POINT/boot/efi"
    fi
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
    select_partition_mode
    format_partition
    mount_partition
    copy_tarball
    remove_live_user
    copy_kernel
    fstab_entry
    set_hostname
    chroot_setup
    user_setup
    select_tier
    packages_install
    bootloader_install
    chroot_cleanup
    unmount_partition
    finish
}

main