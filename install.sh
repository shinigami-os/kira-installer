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
PACKAGES="shadow shadow-login zsh kira-zsh-plugins kira-branding kira-seat kira-login kira-net kira-session-bus zlib flex bison pkgconf kira-basic-tools kira-build-essential os-prober grub grub-efi efivar efibootmgr nano sudo git chrony tzdata"
PACKAGES_SWAYFX="kira-desktop-swayFX netsurf git greetd"
PACKAGES_SLEEX="kira-desktop-sleex netsurf git greetd"
TARBALL="/installer/kira-base.tar.xz"
KIRA_TIER=$(cat /etc/kira-tier 2>/dev/null || echo "server")
# the live medium's own flavor ("desktop" vs "server"), distinct from $KIRA_TIER below once
# ask_tier() runs - copy_tarball/remove_live_user care about what this *live session* is
# (does it have a throwaway "kira" user and NetworkManager state to clean up/seed from),
# not which tier the user is installing
LIVE_ISO_TIER="$KIRA_TIER"

# Free-space measurement (phase 1) feeds the actual mkpart calls (phase 2) - kept as globals
# rather than re-running `parted print free` a second time, which also avoids any chance of
# the measured region changing between "we checked" and "we acted" (nothing else touches the
# disk during an install session, but there's no reason to rely on that twice when once works)
FREE_START=""
FREE_END=""

CONFIRM_SWAP="n"
SWAP_SIZE=""
HOSTNAME=""
USERNAME=""
ROOT_PASS=""
USER_PASS=""
TARGET_TZ=""

# set once mount_partition actually succeeds - the EXIT trap only attempts cleanup when
# there's something mounted to clean up, so a failure *before* that point (e.g. a bad answer
# during the question phase) doesn't print a confusing "cleaning up" message for nothing
MOUNTED=0

# ---- small helpers used throughout ----

# a visually distinct banner for each major phase, not a strict N/M counter - the exact step
# count shifts with user choices (partition mode, tier, swap y/n), so a real progress fraction
# would either be wrong half the time or need constant upkeep; a clear "==>" marker is honest
# about what it promises and still makes the transcript much easier to follow than the old
# plain "echo"-per-function style
announce() {
    echo
    echo "==> $1"
}

# the live environment's blkid is BusyBox's applet, which silently ignores -s/-o -
# "blkid -s UUID -o value $PART" was falling back to BusyBox's own default output
# (the full "/dev/X: UUID=\"...\" TYPE=\"...\"" line, not just the UUID), writing
# literal garbage like 'UUID=/dev/nvme0n1p2: UUID="..." TYPE="swap"' into fstab -
# invalid syntax that silently never activated swap on boot. Parsing that same
# default-format output by hand works on both BusyBox's blkid and util-linux's.
blkid_uuid() {
    blkid "$1" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p'
}

# retries a package install a few times before giving up for real - a single flaky connection
# blip partway through a long package list used to abort the whole install (disk already
# partitioned, base system already copied), throwing away everything up to that point over
# something that usually just needed a second attempt
chroot_flux_install() {
    pkg="$1"
    i=0
    while [ "$i" -lt 3 ]; do
        if chroot "$MOUNT_POINT" flux install -y "$pkg"; then
            return 0
        fi
        i=$((i + 1))
        [ "$i" -lt 3 ] && echo "flux install $pkg failed, retrying ($i/3)..."
        sleep 2
    done
    echo "Error: failed to install $pkg after 3 attempts. Aborting."
    exit 1
}

# best-effort unmount of everything this script might have mounted, run automatically on any
# failure after mount_partition succeeds - without this, a failed install left /mnt, the
# chroot bind-mounts, and swap all still active, so simply re-running the script to try again
# failed immediately (mkfs/mount refuse an already-mounted/active target) until the user
# unmounted everything by hand first
cleanup_on_exit() {
    ec=$?
    if [ "$ec" -ne 0 ] && [ "$MOUNTED" -eq 1 ]; then
        echo
        echo "Install failed (exit $ec) - unmounting so a retry doesn't need manual cleanup first..."
        umount "$MOUNT_POINT/sys/firmware/efi/efivars" 2>/dev/null
        umount "$MOUNT_POINT/sys" 2>/dev/null
        umount "$MOUNT_POINT/proc" 2>/dev/null
        umount "$MOUNT_POINT/dev/pts" 2>/dev/null
        umount "$MOUNT_POINT/dev" 2>/dev/null
        if [ "$ESP_EXTERNAL" = "0" ]; then
            umount "$MOUNT_POINT/boot/efi" 2>/dev/null
        fi
        umount "$MOUNT_POINT" 2>/dev/null
        if [ "$CONFIRM_SWAP" = "y" ] && [ -n "$SWAP_PART" ]; then
            swapoff "$SWAP_PART" 2>/dev/null
        fi
    fi
}
trap cleanup_on_exit EXIT

