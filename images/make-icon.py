"""Renders icon.tga and the CurseForge avatar. Needs Pillow and numpy.

A beveled gold E in Cinzel on the void starfield, in the square gold frame the
Simple Addons icons share. Cinzel is OFL and fetched from google/fonts on
first run.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont
import numpy as np, math, random, os, urllib.request

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

class Icon:
    def __init__(self, N=128, S=4):
        self.N, self.S, self.P = N, S, N * S
        self.img = Image.new("RGBA", (self.P, self.P), (0, 0, 0, 255))
    def canvas(self): return Image.new("RGBA", (self.P, self.P), (0, 0, 0, 0))
    def out(self): return self.img.resize((self.N, self.N), Image.LANCZOS)

    def background(self, top, bottom, glow=None, glow_at=(0.5, 0.5), glow_r=0.6, stars=140, seed=3):
        P = self.P
        y = np.linspace(0, 1, P)[:, None]
        t = np.repeat(y, P, axis=1)
        arr = np.zeros((P, P, 3))
        for i in range(3): arr[..., i] = top[i] * (1 - t) + bottom[i] * t
        if glow:
            xx, yy = np.meshgrid(np.linspace(0, 1, P), np.linspace(0, 1, P))
            d = np.sqrt((xx - glow_at[0]) ** 2 + (yy - glow_at[1]) ** 2) / glow_r
            g = np.clip(1 - d, 0, 1) ** 2.2
            for i in range(3): arr[..., i] += glow[i] * g
        self.img = Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGB").convert("RGBA")
        if stars:
            rnd = random.Random(seed); st = self.canvas(); d = ImageDraw.Draw(st)
            for _ in range(stars):
                x, yv = rnd.random() * P, rnd.random() * P
                r = rnd.choice([0.5, 0.7, 1.0, 1.3, 2.0]) * P / 256
                a = rnd.randint(90, 255)
                d.ellipse([x - r, yv - r, x + r, yv + r], fill=(235, 225, 255, a))
            self.img.alpha_composite(st.filter(ImageFilter.GaussianBlur(P / 600)))
            big = self.canvas(); d = ImageDraw.Draw(big)
            for _ in range(6):
                x, yv = rnd.random() * P, rnd.random() * P; r = P * 0.012
                d.ellipse([x - r, yv - r, x + r, yv + r], fill=(255, 255, 255, 120))
            self.img.alpha_composite(big.filter(ImageFilter.GaussianBlur(P * 0.012)))

    def vignette(self, strength=0.75):
        P = self.P
        xx, yy = np.meshgrid(np.linspace(-1, 1, P), np.linspace(-1, 1, P))
        d = np.clip(np.sqrt(xx ** 2 + yy ** 2) - 0.55, 0, 1.5) / 0.9
        a = (np.clip(d, 0, 1) ** 1.6 * 255 * strength).astype("uint8")
        v = Image.new("RGBA", (P, P), (0, 0, 0, 0)); v.putalpha(Image.fromarray(a, "L"))
        self.img.alpha_composite(v)

    def glow(self, fn, blur, alpha=1.0):
        g = self.canvas(); fn(ImageDraw.Draw(g))
        g = g.filter(ImageFilter.GaussianBlur(blur))
        g.putalpha(g.split()[3].point(lambda v: int(v * alpha)))
        self.img.alpha_composite(g)

    def gradient_poly(self, pts, c0, c1, p0, p1, alpha=255):
        """Fill polygon pts with a linear gradient from colour c0 at point p0 to c1 at p1."""
        P = self.P
        xx, yy = np.meshgrid(np.arange(P), np.arange(P))
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        L = dx * dx + dy * dy
        t = np.clip(((xx - p0[0]) * dx + (yy - p0[1]) * dy) / L, 0, 1)
        arr = np.zeros((P, P, 4), dtype="uint8")
        for i in range(3): arr[..., i] = (c0[i] * (1 - t) + c1[i] * t).astype("uint8")
        arr[..., 3] = alpha
        layer = Image.fromarray(arr, "RGBA")
        m = Image.new("L", (P, P), 0); ImageDraw.Draw(m).polygon(pts, fill=255)
        layer.putalpha(ImageChops.multiply(layer.split()[3], m))
        self.img.alpha_composite(layer)

    def frame(self, gold=(214, 166, 60), hi=(255, 236, 170), lo=(96, 64, 14), w=None):
        P = self.P; w = w or P * 0.035
        d = ImageDraw.Draw(self.img)
        d.rectangle([0, 0, P, P], outline=lo + (255,), width=int(w))
        d.rectangle([w * 0.35, w * 0.35, P - w * 0.35, P - w * 0.35], outline=gold + (255,), width=int(w * 0.45))
        d.line([(w * 0.35, w * 0.35), (P - w * 0.35, w * 0.35)], fill=hi + (255,), width=int(w * 0.18))
        d.line([(w * 0.35, w * 0.35), (w * 0.35, P - w * 0.35)], fill=hi + (255,), width=int(w * 0.18))
        d.line([(P - w * 0.35, w * 0.35), (P - w * 0.35, P - w * 0.35)], fill=lo + (255,), width=int(w * 0.18))
        d.line([(w * 0.35, P - w * 0.35), (P - w * 0.35, P - w * 0.35)], fill=lo + (255,), width=int(w * 0.18))
        d.rectangle([w * 0.8, w * 0.8, P - w * 0.8, P - w * 0.8], outline=(10, 8, 14, 255), width=int(w * 0.15))


FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Cinzel.ttf")
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/cinzel/Cinzel%5Bwght%5D.ttf"
GOLD, GOLD_HI, GOLD_LO = (222, 172, 62), (255, 240, 180), (104, 68, 14)
BG_TOP, BG_BOT, VGLOW = (16, 9, 34), (3, 2, 8), (70, 30, 120)

def circle_mask(P, r=None):
    m = Image.new("L", (P, P), 0); r = r or P / 2
    ImageDraw.Draw(m).ellipse([P / 2 - r, P / 2 - r, P / 2 + r, P / 2 + r], fill=255); return m

def text_mask(P, text, size, font=FONT, weight=700):
    f = ImageFont.truetype(font, int(size))
    try: f.set_variation_by_axes([weight])
    except Exception: pass
    m = Image.new("L", (P, P), 0); d = ImageDraw.Draw(m)
    bbox = d.textbbox((0, 0), text, font=f)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((P / 2 - w / 2 - bbox[0], P / 2 - h / 2 - bbox[1]), text, font=f, fill=255)
    return m

def gold_from_mask(i, m, hi=GOLD_HI, mid=GOLD, lo=GOLD_LO, bevel=0.012, shadow=True, glow=(255, 200, 90)):
    P = i.P
    if glow:
        g = Image.new("RGBA", (P, P), glow + (0,)); g.putalpha(m)
        g = g.filter(ImageFilter.GaussianBlur(P * 0.035))
        g.putalpha(g.split()[3].point(lambda v: int(v * 0.6))); i.img.alpha_composite(g)
    if shadow:
        s = Image.new("RGBA", (P, P), (0, 0, 0, 0)); s.putalpha(m)
        s = ImageChops.offset(s, int(P * 0.01), int(P * 0.018)).filter(ImageFilter.GaussianBlur(P * 0.012))
        i.img.alpha_composite(s)
    # vertical gold gradient through the glyph
    yy = np.repeat(np.linspace(0, 1, P)[:, None], P, axis=1)
    t = np.clip((yy - 0.25) / 0.5, 0, 1)
    arr = np.zeros((P, P, 4), dtype="uint8")
    for k in range(3): arr[..., k] = (hi[k] * (1 - t) + lo[k] * t).astype("uint8")
    arr[..., 3] = 255
    layer = Image.fromarray(arr, "RGBA"); layer.putalpha(m); i.img.alpha_composite(layer)
    # bevel: light on upper-left edge, dark on lower-right, via offset masks
    inner = m.filter(ImageFilter.MinFilter(int(P * bevel) * 2 + 1))
    edge = ImageChops.subtract(m, inner)
    up = ImageChops.offset(edge, -int(P * bevel * 0.6), -int(P * bevel * 0.6))
    hl = Image.new("RGBA", (P, P), (255, 250, 220, 0)); hl.putalpha(ImageChops.multiply(ImageChops.multiply(edge, up), m))
    i.img.alpha_composite(hl)
    dn = ImageChops.offset(edge, int(P * bevel * 0.6), int(P * bevel * 0.6))
    sh = Image.new("RGBA", (P, P), (60, 30, 0, 0)); sh.putalpha(ImageChops.multiply(ImageChops.multiply(edge, dn), m))
    i.img.alpha_composite(sh)
    # a bright core highlight band
    band = np.clip(1 - np.abs(yy - 0.42) / 0.06, 0, 1)
    b = Image.fromarray((band * 110).astype("uint8"), "L")
    hb = Image.new("RGBA", (P, P), (255, 255, 240, 0)); hb.putalpha(ImageChops.multiply(b, inner)); i.img.alpha_composite(hb)

def ring(i, r_frac=0.46, w_frac=0.02):
    P = i.P; c = P / 2; r = P * r_frac; w = P * w_frac
    d = ImageDraw.Draw(i.img)
    d.ellipse([c - r, c - r, c + r, c + r], outline=GOLD_LO + (255,), width=int(w))
    d.ellipse([c - r, c - r, c + r, c + r], outline=GOLD + (255,), width=int(w * 0.55))
    d.arc([c - r, c - r, c + r, c + r], 200, 340, fill=GOLD_HI + (255,), width=int(w * 0.25))

def finish_round(i):
    out = i.out(); m = circle_mask(out.size[0]); out.putalpha(ImageChops.multiply(out.split()[3], m)); return out


def render(N, S=4):
    i = Icon(N, S)
    P = i.P
    i.background(BG_TOP, BG_BOT, glow=VGLOW, glow_at=(0.5, 0.48), glow_r=0.6, stars=160, seed=5)
    gold_from_mask(i, text_mask(P, "E", P * 0.74))
    i.vignette(0.7)
    i.frame()
    return i.out()


HERE = os.path.dirname(os.path.abspath(__file__))
if not os.path.exists(FONT):
    urllib.request.urlretrieve(FONT_URL, FONT)
os.chdir(os.path.join(HERE, ".."))
icon = render(128)
icon.save("images/icon-128.png")
icon.save("icon.tga", compression=None)
render(512, S=2).save("images/curseforge-avatar.png")
print("ok")
