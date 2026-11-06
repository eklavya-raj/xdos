import os
import shutil
import sys
import time

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
img = os.path.join(out, 'test.img')
shutil.copy(os.path.join(here, '..', 'out', 'os.img'), img)
os.environ['OS_IMG'] = img

from PIL import Image, ImageChops
from shot import Machine

KEY = {' ': 'spc', '.': 'dot', '\n': 'ret'}
results = []


def grab(m, name):
    p = os.path.join(out, name + '.png')
    time.sleep(0.5)
    m.shot(p)
    return Image.open(p).convert('RGB')


def typed(m, text):
    for ch in text:
        m.cmd('sendkey ' + KEY.get(ch, ch))
        time.sleep(0.03)


def icon(m, i):
    m.goto(48, 36 + i * 78)
    m.click()
    time.sleep(0.3)


def check(name, ok):
    results.append((name, bool(ok)))


def diff(a, b, box):
    return ImageChops.difference(a.crop(box), b.crop(box)).getbbox() is not None


m = Machine()
time.sleep(4)
grab(m, '01-desktop')

icon(m, 1)
typed(m, 'write hi.txt hello from terminal\nls\ncat hi.txt\n')
grab(m, '02-terminal')

icon(m, 2)
typed(m, 'saved note')
m.goto(330, 215)
m.click()
grab(m, '03-notepad-saved')

icon(m, 4)
for row, col in ((2, 0), (2, 1), (3, 3), (2, 2), (3, 2)):
    m.goto(660 + 6 + 8 + col * 56 + 26, 100 + 30 + 66 + row * 56 + 26)
    m.click()
    time.sleep(0.15)
grab(m, '04-calculator')

icon(m, 6)
time.sleep(1.5)
a = grab(m, '05-hill-start')
m.cmd('sendkey right 3000')
time.sleep(3.5)
b = grab(m, '06-hill-driven')
check('real hill climb runs', diff(a, b, (246, 140, 886, 540)))

icon(m, 5)
time.sleep(1)
for _ in range(6):
    m.cmd('sendkey spc')
    time.sleep(0.35)
a = grab(m, '07-flappy-1')
m.cmd('sendkey spc')
time.sleep(0.3)
b = grab(m, '08-flappy-2')
check('real flappy runs', diff(a, b, (206, 100, 846, 500)))
time.sleep(3)
grab(m, '09-flappy-crash')

icon(m, 7)
a = grab(m, '10a-paint-open')
m.goto(520, 250)
m.cmd('mouse_button 1')
for _ in range(30):
    m.goto(m.x + 6, m.y + 2)
m.cmd('mouse_button 0')
b = grab(m, '10b-paint-drawn')
check('paint draws', diff(a, b, (426, 120, 846, 400)))

icon(m, 8)
grab(m, '13-browser-home')
m.cmd('sendkey ret')
time.sleep(5)
grab(m, '13b-browser-cern')
m.cmd('sendkey backspace')
m.goto(190, 125)
m.click()
time.sleep(5)
grab(m, '14-browser-link')
m.goto(120, 87)
m.click()
time.sleep(0.3)
for _ in range(24):
    m.cmd('sendkey backspace')
typed(m, 'neverssl.com\n')
time.sleep(5)
grab(m, '15-browser-neverssl')
m.cmd('sendkey pgdn')
grab(m, '16-browser-scrolled')
for _ in range(24):
    m.cmd('sendkey backspace')
typed(m, 'github.com\n')
time.sleep(5)
grab(m, '17-browser-https')

m.goto(880 - 49 + 10, 55)
m.click()
time.sleep(0.6)
full = grab(m, '18-browser-full')
check('browser fills screen', full.getpixel((1000, 700)) == (255, 255, 255))
m.goto(1024 - 49 + 10, 14)
m.click()
time.sleep(0.6)
small = grab(m, '19-browser-restored')
check('browser restores', small.getpixel((1000, 700)) != (255, 255, 255))
m.goto(880 - 71 + 10, 55)
m.click()
time.sleep(0.6)
gone = grab(m, '20-browser-minimized')
check('browser minimizes', gone.getpixel((860, 500)) != small.getpixel((860, 500)))

icon(m, 5)
time.sleep(0.8)
m.goto(200 + 652 - 49 + 10, 75)
m.click()
time.sleep(1.5)
grab(m, '21-flappy-full')
m.goto(1024 - 49 + 10, 14)
m.click()
time.sleep(0.5)

icon(m, 3)
grab(m, '10-files')
m.close()
time.sleep(1)

m = Machine()
time.sleep(4)
icon(m, 3)
c = grab(m, '11-files-after-reboot')
check('file listing survives reboot', c.getpixel((300, 215)) != c.getpixel((300, 480)))
m.goto(160, 236)
m.click()
grab(m, '12-note-reopened')
m.close()

for name, ok in results:
    print(('PASS ' if ok else 'FAIL ') + name)