# prompts twice and requires a match, rather than silently accepting whatever was typed once -
# a single mistyped password used to become the actual (unusable, and unknown to the user)
# account password with no way to notice until the first login attempt failed
ask_password() {
    # $1 = variable name to set via eval (always a literal name this script controls itself,
    # never user input), $2 = label for the prompts
    while true; do
        read -s -p "Enter password for $2: " _pw1
        echo
        if [ -z "$_pw1" ]; then
            echo "Password cannot be empty."
            continue
        fi
        read -s -p "Retype password for $2: " _pw2
        echo
        if [ "$_pw1" != "$_pw2" ]; then
            echo "Passwords did not match, try again."
            continue
        fi
        eval "$1=\$_pw1"
        break
    done
}

check_root() {
    announce "Checking root..."
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
}

# Kira only ships grub-efi, not legacy BIOS grub - failing here with a clear message beats
# failing an hour later inside bootloader_install with a cryptic grub-install error, after
# every other step (partition, format, copy, packages) already succeeded
check_uefi() {
    announce "Checking boot mode..."
    if [ ! -d /sys/firmware/efi ]; then
        echo "Error: this system did not boot in UEFI mode (no /sys/firmware/efi)."
        echo "Kira's installer only supports UEFI installs (grub-efi) at this time."
        exit 1
    fi
}

