KERNEL ?= ../shinigami/arch/x86/boot/bzImage
KIRA_BASE_INITRAMFS ?= ../kira-base/build/initramfs.cpio.gz
KIRA_BASE_ROOTFS ?= ../kira-base/build/rootfs.tar.xz

# Mount point of the chroot the live medium is built in.
ROOT = /tmp/kira-installer-root

# What the live medium carries: the installer's tools, the stack the app runs on (cage, Quickshell, Qt's
# graphics drivers, fonts), networking, and the firmware for the screen and the wifi. icu-data-full comes
# first on purpose: several Qt packages otherwise claim icu-data-en and conflict with it.
PACKAGES = icu-data-full kira-installer-tools kira-net kira-seat kira-session-bus kira-branding \
	kira-quickshell kira-the-line-ui cage xkeyboard-config font-raleway kira-ttf-ibm-plex-mono font-dejavu \
	mesa mesa-egl mesa-gl mesa-gles mesa-dri-gallium linux-firmware-intel linux-firmware-nvidia

# Every way into a shell on the medium: the installer must be the only thing it offers.
REMOVE_SERVICES = getty-tty1 getty-tty2 getty-tty3 getty-tty4 getty-tty5 getty-tty6 console sshd

SOURCES = $(shell find app iso -type f)

# umount -R needs the path itself to be a mountpoint, so unmount each bind mount explicitly
UNMOUNT_CHROOT = sudo umount $(1)/dev/pts 2>/dev/null; sudo umount $(1)/dev 2>/dev/null; sudo umount $(1)/sys 2>/dev/null; sudo umount $(1)/proc 2>/dev/null; true

.PHONY: all iso clean unmount-stale qemu

all: iso

iso: build/kira-installer.iso

unmount-stale:
	$(call UNMOUNT_CHROOT,$(ROOT))

clean: unmount-stale
	sudo rm -rf $(ROOT)
	sudo rm -rf build

build/:
	mkdir -p build

$(KERNEL):
	@echo "ERROR: Shinigami bzImage not found. Run: make -C ../shinigami"
	@exit 1

$(KIRA_BASE_INITRAMFS):
	@echo "ERROR: kira-base initramfs not built. Run: make -C ../kira-base"
	@exit 1

$(KIRA_BASE_ROOTFS):
	@echo "ERROR: kira-base rootfs not built. Run: make -C ../kira-base"
	@exit 1

build/kira-base.tar.xz: $(KIRA_BASE_ROOTFS) | build/
	cp $(KIRA_BASE_ROOTFS) $@

# tarball of the provisioned chroot, extracted into tmpfs at boot by kira-base's switch_root initramfs
build/live-rootfs.tar.xz: build/kira-base.tar.xz $(KIRA_BASE_INITRAMFS) $(KERNEL) $(SOURCES) | build/
	@echo "needs to run as root"
	$(call UNMOUNT_CHROOT,$(ROOT))
	sudo rm -rf $(ROOT)
	mkdir -p $(ROOT)
	tar -xJpf $(KIRA_BASE_ROOTFS) -C $(ROOT)
	set -e; \
	trap '$(call UNMOUNT_CHROOT,$(ROOT))' EXIT; \
	sudo mount --bind /proc $(ROOT)/proc; \
	sudo mount --bind /sys $(ROOT)/sys; \
	sudo mount --bind /dev $(ROOT)/dev; \
	sudo mount --bind /dev/pts $(ROOT)/dev/pts; \
	sudo cp /etc/resolv.conf $(ROOT)/etc/resolv.conf; \
	sudo chroot $(ROOT) /usr/bin/flux check; \
	sudo chroot $(ROOT) /usr/bin/flux install -y $(PACKAGES)
	sudo mkdir -p $(ROOT)/usr/share/kira-installer
	sudo cp -a app/. $(ROOT)/usr/share/kira-installer/
	sudo chmod +x $(ROOT)/usr/share/kira-installer/launch.sh $(ROOT)/usr/share/kira-installer/backend/kira-install-backend
	sudo cp -a iso/sv/kira-installer $(ROOT)/etc/sv/kira-installer
	cd $(ROOT)/etc/sv && sudo rm -rf $(REMOVE_SERVICES)
	sudo mkdir -p $(ROOT)/installer
	sudo cp build/kira-base.tar.xz $(ROOT)/installer/kira-base.tar.xz
	sudo cp $(KERNEL) $(ROOT)/installer/bzImage
	sudo cp $(KIRA_BASE_INITRAMFS) $(ROOT)/installer/initramfs.cpio.gz
	# drop build-only packages (gcc, cmake, -dev headers, ...) pulled in above
	sudo chroot $(ROOT) /usr/bin/flux autoremove
	# the .tar.zst cache is redundant with the files already extracted onto disk
	sudo rm -rf $(ROOT)/var/cache/flux/*
	sudo tar -cJpf $(CURDIR)/build/live-rootfs.tar.xz --numeric-owner -C $(ROOT) .

build/BOOTX64.EFI: grub.cfg grub-early.cfg | build/
	grub-mkimage \
		-O x86_64-efi \
		-o build/BOOTX64.EFI \
		-c grub-early.cfg \
		-p /EFI/BOOT \
		iso9660 part_gpt part_msdos fat ext2 normal boot linux echo configfile \
		search search_fs_uuid search_fs_file search_label \
		ls cat help reboot halt

build/kira-installer.iso: build/live-rootfs.tar.xz $(KIRA_BASE_INITRAMFS) $(KERNEL) build/BOOTX64.EFI | build/
	mkdir -p build/iso-root/boot
	mkdir -p build/iso-root/EFI/BOOT
	cp $(KERNEL) build/iso-root/boot/bzImage
	cp $(KIRA_BASE_INITRAMFS) build/iso-root/boot/initramfs.cpio.gz
	cp build/live-rootfs.tar.xz build/iso-root/live-rootfs.tar.xz
	cp build/BOOTX64.EFI build/iso-root/EFI/BOOT/BOOTX64.EFI
	cp grub.cfg build/iso-root/EFI/BOOT/grub.cfg
	dd if=/dev/zero of=build/efi.img bs=1M count=4
	mkfs.fat -F 12 build/efi.img
	mmd -i build/efi.img ::/EFI ::/EFI/BOOT
	mcopy -i build/efi.img build/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i build/efi.img grub.cfg ::/EFI/BOOT/grub.cfg
	xorriso -as mkisofs \
		-o $@ \
		-R -J \
		-V "KIRA" \
		--protective-msdos-label \
		-e --interval:appended_partition_2:all:: \
		-no-emul-boot \
		-append_partition 2 0xef build/efi.img \
		build/iso-root/

qemu: build/kira-installer.iso
	qemu-system-x86_64 \
		-enable-kvm \
		-drive file=build/kira-installer.iso,format=raw,if=virtio \
		-bios /usr/share/ovmf/OVMF.fd \
		-m 2G \
		-device virtio-vga
