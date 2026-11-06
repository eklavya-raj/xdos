import os
import socket
import subprocess
import sys
import time
from PIL import Image

QEMU = r'C:\Program Files\qemu\qemu-system-i386.exe'
HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.environ.get('OS_IMG', os.path.join(HERE, '..', 'out', 'os.img'))
PORT = 4455


class Machine:
    def __init__(self):
        self.p = subprocess.Popen([QEMU, '-drive', f'format=raw,file={IMG}', '-m', '64', '-vga', 'std', '-display', 'none', '-rtc', 'base=localtime', '-nic', 'user,model=rtl8139',
                                   '-monitor', f'tcp:127.0.0.1:{PORT},server,nowait'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(50):
            try:
                self.s = socket.create_connection(('127.0.0.1', PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.1)
        self.s.settimeout(0.3)
        self.x, self.y = 512, 384
        self.read()

    def read(self):
        try:
            while self.s.recv(4096):
                pass
        except OSError:
            pass

    def cmd(self, c):
        self.s.sendall(c.encode() + b'\n')
        self.read()

    def move(self, dx, dy):
        while dx or dy:
            sx = max(-100, min(100, dx))
            sy = max(-100, min(100, dy))
            self.cmd(f'mouse_move {sx} {sy}')
            dx -= sx
            dy -= sy

    def goto(self, x, y):
        self.move(x - self.x, y - self.y)
        self.x, self.y = x, y

    def click(self):
        self.cmd('mouse_button 1')
        self.cmd('mouse_button 0')

    def shot(self, out):
        ppm = out + '.ppm'
        self.cmd(f'screendump {ppm.replace(chr(92), "/")}')
        time.sleep(0.4)
        Image.open(ppm).save(out)
        os.remove(ppm)

    def close(self):
        self.p.kill()


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    m = Machine()
    time.sleep(4)
    m.shot(os.path.join(out, '1-desktop.png'))
    m.move(-462, 364)
    m.click()
    time.sleep(0.6)
    m.shot(os.path.join(out, '2-start-menu.png'))
    m.move(60, -130)
    m.click()
    time.sleep(0.5)
    for k in 'h-e-l-l-o spc w-o-r-l-d'.replace('-', ' ').split():
        m.cmd(f'sendkey {k}')
    time.sleep(0.5)
    m.shot(os.path.join(out, '3-notepad.png'))
    m.close()