select_keymap() {
    announce "Keyboard layout selection..."
    KEYMAP_LIB="/usr/share/kira-keymaps"
    # numbered off whatever the live image actually ships (same library
    # kira-branding installs into the target below), not a hardcoded list -
    # so this never drifts out of sync with what's actually available
    i=0
    KEYMAP_NAMES=""
    for f in "$KEYMAP_LIB"/*.bmap; do
        [ -f "$f" ] || continue
        i=$((i + 1))
        name=$(basename "$f" .bmap)
        KEYMAP_NAMES="$KEYMAP_NAMES $name"
        default_tag=""
        [ "$name" = "us" ] && default_tag=" (default)"
        echo "  $i) $name$default_tag"
    done
    read -p "Select a keyboard layout number, or press enter for us (QWERTY): " KEYMAP_NUM
    if [ -z "$KEYMAP_NUM" ]; then
        KEYMAP_CHOICE="us"
    else
        KEYMAP_CHOICE=$(echo "$KEYMAP_NAMES" | tr ' ' '\n' | sed -n "${KEYMAP_NUM}p")
        if [ -z "$KEYMAP_CHOICE" ]; then
            echo "Invalid selection, defaulting to us (QWERTY)."
            KEYMAP_CHOICE="us"
        fi
    fi
    # apply it to this live session too, so typing the hostname/passwords/wifi
    # SSID below already happens on the chosen layout, not just the installed one
    loadkmap < "$KEYMAP_LIB/$KEYMAP_CHOICE.bmap" 2>/dev/null || true
}

network_setup() {
    announce "Network setup..."
    nmcli device status
    read -p "Enter network interface: " NETWORK_INTERFACE
    echo
    if [ -d "/sys/class/net/$NETWORK_INTERFACE/wireless" ]; then
        echo "Wireless setup..."
        # -t gives an exact "connected"/"disconnected" field, unlike the
        # parenthesized nmcli device status output where a plain string
        # match on "connected" would also match "disconnected"
        WIFI_STATE=$(nmcli -t -f DEVICE,STATE device status | awk -F: -v dev="$NETWORK_INTERFACE" '$1 == dev { print $2 }')
        if [ "$WIFI_STATE" = "connected" ]; then
            echo "$NETWORK_INTERFACE is already connected to Wi-Fi, skipping network selection."
        else
            nmcli device wifi rescan ifname "$NETWORK_INTERFACE"
            sleep 2
            nmcli device wifi list ifname "$NETWORK_INTERFACE"
            read -p "Enter wireless SSID: " WIRELESS_SSID
            nmcli --ask device wifi connect "$WIRELESS_SSID" ifname "$NETWORK_INTERFACE"
        fi
    else
        echo "Ethernet setup..."
        nmcli device connect "$NETWORK_INTERFACE"
    fi
    set +e
    ping -c 3 8.8.8.8
    set -e
}

ask_partition_mode() {
    announce "Partition mode selection..."
    read -p "Enter 1 for guided - whole disk | 2 for guided - use free space | 3 for full manual (not implemented): " PARTITION_MODE
    case "$PARTITION_MODE" in
        1) select_disk; check_whole_disk_size; ask_swap ;;
        2) select_disk; measure_free_space; ask_swap ;;
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

# same 15GiB floor format_free_space already enforces for its (smaller, shared) target region -
# whole-disk mode had no equivalent check at all, so a disk that's simply too small to hold a
# minimal Kira install used to partition and format "successfully" and only fail confusingly
# later, deep into copy_tarball, with a plain ENOSPC
check_whole_disk_size() {
    DISK_MIB=$(parted -s "$TARGET_DISK" unit MiB print | awk -F': ' '/^Disk /{gsub(/MiB/,"",$2); print $2}')
    if [ -z "$DISK_MIB" ] || [ "$DISK_MIB" -lt 15360 ]; then
        echo "Error: $TARGET_DISK is too small (need at least 15GiB, found $(( ${DISK_MIB:-0} / 1024 ))GiB). Aborting."
        exit 1
    fi
}

measure_free_space() {
    FREE=$(parted -s "$TARGET_DISK" unit MiB print free \
        | grep "Free Space" \
        | awk '{gsub(/MiB/,""); print $1, $2, $3}' \
        | sort -k3 -n \
        | tail -1)
    FREE_START=$(echo "$FREE" | awk '{print $1}')
    FREE_END=$(echo "$FREE" | awk '{print $2}')

    if [ -z "$FREE_START" ]; then
        echo "No free space found on $TARGET_DISK. Aborting."
        exit 1
    fi
    # START/END are already MiB values here (units stripped above), so this
    # is a straight MiB comparison: require at least 15GiB of free space,
    # enough for a minimal Kira root without being an unreasonably high bar
    if [ $((FREE_END - FREE_START)) -lt 15360 ]; then
        echo "Not enough free space on $TARGET_DISK (need at least 15GiB, found $(((FREE_END - FREE_START) / 1024))GiB). Aborting."
        exit 1
    fi
    echo "Largest free region found: ${FREE_START}MiB - ${FREE_END}MiB ($(((FREE_END - FREE_START) / 1024))GiB)"
}

ask_swap() {
    read -p "Do you want a swap partition? (y/n): " CONFIRM_SWAP
    case "$CONFIRM_SWAP" in
        y|Y|yes|Yes) CONFIRM_SWAP="y" ;;
        *) CONFIRM_SWAP="n" ;;
    esac
    if [ "$CONFIRM_SWAP" = "y" ]; then
        read -p "Enter swap size (in MiB): " SWAP_SIZE
    fi
}

ask_hostname() {
    announce "Hostname..."
    while true; do
        read -p "Enter hostname [Kira]: " HOSTNAME
        [ -z "$HOSTNAME" ] && HOSTNAME="Kira"
        case "$HOSTNAME" in
            *[!a-zA-Z0-9-]*)
                echo "Hostname can only contain letters, numbers, and hyphens. Try again."
                continue
                ;;
        esac
        break
    done
}

ask_user() {
    announce "Account setup..."
    ask_password ROOT_PASS "root"
    while true; do
        read -p "Enter username [kira]: " USERNAME
        [ -z "$USERNAME" ] && USERNAME="kira"
        case "$USERNAME" in
            [a-z_][a-z0-9_-]*) break ;;
            *)
                echo "Username must start with a lowercase letter or underscore, and contain only lowercase letters, numbers, underscores, or hyphens. Try again."
                ;;
        esac
    done
    ask_password USER_PASS "$USERNAME"
}

# curated rather than driven by a live /usr/share/zoneinfo listing - the live image has no
# tzdata of its own (only the target gets it, via $PACKAGES), so there's nothing on this
# session to list choices from. Covers every major region; "other" below covers anything this
# list doesn't, for anyone who already knows the exact Region/City name they want.
TIMEZONES="UTC America/New_York America/Chicago America/Denver America/Los_Angeles America/Anchorage America/Sao_Paulo America/Mexico_City America/Toronto Europe/London Europe/Paris Europe/Berlin Europe/Madrid Europe/Rome Europe/Amsterdam Europe/Moscow Europe/Istanbul Africa/Cairo Africa/Johannesburg Africa/Lagos Asia/Dubai Asia/Kolkata Asia/Shanghai Asia/Tokyo Asia/Seoul Asia/Singapore Asia/Bangkok Asia/Jakarta Australia/Sydney Australia/Perth Pacific/Auckland"

ask_timezone() {
    announce "Timezone selection..."
    i=0
    for tz in $TIMEZONES; do
        i=$((i + 1))
        echo "  $i) $tz"
    done
    read -p "Select a timezone number, type a full Region/City name, or press enter for UTC: " TZ_INPUT
    if [ -z "$TZ_INPUT" ]; then
        TARGET_TZ="UTC"
    elif echo "$TZ_INPUT" | grep -qE '^[0-9]+$'; then
        TARGET_TZ=$(echo "$TIMEZONES" | tr ' ' '\n' | sed -n "${TZ_INPUT}p")
        if [ -z "$TARGET_TZ" ]; then
            echo "Invalid selection, defaulting to UTC."
            TARGET_TZ="UTC"
        fi
    else
        TARGET_TZ="$TZ_INPUT"
    fi
}

ask_tier() {
    announce "Select installation tier:"
    read -p "Enter 1 for desktop (Sleex) | 2 for desktop (SwayFX) | 3 for server: " TIER_CHOICE
    case "$TIER_CHOICE" in
        1) KIRA_TIER="desktop-sleex" ;;
        2) KIRA_TIER="desktop-swayfx" ;;
        3) KIRA_TIER="server" ;;
        *) echo "Invalid choice, defaulting to server."; KIRA_TIER="server" ;;
    esac
}

# the single gate before anything destructive happens - every prompt above this point only
# ever asked questions or (for keymap/network) applied something to the live session itself,
# never touched the target disk. Replaces the old confirm_disk/confirm_free_space (which used
# to run immediately before partitioning, before hostname/user/timezone/tier were even asked)
# with one consolidated review of every choice made, all at once, before the point of no return.
confirm_and_summarize() {
    echo
    echo "Current layout of $TARGET_DISK:"
    lsblk "$TARGET_DISK" -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
    echo
    echo "================================================"
    echo " Review your choices before anything is written:"
    echo "================================================"
    echo "  Keyboard layout : $KEYMAP_CHOICE"
    echo "  Target disk     : $TARGET_DISK"
    if [ "$PARTITION_MODE" = "1" ]; then
        echo "  Partitioning    : erase the whole disk"
    else
        echo "  Partitioning    : use existing free space (${FREE_START}MiB-${FREE_END}MiB), other partitions untouched"
    fi
    if [ "$CONFIRM_SWAP" = "y" ]; then
        echo "  Swap            : ${SWAP_SIZE}MiB"
    else
        echo "  Swap            : none"
    fi
    echo "  Hostname        : $HOSTNAME"
    echo "  Username        : $USERNAME"
    echo "  Timezone        : $TARGET_TZ"
    echo "  Installation    : $KIRA_TIER"
    echo
    echo "/!\ ALL DATA on $TARGET_DISK will be permanently modified. This cannot be undone. /!\ "
    read -p "Type '$TARGET_DISK_SHORT' to confirm and begin, or anything else to abort: " CONFIRM
    if [ "$CONFIRM" != "$TARGET_DISK_SHORT" ]; then
        echo "Aborting. Nothing has been written."
        exit 1
    fi
}

find_esp() {
    announce "Finding ESP partition..."
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
    echo "Error: no EFI System Partition found on this disk or any other. Aborting."
    exit 1
}

write_free_space() {
    announce "Partitioning (free space)..."
    LAST_PART=$(parted -s "$TARGET_DISK" print | awk '/^ [0-9]/{print $1}' | sort -n | tail -1)
    case "$TARGET_DISK" in
        *[0-9]) PART_PREFIX="${TARGET_DISK}p" ;;
        *)      PART_PREFIX="${TARGET_DISK}" ;;
    esac
    if [ "$CONFIRM_SWAP" = "y" ]; then
        parted -s "$TARGET_DISK" mkpart swap linux-swap "${FREE_START}MiB" "$((FREE_START + SWAP_SIZE))MiB"
        SWAP_PART="${PART_PREFIX}$((LAST_PART + 1))"
        parted -s "$TARGET_DISK" mkpart root ext4 "$((FREE_START + SWAP_SIZE))MiB" "${FREE_END}MiB"
        ROOT_PART="${PART_PREFIX}$((LAST_PART + 2))"
    else
        parted -s "$TARGET_DISK" mkpart root ext4 "${FREE_START}MiB" "${FREE_END}MiB"
        ROOT_PART="${PART_PREFIX}$((LAST_PART + 1))"
    fi
    find_esp
}

write_partition() {
    announce "Partitioning (whole disk)..."
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    case "$TARGET_DISK" in
        *[0-9]) PART_PREFIX="${TARGET_DISK}p" ;;
        *)      PART_PREFIX="${TARGET_DISK}" ;;
    esac
    if [ "$CONFIRM_SWAP" = "y" ]; then
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
    announce "Partition formatting..."
    # parted returns as soon as it writes the partition table, before the
    # kernel/udev have necessarily created the new partition device nodes yet
    # (especially common on NVMe) - without this, mkfs can race ahead and fail
    # with "No such file or directory" on a partition that's about to exist
    partprobe "$TARGET_DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    for part in "$ESP_PART" "$ROOT_PART" "$SWAP_PART"; do
        [ -z "$part" ] && continue
        i=0
        while [ ! -b "$part" ] && [ $i -lt 15 ]; do
            sleep 1
            i=$((i + 1))
        done
        if [ ! -b "$part" ]; then
            echo "Error: $part never appeared after partitioning. Aborting."
            exit 1
        fi
    done

    if [ "$PARTITION_MODE" = "1" ]; then
        mkfs.fat -F 32 "$ESP_PART"
    fi
    mkfs.ext4 -F "$ROOT_PART"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        mkswap "$SWAP_PART"
    fi
}

mount_partition() {
    announce "Partition mounting..."
    mkdir -p "$MOUNT_POINT"
    mount "$ROOT_PART" "$MOUNT_POINT"
    # set as soon as the root mount succeeds, not at the end of this function - if the ESP
    # mount or swapon below it fails, root is still mounted and still needs the EXIT trap to
    # unmount it, not just whatever happened to finish last
    MOUNTED=1
    mkdir -p "$MOUNT_POINT/boot/efi"
    mount "$ESP_PART" "$MOUNT_POINT/boot/efi"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        swapon "$SWAP_PART"
    fi
}

copy_tarball() {
    announce "Installing base system..."
    tar -xJpf "$TARBALL" -C "$MOUNT_POINT" \
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
    if [ "$LIVE_ISO_TIER" = "desktop" ]; then
        mkdir -p "$MOUNT_POINT/var/lib/NetworkManager"
        chmod 755 "$MOUNT_POINT/var/lib/NetworkManager"
    fi
    chmod 1777 "$MOUNT_POINT/tmp"
    chown root:root "$MOUNT_POINT/var/empty"
    echo "$KIRA_TIER" > "$MOUNT_POINT/etc/kira-tier"
}

copy_network_config() {
    # keyfile plugin (see networkmanager/files/NetworkManager.conf) stores
    # connections as plain files here - carry over whatever got set up
    # during the live session (e.g. wifi) so the install doesn't come up
    # with no network on first boot
    if [ -d /etc/NetworkManager/system-connections ] && \
       [ -n "$(ls -A /etc/NetworkManager/system-connections 2>/dev/null)" ]; then
        echo "Copying network connections..."
        mkdir -p "$MOUNT_POINT/etc/NetworkManager/system-connections"
        cp -a /etc/NetworkManager/system-connections/. "$MOUNT_POINT/etc/NetworkManager/system-connections/"
        chown -R root:root "$MOUNT_POINT/etc/NetworkManager/system-connections"
        chmod 600 "$MOUNT_POINT"/etc/NetworkManager/system-connections/*
    fi
}

remove_live_user() {
    if [ "$LIVE_ISO_TIER" = "desktop" ]; then
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
UUID=$(blkid_uuid "$ROOT_PART")  /           ext4    defaults    0 1
UUID=$(blkid_uuid "$ESP_PART")   /boot/efi   vfat    defaults    0 2
EOF
    if [ "$CONFIRM_SWAP" = "y" ]; then
        echo "UUID=$(blkid_uuid "$SWAP_PART")  none  swap  sw  0 0" >> "$MOUNT_POINT/etc/fstab"
    fi
}

apply_hostname() {
    echo "$HOSTNAME" > "$MOUNT_POINT/etc/hostname"
}

apply_timezone() {
    announce "Setting timezone..."
    ln -sf "/usr/share/zoneinfo/$TARGET_TZ" "$MOUNT_POINT/etc/localtime"
}

apply_user_setup() {
    announce "Creating accounts..."
    echo "root:$ROOT_PASS" | chroot "$MOUNT_POINT" /usr/sbin/chpasswd
    chroot "$MOUNT_POINT" /usr/sbin/useradd -m -s /bin/zsh -G wheel,video,input,audio "$USERNAME"
    echo "$USERNAME:$USER_PASS" | chroot "$MOUNT_POINT" /usr/sbin/chpasswd
}

chroot_setup() {
    echo "Binding Virtual File Systems..."
    mount --bind /dev "$MOUNT_POINT/dev"
    mount --bind /proc "$MOUNT_POINT/proc"
    mount --bind /sys "$MOUNT_POINT/sys"
    mount --bind /sys/firmware/efi/efivars "$MOUNT_POINT/sys/firmware/efi/efivars"
    cp /etc/resolv.conf "$MOUNT_POINT/etc/resolv.conf"
}

apply_tier_config() {
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
    announce "Installing base packages..."
    chroot "$MOUNT_POINT" flux check
    for pkg in $PACKAGES; do
        chroot_flux_install "$pkg"
    done
    # Alpine's sudo package ships this rule commented out by default - without
    # it, wheel membership (set on the user in apply_user_setup) grants nothing and
    # sudo just says "not in the sudoers file", not a login problem itself but
    # exactly as confusing as one
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL$/%wheel ALL=(ALL:ALL) ALL/' "$MOUNT_POINT/etc/sudoers"
    if [ "$KIRA_TIER" = "desktop-sleex" ]; then
        echo "Installing desktop packages (Sleex)..."
        for pkg in $PACKAGES_SLEEX; do
            chroot_flux_install "$pkg"
        done
    fi
    if [ "$KIRA_TIER" = "desktop-swayfx" ]; then
        echo "Installing desktop packages (SwayFX)..."
        for pkg in $PACKAGES_SWAYFX; do
            chroot_flux_install "$pkg"
        done
    fi
    if has_intel_wifi; then
        echo "Intel WiFi detected, installing linux-firmware-intel..."
        chroot_flux_install linux-firmware-intel
    fi
    if has_nvidia_gpu; then
        echo "NVIDIA GPU detected, installing linux-firmware-nvidia..."
        chroot_flux_install linux-firmware-nvidia
    fi
}

# grub-probe sometimes can't resolve the root UUID inside the chroot and grub-mkconfig
# silently falls back to a raw /dev/nvmeXnYpZ path, which breaks on reboot if NVMe
# enumeration order shifts - force it to the UUID fstab already uses successfully
fix_grub_root_uuid() {
    sed -i "s#root=$ROOT_PART#root=UUID=$(blkid_uuid "$ROOT_PART")#" \
        "$MOUNT_POINT/boot/grub/grub.cfg"
}

# kira-base seeds a Kira-branded /etc/default/grub, but Alpine's own grub package
# ships its own copy of that same path (and of /etc/grub.d/40_custom) - installing
# grub overwrites the seed, which is why every menu entry read back "Alpine" instead
# of "Kira Linux". Has to run right before grub-mkconfig, not rely on install order.
fix_grub_branding() {
    if grep -q '^GRUB_DISTRIBUTOR=' "$MOUNT_POINT/etc/default/grub"; then
        sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Kira Linux"/' "$MOUNT_POINT/etc/default/grub"
    else
        echo 'GRUB_DISTRIBUTOR="Kira Linux"' >> "$MOUNT_POINT/etc/default/grub"
    fi

    # the live ISO hand-writes these two menuentries straight into its own grub.cfg,
    # but the installed system's grub.cfg is generated by grub-mkconfig instead, which
    # only picks up custom entries from /etc/grub.d/40_custom (every script under
    # /etc/grub.d/ gets run, its stdout copied into grub.cfg verbatim)
    if ! grep -q "Reboot Computer" "$MOUNT_POINT/etc/grub.d/40_custom" 2>/dev/null; then
        cat >> "$MOUNT_POINT/etc/grub.d/40_custom" << 'EOF'

menuentry 'Reboot Computer' {
    reboot
}
menuentry 'Shutdown Computer' {
    halt
}
EOF
    fi
}

bootloader_install() {
    announce "Installing bootloader..."
    if [ "$PARTITION_MODE" = "1" ]; then
        chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$HOSTNAME"
        fix_grub_branding
        chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg
        fix_grub_root_uuid
    else
        if [ "$ESP_EXTERNAL" = "1" ]; then
            mount "$ESP_PART" "$MOUNT_POINT/boot/efi"
            chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$HOSTNAME"
            fix_grub_branding
            chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg
            fix_grub_root_uuid
            umount "$MOUNT_POINT/boot/efi"
        else
            chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$HOSTNAME"
            fix_grub_branding
            chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg
            fix_grub_root_uuid
        fi
    fi
}

chroot_cleanup() {
    echo "Unbinding Virtual File Systems..."
    umount "$MOUNT_POINT/sys/firmware/efi/efivars"
    umount "$MOUNT_POINT/sys"
    umount "$MOUNT_POINT/proc"
    umount "$MOUNT_POINT/dev"
}

unmount_partition() {
    announce "Partition unmounting..."
    if [ "$ESP_EXTERNAL" = "0" ] || mountpoint -q "$MOUNT_POINT/boot/efi"; then
        umount "$MOUNT_POINT/boot/efi"
    fi
    umount "$MOUNT_POINT"
    if [ "$CONFIRM_SWAP" = "y" ]; then
        swapoff "$SWAP_PART"
    fi
    # nothing left for the EXIT trap to clean up - a failure in finish() (which only reboots
    # or prints a message) has nothing destructive left to undo
    MOUNTED=0
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
    check_uefi

    # ---- phase 1: ask everything up front. Nothing below this point touches the target
    # disk - keymap/network are the only two steps that apply anything at all, and both only
    # ever apply to the live session itself (console keymap, live network connection), never
    # to $TARGET_DISK. ----
    select_keymap
    network_setup
    ask_partition_mode
    ask_hostname
    ask_user
    ask_timezone
    ask_tier
    confirm_and_summarize

    # ---- phase 2: everything from here runs non-interactively. The user already reviewed
    # and confirmed every choice above - nothing here should need to ask anything else. ----
    if [ "$PARTITION_MODE" = "1" ]; then
        write_partition
    else
        write_free_space
    fi
    format_partition
    mount_partition
    copy_tarball
    copy_network_config
    remove_live_user
    copy_kernel
    fstab_entry
    apply_hostname
    chroot_setup
    # apply_user_setup needs the real useradd/chpasswd from the shadow package, and
    # apply_tier_config (right after it) needs the home directory useradd creates - so shadow
    # has to be pulled in on its own ahead of the main package list, not found partway through it
    chroot "$MOUNT_POINT" flux check
    # flux's own recipe sync falls back to a plain tarball download the first time
    # git isn't there, but every sync after that assumes git and just runs
    # "git -C ... pull" - installing it now (still git-independent, a plain
    # Alpine package fetch) keeps every later flux check in this chroot from
    # breaking, instead of only the very first one being tolerant of it
    chroot_flux_install git
    chroot_flux_install shadow
    # useradd -m copies /etc/skel into the new home right away - kira-branding
    # is what actually populates .zshrc/.p10k.zsh there, so it has to land
    # before apply_user_setup too, not later in packages_install like the rest.
    # kira-branding pulls in zsh and kira-zsh-plugins itself via its own deps.
    chroot_flux_install kira-branding
    # kira-branding just seeded /etc/keymaps/us.bmap as the default active
    # layout - swap it for whatever was picked in select_keymap, unless that
    # was already us. Target's own copy of the library (installed by the
    # same package) is used rather than the live image's, since it's
    # guaranteed to exist at this point regardless of how the ISO was built
    if [ "$KEYMAP_CHOICE" != "us" ]; then
        rm -f "$MOUNT_POINT/etc/keymaps"/*.bmap
        cp "$MOUNT_POINT/usr/share/kira-keymaps/$KEYMAP_CHOICE.bmap" "$MOUNT_POINT/etc/keymaps/"
    fi
    apply_user_setup
    apply_tier_config
    packages_install
    apply_timezone
    bootloader_install
    chroot_cleanup
    unmount_partition
    finish
}

main
