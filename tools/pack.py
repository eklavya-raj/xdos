# which of the last 8 bytes go in each context
MASKS = [0, 1, 3, 7, 2, 5, 17, 4, 10, 9]
WC = [0, 2, 3, 3, 1, 2, 2, 0, 1, 2]
HBITS = 22
M32 = 0xFFFFFFFF


def hashes(buf, i):
    out = []
    for m in MASKS:
        h = m
        for k in range(8):
            if m >> k & 1:
                h = (h * 0x2F0B3 + (buf[i - 1 - k] if i - 1 - k >= 0 else 0) + 1) & M32
        out.append(h)
    return out


def predict(tab, hs, partial):
    s0 = s1 = 0
    keys = []
    pk = (partial * 0x85EBCA6B) & M32
    for h, w in zip(hs, WC):
        k = (((h * 0x9E3779B1) & M32) + pk) & M32
        k = (k >> (32 - HBITS)) * 2
        keys.append(k)
        s0 += tab[k] << w
        s1 += tab[k + 1] << w
    return ((2 * s0 + 1) << 16) // (2 * (s0 + s1) + 2), keys


def update(tab, keys, bit):
    for k in keys:
        if tab[k + bit] < 255:
            tab[k + bit] += 1
        o = tab[k + 1 - bit]
        if o > 2:
            tab[k + 1 - bit] = (o >> 1) + 1


class Enc:
    def __init__(self):
        self.low, self.range, self.cache, self.size, self.out = 0, M32, 0, 1, bytearray()

    def shift(self):
        if self.low < 0xFF000000 or self.low >= 1 << 32:
            carry = self.low >> 32
            b = self.cache
            while True:
                self.out.append((b + carry) & 255)
                b = 0xFF
                self.size -= 1
                if not self.size:
                    break
            self.cache = (self.low >> 24) & 255
        self.size += 1
        self.low = (self.low << 8) & M32

    def bit(self, p0, b):
        bound = (self.range >> 16) * p0
        if b:
            self.low += bound
            self.range -= bound
        else:
            self.range = bound
        while self.range < 1 << 24:
            self.range = (self.range << 8) & M32
            self.shift()

    def done(self):
        for _ in range(5):
            self.shift()
        return bytes(self.out)


def compress(data):
    tab = bytearray(2 << HBITS)
    e = Enc()
    for i, c in enumerate(data):
        hs = hashes(data, i)
        partial = 1
        for b in range(7, -1, -1):
            bit = c >> b & 1
            p0, keys = predict(tab, hs, partial)
            e.bit(p0, bit)
            update(tab, keys, bit)
            partial = partial * 2 + bit
    return e.done()


def decompress(src, size):
    tab = bytearray(2 << HBITS)
    i = 5
    code = int.from_bytes(src[1:5], 'big')
    rng = M32
    out = bytearray()
    while len(out) < size:
        hs = hashes(out, len(out))
        partial = 1
        while partial < 256:
            p0, keys = predict(tab, hs, partial)
            bound = (rng >> 16) * p0
            if code < bound:
                rng = bound
                bit = 0
            else:
                code -= bound
                rng -= bound
                bit = 1
            while rng < 1 << 24:
                rng = (rng << 8) & M32
                code = ((code << 8) | (src[i] if i < len(src) else 0)) & M32
                i += 1
            update(tab, keys, bit)
            partial = partial * 2 + bit
        out.append(partial & 255)
    return bytes(out)


def filter_calls(data, sign=1):
    b = bytearray(data)
    i = 0
    while i + 5 <= len(b):
        k = 0
        if b[i] in (0xE8, 0xE9):
            k = 1
        elif b[i] == 0x0F and b[i + 1] & 0xF0 == 0x80:
            k = 2
        if k and i + k + 4 <= len(b):
            r = int.from_bytes(b[i + k:i + k + 4], 'little')
            b[i + k:i + k + 4] = ((r + sign * (i + k + 4)) & M32).to_bytes(4, 'little')
            i += k + 4
        else:
            i += 1
    return bytes(b)
