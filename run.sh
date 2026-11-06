#!/bin/sh
set -e
python tools/build.py
qemu-system-i386 -drive format=raw,file=out/os.img -m 64 -vga std -rtc base=localtime -nic user,model=rtl8139 "$@"
