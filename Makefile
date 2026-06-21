KERNEL ?= ../shinigami/arch/x86/boot/bzImage
KIRA_BASE_STAMP ?= ../kira-base/build/stamps/sysroot.stamp
KIRA_BASE_SYSROOT ?= ../kira-base/build/sysroot
KIRA_BASE_INITRAMFS ?= ../kira-base/build/initramfs.cpio.gz

.PHONY: all clean qemu

all: build/kira-base.iso

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

build/installer-initramfs.cpio.gz: build/kira-base.tar.gz $(KIRA_BASE_INITRAMFS) install.sh | build/
	mkdir -p build/installer-root
	gunzip -c $(KIRA_BASE_INITRAMFS) | cpio -idm -D build/installer-root/
	@echo "needs to run as root"
	sudo mount --bind /proc build/installer-root/proc
	sudo mount --bind /sys build/installer-root/sys
	sudo mount --bind /dev build/installer-root/dev
	sudo mount --bind /dev/pts build/installer-root/dev/pts
	sudo cp /etc/resolv.conf build/installer-root/etc/resolv.conf
	sudo chroot build/installer-root /usr/bin/flux update
	sudo chroot build/installer-root /usr/bin/flux install -y kira-installer-tools
	sudo umount build/installer-root/dev/pts
	sudo umount build/installer-root/dev
	sudo umount build/installer-root/sys
	sudo umount build/installer-root/proc
	cp install.sh build/installer-root/usr/bin/kira-install
	chmod +x build/installer-root/usr/bin/kira-install
	mkdir -p build/installer-root/installer
	cp build/kira-base.tar.gz build/installer-root/installer/kira-base.tar.gz
	cp $(KERNEL) build/installer-root/installer/bzImage
	cd build/installer-root && find . | cpio -oH newc --owner root:root | gzip > ../installer-initramfs.cpio.gz

build/BOOTX64.EFI: grub.cfg grub-early.cfg | build/
	grub-mkimage \
		-O x86_64-efi \
		-o build/BOOTX64.EFI \
		-c grub-early.cfg \
		-p /EFI/BOOT \
		iso9660 part_gpt part_msdos fat ext2 normal boot linux echo configfile \
		search search_fs_uuid search_fs_file search_label \
		ls cat help reboot halt

build/kira-base.iso: build/installer-initramfs.cpio.gz $(KERNEL) build/BOOTX64.EFI | build/
	mkdir -p build/iso-root/boot
	mkdir -p build/iso-root/EFI/BOOT
	cp $(KERNEL) build/iso-root/boot/bzImage
	cp build/installer-initramfs.cpio.gz build/iso-root/boot/initramfs.cpio.gz
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

qemu: build/kira-base.iso
	qemu-system-x86_64 \
		-drive file=build/kira-base.iso,format=raw,if=virtio \
		-bios /usr/share/ovmf/OVMF.fd \
		-m 1G \
		-nographic \
		-serial mon:stdio