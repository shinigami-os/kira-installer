KERNEL ?= ../shinigami/arch/x86/boot/bzImage
KIRA_BASE_STAMP ?= ../kira-base/build/stamps/sysroot.stamp
KIRA_BASE_SYSROOT ?= ../kira-base/build/sysroot
KIRA_BASE_INITRAMFS ?= ../kira-base/build/initramfs.cpio.gz

.PHONY: all clean qemu-console qemu-desktop console desktop

all: build/kira-console.iso build/kira-desktop.iso

console: build/kira-console.iso

desktop: build/kira-desktop.iso

clean:
	rm -rf build

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
	rm -rf build/installer-root-console
	mkdir -p build/installer-root-console
	gunzip -c $(KIRA_BASE_INITRAMFS) | cpio -idm -D build/installer-root-console/
	@echo "needs to run as root"
	sudo mount --bind /proc build/installer-root-console/proc
	sudo mount --bind /sys build/installer-root-console/sys
	sudo mount --bind /dev build/installer-root-console/dev
	sudo mount --bind /dev/pts build/installer-root-console/dev/pts
	sudo cp /etc/resolv.conf build/installer-root-console/etc/resolv.conf
	sudo chroot build/installer-root-console /usr/bin/flux update
	sudo chroot build/installer-root-console /usr/bin/flux install -y kira-installer-tools
	sudo chroot build/installer-root-console /usr/bin/flux install -y kira-net
	sudo chroot build/installer-root-console /usr/bin/flux install -y kira-login
	sudo chroot build/installer-root-console /usr/bin/flux install -y kira-seat
	sudo chroot build/installer-root-console /usr/bin/flux install -y kira-session-bus
	sudo chroot build/installer-root-console /usr/bin/flux install -y zsh
	sudo chroot build/installer-root-console /usr/bin/flux install -y zsh-plugins
	sudo chroot build/installer-root-console /usr/bin/flux install -y kira-branding
	sudo umount build/installer-root-console/dev/pts
	sudo umount build/installer-root-console/dev
	sudo umount build/installer-root-console/sys
	sudo umount build/installer-root-console/proc
	cp install.sh build/installer-root-console/usr/bin/kira-install
	chmod +x build/installer-root-console/usr/bin/kira-install
	mkdir -p build/installer-root-console/installer
	cp build/kira-base.tar.gz build/installer-root-console/installer/kira-base.tar.gz
	cp $(KERNEL) build/installer-root-console/installer/bzImage
	cd build/installer-root-console && find . | cpio -oH newc --owner root:root | gzip > ../installer-initramfs-console.cpio.gz

build/installer-initramfs-desktop.cpio.gz: build/kira-base.tar.gz $(KIRA_BASE_INITRAMFS) install.sh | build/
	rm -rf build/installer-root-desktop
	mkdir -p build/installer-root-desktop
	gunzip -c $(KIRA_BASE_INITRAMFS) | cpio -idm -D build/installer-root-desktop/
	@echo "needs to run as root"
	sudo mount --bind /proc build/installer-root-desktop/proc
	sudo mount --bind /sys build/installer-root-desktop/sys
	sudo mount --bind /dev build/installer-root-desktop/dev
	sudo mount --bind /dev/pts build/installer-root-desktop/dev/pts
	sudo cp /etc/resolv.conf build/installer-root-desktop/etc/resolv.conf
	sudo chroot build/installer-root-desktop /usr/bin/flux update
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-installer-tools
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-net
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-login
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-seat
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-session-bus
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y zsh
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y zsh-plugins
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-branding
	sudo chroot build/installer-root-desktop /usr/bin/flux install -y kira-desktop-swayFX
	sudo umount build/installer-root-desktop/dev/pts
	sudo umount build/installer-root-desktop/dev
	sudo umount build/installer-root-desktop/sys
	sudo umount build/installer-root-desktop/proc
	cp install.sh build/installer-root-desktop/usr/bin/kira-install
	chmod +x build/installer-root-desktop/usr/bin/kira-install
	mkdir -p build/installer-root-desktop/installer
	cp build/kira-base.tar.gz build/installer-root-desktop/installer/kira-base.tar.gz
	cp $(KERNEL) build/installer-root-desktop/installer/bzImage
	cd build/installer-root-desktop && find . | cpio -oH newc --owner root:root | gzip > ../installer-initramfs-desktop.cpio.gz

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
