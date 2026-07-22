KERNEL ?= ../shinigami/arch/x86/boot/bzImage
KIRA_BASE_INITRAMFS ?= ../kira-base/build/initramfs.cpio.gz
KIRA_BASE_ROOTFS ?= ../kira-base/build/rootfs.tar.gz
# Choose DE between sleex, swayfx
DE ?= sleex

# Mount points for the chroot used to build each installer environment.
ROOT_CONSOLE = /tmp/kira-installer-root-console
ROOT_DESKTOP = /tmp/kira-installer-root-desktop

# umount -R refuses to recurse unless the given path is itself a mountpoint
# so unmount each bind mount explicitly, innermost first.
UNMOUNT_CHROOT = sudo umount $(1)/dev/pts 2>/dev/null; sudo umount $(1)/dev 2>/dev/null; sudo umount $(1)/sys 2>/dev/null; sudo umount $(1)/proc 2>/dev/null; true

.PHONY: all clean unmount-stale qemu-console qemu-desktop console desktop

all: build/kira-console.iso build/kira-desktop-$(DE).iso

console: build/kira-console.iso

desktop: build/kira-desktop-$(DE).iso

unmount-stale:
	$(call UNMOUNT_CHROOT,$(ROOT_CONSOLE))
	$(call UNMOUNT_CHROOT,$(ROOT_DESKTOP))

clean: unmount-stale
	sudo rm -rf $(ROOT_CONSOLE) $(ROOT_DESKTOP)
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

build/kira-base.tar.gz: $(KIRA_BASE_ROOTFS) | build/
	cp $(KIRA_BASE_ROOTFS) $@

# These produce a tarball of the fully provisioned chroot, it's NOT a bootable
# initramfs. The live ISO boots through kira-base's minimal switch_root
# initramfs (same one used on the installed disk); that initramfs finds
# this tarball on the boot media itself (at the ISO9660 root, see
# build/kira-*.iso below) and extracts it into a tmpfs before switch_root.
build/live-rootfs-console.tar.gz: build/kira-base.tar.gz $(KIRA_BASE_INITRAMFS) install.sh | build/
	@echo "needs to run as root"
	$(call UNMOUNT_CHROOT,$(ROOT_CONSOLE))
	sudo rm -rf $(ROOT_CONSOLE)
	mkdir -p $(ROOT_CONSOLE)
	tar -xzpf $(KIRA_BASE_ROOTFS) -C $(ROOT_CONSOLE)
	set -e; \
	trap '$(call UNMOUNT_CHROOT,$(ROOT_CONSOLE))' EXIT; \
	sudo mount --bind /proc $(ROOT_CONSOLE)/proc; \
	sudo mount --bind /sys $(ROOT_CONSOLE)/sys; \
	sudo mount --bind /dev $(ROOT_CONSOLE)/dev; \
	sudo mount --bind /dev/pts $(ROOT_CONSOLE)/dev/pts; \
	sudo cp /etc/resolv.conf $(ROOT_CONSOLE)/etc/resolv.conf; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux update; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y kira-installer-tools; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y kira-net; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y kira-login; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y kira-seat; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y kira-session-bus; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y zsh; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y zsh-plugins; \
	sudo chroot $(ROOT_CONSOLE) /usr/bin/flux install -y kira-branding
	echo "server" > $(ROOT_CONSOLE)/etc/kira-tier
	cp install.sh $(ROOT_CONSOLE)/usr/bin/kira-install
	chmod +x $(ROOT_CONSOLE)/usr/bin/kira-install
	mkdir -p $(ROOT_CONSOLE)/installer
	cp build/kira-base.tar.gz $(ROOT_CONSOLE)/installer/kira-base.tar.gz
	cp $(KERNEL) $(ROOT_CONSOLE)/installer/bzImage
	cp $(KIRA_BASE_INITRAMFS) $(ROOT_CONSOLE)/installer/initramfs.cpio.gz
	sudo tar -czpf $(CURDIR)/build/live-rootfs-console.tar.gz --numeric-owner -C $(ROOT_CONSOLE) .

build/live-rootfs-desktop.tar.gz: build/kira-base.tar.gz $(KIRA_BASE_INITRAMFS) install.sh | build/
	@echo "needs to run as root"
	$(call UNMOUNT_CHROOT,$(ROOT_DESKTOP))
	sudo rm -rf $(ROOT_DESKTOP)
	mkdir -p $(ROOT_DESKTOP)
	tar -xzpf $(KIRA_BASE_ROOTFS) -C $(ROOT_DESKTOP)
	set -e; \
	trap '$(call UNMOUNT_CHROOT,$(ROOT_DESKTOP))' EXIT; \
	sudo mount --bind /proc $(ROOT_DESKTOP)/proc; \
	sudo mount --bind /sys $(ROOT_DESKTOP)/sys; \
	sudo mount --bind /dev $(ROOT_DESKTOP)/dev; \
	sudo mount --bind /dev/pts $(ROOT_DESKTOP)/dev/pts; \
	sudo cp /etc/resolv.conf $(ROOT_DESKTOP)/etc/resolv.conf; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux update; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-installer-tools; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-net; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-seat; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-session-bus; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y zsh; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y zsh-plugins; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-branding; \
