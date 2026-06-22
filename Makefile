KERNEL ?= ../shinigami/arch/x86/boot/bzImage
KIRA_BASE_STAMP ?= ../kira-base/build/stamps/sysroot.stamp
KIRA_BASE_SYSROOT ?= ../kira-base/build/sysroot
KIRA_BASE_INITRAMFS ?= ../kira-base/build/initramfs.cpio.gz

# Mount points for the chroot used to build each installer environment.
# Deliberately kept OUTSIDE build/ so that `rm -rf build` (run manually,
# by habit, or by any future tooling) can never recurse into a live
# /proc, /sys, /dev bind mount
# That footgun previously made a stale mount from a failed build
# turn a routine cleanup into a system-mount deletion attempt.
ROOT_CONSOLE = /tmp/kira-installer-root-console
ROOT_DESKTOP = /tmp/kira-installer-root-desktop

# umount -R refuses to recurse unless the given path is itself a mountpoint
# so unmount each bind mount explicitly, innermost first.
UNMOUNT_CHROOT = sudo umount $(1)/dev/pts 2>/dev/null; sudo umount $(1)/dev 2>/dev/null; sudo umount $(1)/sys 2>/dev/null; sudo umount $(1)/proc 2>/dev/null; true

.PHONY: all clean unmount-stale qemu-console qemu-desktop console desktop

all: build/kira-console.iso build/kira-desktop.iso

console: build/kira-console.iso

desktop: build/kira-desktop.iso

unmount-stale:
	$(call UNMOUNT_CHROOT,$(ROOT_CONSOLE))
	$(call UNMOUNT_CHROOT,$(ROOT_DESKTOP))

clean: unmount-stale
	sudo rm -rf $(ROOT_CONSOLE) $(ROOT_DESKTOP)
	sudo rm -rf build

build/:
	mkdir -p build

$(KIRA_BASE_STAMP):
	@echo "ERROR: kira-base sysroot not built. Run: make -C ../kira-base"
	@exit 1

$(KERNEL):
	@echo "ERROR: Shinigami bzImage not found. Run: make -C ../shinigami"
	@exit 1

$(KIRA_BASE_INITRAMFS):
	@echo "ERROR: kira-base initramfs not built. Run: make -C ../kira-base"
	@exit 1

build/kira-base.tar.gz: $(KIRA_BASE_STAMP) | build/
	@echo "needs to run as root"
	tar -czpf $@ --numeric-owner -C $(KIRA_BASE_SYSROOT) .

build/installer-initramfs-console.cpio.gz: build/kira-base.tar.gz $(KIRA_BASE_INITRAMFS) install.sh | build/
	@echo "needs to run as root"
	$(call UNMOUNT_CHROOT,$(ROOT_CONSOLE))
	sudo rm -rf $(ROOT_CONSOLE)
	mkdir -p $(ROOT_CONSOLE)
	gunzip -c $(KIRA_BASE_INITRAMFS) | cpio -idm -D $(ROOT_CONSOLE)/
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
	cp install.sh $(ROOT_CONSOLE)/usr/bin/kira-install
	chmod +x $(ROOT_CONSOLE)/usr/bin/kira-install
	mkdir -p $(ROOT_CONSOLE)/installer
	cp build/kira-base.tar.gz $(ROOT_CONSOLE)/installer/kira-base.tar.gz
	cp $(KERNEL) $(ROOT_CONSOLE)/installer/bzImage
	cd $(ROOT_CONSOLE) && find . | cpio -oH newc --owner root:root | gzip > $(CURDIR)/build/installer-initramfs-console.cpio.gz

build/installer-initramfs-desktop.cpio.gz: build/kira-base.tar.gz $(KIRA_BASE_INITRAMFS) install.sh | build/
	@echo "needs to run as root"
	$(call UNMOUNT_CHROOT,$(ROOT_DESKTOP))
	sudo rm -rf $(ROOT_DESKTOP)
	mkdir -p $(ROOT_DESKTOP)
	gunzip -c $(KIRA_BASE_INITRAMFS) | cpio -idm -D $(ROOT_DESKTOP)/
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
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-login; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-seat; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-session-bus; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y zsh; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y zsh-plugins; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-branding; \
	sudo chroot $(ROOT_DESKTOP) /usr/bin/flux install -y kira-desktop-swayFX
	cp install.sh $(ROOT_DESKTOP)/usr/bin/kira-install
	chmod +x $(ROOT_DESKTOP)/usr/bin/kira-install
	mkdir -p $(ROOT_DESKTOP)/installer
	cp build/kira-base.tar.gz $(ROOT_DESKTOP)/installer/kira-base.tar.gz
	cp $(KERNEL) $(ROOT_DESKTOP)/installer/bzImage
	cd $(ROOT_DESKTOP) && find . | cpio -oH newc --owner root:root | gzip > $(CURDIR)/build/installer-initramfs-desktop.cpio.gz

build/BOOTX64.EFI: grub.cfg grub-early.cfg | build/
	grub-mkimage \
		-O x86_64-efi \
		-o build/BOOTX64.EFI \
		-c grub-early.cfg \
		-p /EFI/BOOT \
		iso9660 part_gpt part_msdos fat ext2 normal boot linux echo configfile \
		search search_fs_uuid search_fs_file search_label \
		ls cat help reboot halt

build/kira-console.iso: build/installer-initramfs-console.cpio.gz $(KERNEL) build/BOOTX64.EFI | build/
	mkdir -p build/iso-root-console/boot
	mkdir -p build/iso-root-console/EFI/BOOT
	cp $(KERNEL) build/iso-root-console/boot/bzImage
	cp build/installer-initramfs-console.cpio.gz build/iso-root-console/boot/initramfs.cpio.gz
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

build/kira-desktop.iso: build/installer-initramfs-desktop.cpio.gz $(KERNEL) build/BOOTX64.EFI | build/
	mkdir -p build/iso-root-desktop/boot
	mkdir -p build/iso-root-desktop/EFI/BOOT
	cp $(KERNEL) build/iso-root-desktop/boot/bzImage
	cp build/installer-initramfs-desktop.cpio.gz build/iso-root-desktop/boot/initramfs.cpio.gz
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

qemu-desktop: build/kira-desktop.iso
	qemu-system-x86_64 \
		-drive file=build/kira-desktop.iso,format=raw,if=virtio \
		-bios /usr/share/ovmf/OVMF.fd \
		-m 1G \
		-nographic \
		-serial mon:stdio
