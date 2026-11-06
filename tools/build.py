import os
import struct
import subprocess
import pack

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
NASM = os.path.expandvars(r'%LOCALAPPDATA%\bin\NASM\nasm.exe')


INC = ['-Iinclude/', '-Ikernel/', '-Ikernel/apps/', '-Ikernel/net/', '-Iout/']


def nasm(src, out):
    subprocess.run([NASM, '-f', 'bin', *INC, src, '-o', out, '-l', out + '.lst'] + os.environ.get('NASMFLAGS', '').split(), cwd=ROOT, check=True)


subprocess.run(['python', os.path.join(HERE, 'mkassets.py')], check=True)
nasm('kernel/kernel.asm', 'out/kernel.bin')
raw = open(os.path.join(ROOT, 'out', 'kernel.bin'), 'rb').read()
# absolute targets pack better
filtered = pack.filter_calls(raw)
assert pack.filter_calls(filtered, -1) == raw
packed = pack.compress(filtered)
assert pack.decompress(packed, len(filtered)) == filtered
with open(os.path.join(ROOT, 'out', 'kernel.lz'), 'wb') as f:
    f.write(struct.pack('<I', len(raw)) + packed)
with open(os.path.join(ROOT, 'out', 'cmtab.inc'), 'w', newline='\n') as f:
    f.write(f'NM equ {len(pack.MASKS)}\ncm_mask db {", ".join(map(str, pack.MASKS))}\ncm_w db {", ".join(map(str, pack.WC))}\n')
nasm('boot/boot.asm', 'out/os.img')
img = open(os.path.join(ROOT, 'out', 'os.img'), 'rb').read()
used = img.rfind(packed[-16:]) + 16
print(f'image {len(img)} bytes, kernel {len(raw)}, packed {len(packed)}, system ends at {used}')