ifeq ($(DE),swayfx)
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-desktop-swayFX; \
endif
ifeq ($(DE),sleex)
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-desktop-sleex; \
endif
	true
	sudo cp -r $(ROOT_DESKTOP)/etc/skel/. $(ROOT_DESKTOP)/root/

	sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' $(ROOT_DESKTOP)/etc/ssh/sshd_config
	sed -i 's/#PermitEmptyPasswords.*/PermitEmptyPasswords yes/' $(ROOT_DESKTOP)/etc/ssh/sshd_config
	echo "desktop" > $(ROOT_DESKTOP)/etc/kira-tier

	cp install.sh $(ROOT_DESKTOP)/usr/bin/kira-install
	chmod +x $(ROOT_DESKTOP)/usr/bin/kira-install
	mkdir -p $(ROOT_DESKTOP)/installer
	cp build/kira-base.tar.gz $(ROOT_DESKTOP)/installer/kira-base.tar.gz
	cp $(KERNEL) $(ROOT_DESKTOP)/installer/bzImage
	cp $(KIRA_BASE_INITRAMFS) $(ROOT_DESKTOP)/installer/initramfs.cpio.gz
	sudo tar -czpf $(CURDIR)/build/live-rootfs-desktop.tar.gz --numeric-owner -C $(ROOT_DESKTOP) .

build/BOOTX64.EFI: grub.cfg grub-early.cfg | build/
	grub-mkimage \
		-O x86_64-efi \
		-o build/BOOTX64.EFI \
		-c grub-early.cfg \
		-p /EFI/BOOT \
		iso9660 part_gpt part_msdos fat ext2 normal boot linux echo configfile \
		search search_fs_uuid search_fs_file search_label \
		ls cat help reboot halt

build/kira-console.iso: build/live-rootfs-console.tar.gz $(KIRA_BASE_INITRAMFS) $(KERNEL) build/BOOTX64.EFI | build/
	mkdir -p build/iso-root-console/boot
	mkdir -p build/iso-root-console/EFI/BOOT
	cp $(KERNEL) build/iso-root-console/boot/bzImage
	cp $(KIRA_BASE_INITRAMFS) build/iso-root-console/boot/initramfs.cpio.gz
	cp build/live-rootfs-console.tar.gz build/iso-root-console/live-rootfs.tar.gz
	cp build/BOOTX64.EFI build/iso-root-console/EFI/BOOT/BOOTX64.EFI
	cp grub.cfg build/iso-root-console/EFI/BOOT/grub.cfg
	dd if=/dev/zero of=build/efi-console.img bs=1M count=4
	mkfs.fat -F 12 build/efi-console.img
	mmd -i build/efi-console.img ::/EFI ::/EFI/BOOT
	mcopy -i build/efi-console.img build/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i build/efi-console.img grub.cfg ::/EFI/BOOT/grub.cfg
	xorriso -as mkisofs \
		-o $@ \
		-R -J \
		-V "KIRA" \
		--protective-msdos-label \
		-e --interval:appended_partition_2:all:: \
		-no-emul-boot \
		-append_partition 2 0xef build/efi-console.img \
		build/iso-root-console/

build/kira-desktop-$(DE).iso: build/live-rootfs-desktop.tar.gz $(KIRA_BASE_INITRAMFS) $(KERNEL) build/BOOTX64.EFI | build/
	mkdir -p build/iso-root-desktop/boot
	mkdir -p build/iso-root-desktop/EFI/BOOT
	cp $(KERNEL) build/iso-root-desktop/boot/bzImage
	cp $(KIRA_BASE_INITRAMFS) build/iso-root-desktop/boot/initramfs.cpio.gz
	cp build/live-rootfs-desktop.tar.gz build/iso-root-desktop/live-rootfs.tar.gz
	cp build/BOOTX64.EFI build/iso-root-desktop/EFI/BOOT/BOOTX64.EFI
	cp grub.cfg build/iso-root-desktop/EFI/BOOT/grub.cfg
	dd if=/dev/zero of=build/efi-desktop.img bs=1M count=4
	mkfs.fat -F 12 build/efi-desktop.img
	mmd -i build/efi-desktop.img ::/EFI ::/EFI/BOOT
	mcopy -i build/efi-desktop.img build/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
	mcopy -i build/efi-desktop.img grub.cfg ::/EFI/BOOT/grub.cfg
	xorriso -as mkisofs \
		-o $@ \
		-R -J \
		-V "KIRA" \
		--protective-msdos-label \
		-e --interval:appended_partition_2:all:: \
		-no-emul-boot \
		-append_partition 2 0xef build/efi-desktop.img \
		build/iso-root-desktop/

qemu-console: build/kira-console.iso
	qemu-system-x86_64 \
		-drive file=build/kira-console.iso,format=raw,if=virtio \
		-bios /usr/share/ovmf/OVMF.fd \
		-m 1G \
		-nographic \
		-serial mon:stdio

qemu-desktop: build/kira-desktop-$(DE).iso
	qemu-system-x86_64 \
		-drive file=build/kira-desktop-$(DE).iso,format=raw,if=virtio \
		-bios /usr/share/ovmf/OVMF.fd \
		-m 1G \
		-nographic \
		-serial mon:stdio
