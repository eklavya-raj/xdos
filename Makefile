QEMU ?= qemu-system-i386

.PHONY: all run clean

all:
	python tools/build.py

run: all
	$(QEMU) -drive format=raw,file=out/os.img -m 64 -vga std -rtc base=localtime -nic user,model=rtl8139

clean:
	rm -f out/*
