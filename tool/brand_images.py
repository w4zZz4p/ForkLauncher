"""Generate ForkLauncher's brand images: a white table fork on solid dark grey.

Writes straight into the repo:
  - app icon: android/app/src/main/res/mipmap-*/ic_launcher.png
  - adaptive icon foreground: res/drawable-*/ic_launcher_foreground.png
  - TV banner: res/drawable{,-xhdpi}/banner.png
  - launch screen outline: res/drawable-*/splash_fork.png
  - assets/icon.png (About dialog), assets/banner.png
  - fastlane/metadata/android/en-US/images/icon.png

Usage, from the repo root:  python3 tool/brand_images.py
Needs Pillow. The banner text uses Roboto, found in the pub cache.
The adaptive icon background colour is in res/values/colors.xml and should match BG.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
SS = 4  # supersampling factor

BG = (0x2B, 0x2B, 0x2E)  # dark grey; keep ic_launcher_background in colors.xml the same
SHADOW = (12, 12, 14)
WHITE = (255, 255, 255)
ANGLE = -32  # fork tilt in degrees


def find_font(name):
    for path in sorted((Path.home() / ".pub-cache").rglob(name)):
        return path
    raise SystemExit(f"{name} not found in ~/.pub-cache; set the path in find_font()")


def background(w, h):
    return Image.new("RGB", (w, h), BG)


def fork_mask(size, angle=ANGLE):
    """Fork glyph as an L-mode mask of `size` px, tilted and centred on its bounding box."""
    S = size * SS
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    cx = S / 2
    u = S / 100  # the fork is drawn in a 100x100 box

    # Tines: rounded tops, square bottoms hidden inside the head.
    tine_w, gap = 5.2 * u, 3.6 * u
    total = 4 * tine_w + 3 * gap
    top = 6 * u
    x0 = cx - total / 2
    for i in range(4):
        x = x0 + i * (tine_w + gap)
        d.rounded_rectangle((x, top, x + tine_w, top + 3 * tine_w), radius=tine_w / 2, fill=255)
        d.rectangle((x, top + tine_w, x + tine_w, 33 * u), fill=255)

    # Head: straight sides under the tines, then an S-curve into the neck.
    head_top, head_bottom = 32 * u, 58 * u
    neck_w = 7.5 * u
    steps = 60

    def half_width(t):
        s = 3 * t * t - 2 * t * t * t  # smoothstep: vertical at both ends, so no kinks
        return neck_w / 2 + (total / 2 - neck_w / 2) * (1 - s)

    ys = [head_top + (head_bottom - head_top) * s / steps for s in range(steps + 1)]
    pts = [(cx + half_width(s / steps), ys[s]) for s in range(steps + 1)]
    pts += [(cx - half_width(s / steps), ys[s]) for s in range(steps, -1, -1)]
    d.polygon(pts, fill=255)

    # Handle: widens slightly towards a rounded end.
    hb_top, hb_len = 57 * u, 34 * u
    side = [(neck_w / 2 + 2.2 * u * (s / steps) ** 1.4, hb_top + hb_len * s / steps) for s in range(steps + 1)]
    d.polygon([(cx + w, y) for w, y in side] + [(cx - w, y) for w, y in reversed(side)], fill=255)
    end_w, end_y = side[-1][0], side[-1][1]
    d.ellipse((cx - end_w, end_y - end_w, cx + end_w, end_y + end_w), fill=255)

    m = m.rotate(angle, resample=Image.BICUBIC, center=(cx, S / 2))
    l, t, r, b = m.getbbox()
    m = m.transform(m.size, Image.AFFINE, (1, 0, (l + r) / 2 - S / 2, 0, 1, (t + b) / 2 - S / 2))
    return m.resize((size, size), Image.LANCZOS)


def paste_glyph(base, glyph_size, center):
    mask = fork_mask(glyph_size)
    x, y = round(center[0] - glyph_size / 2), round(center[1] - glyph_size / 2)
    shadow = Image.new("L", base.size, 0)
    blurred = mask.filter(ImageFilter.GaussianBlur(glyph_size / 40)).point(lambda p: p * 0.35)
    shadow.paste(blurred, (x + glyph_size // 60, y + glyph_size // 40))
    base.paste(Image.new("RGB", base.size, SHADOW), (0, 0), shadow)
    base.paste(Image.new("RGB", (glyph_size, glyph_size), WHITE), (x, y), mask)
    return base


def icon(size):
    return paste_glyph(background(size, size), round(size * 0.78), (size / 2, size / 2))


def adaptive_foreground(size):
    """108dp adaptive layer: full-bleed background, fork kept inside the 66dp safe zone."""
    return paste_glyph(background(size, size), round(size * 0.56), (size / 2, size / 2))


def sheared_text(text, font, shear=0.2):
    """Text slanted by hand, since only upright Roboto is available."""
    l, t, r, b = font.getbbox(text)
    w, h = r - l + int((b - t) * shear) + 4, b - t + 4
    layer = Image.new("L", (w, h), 0)
    ImageDraw.Draw(layer).text((-l + int((b - t) * shear) + 2, -t + 2), text, font=font, fill=255)
    return layer.transform(layer.size, Image.AFFINE, (1, shear, -shear * h, 0, 1, 0), Image.BICUBIC)


def banner(w, h):
    W, H = w * SS, h * SS
    im = background(W, H)
    paste_glyph(im, round(H * 0.72), (W * 0.25, H * 0.5))
    size = round(H * 0.2)
    t1 = sheared_text("fork", ImageFont.truetype(str(find_font("Roboto-Light.ttf")), size))
    t2 = sheared_text("launcher", ImageFont.truetype(str(find_font("Roboto-Bold.ttf")), size))
    tx, gap = round(W * 0.43), round(H * 0.01)
    ty = round((H - (t1.height + gap + t2.height)) / 2)
    white = Image.new("RGB", im.size, WHITE)
    for layer, y in ((t1, ty), (t2, ty + t1.height + gap)):
        full = Image.new("L", im.size, 0)
        full.paste(layer, (tx, y))
        im.paste(white, (0, 0), full)
    return im.resize((w, h), Image.LANCZOS)


def splash_outline(size, stroke=0.014):
    """White outline of the fork on transparency, for the launch screen."""
    big = size * SS
    mask = fork_mask(big)
    k = max(3, round(big * stroke)) | 1
    ring = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(k)))  # stroke inwards
    out = Image.new("RGBA", (big, big), WHITE + (0,))
    out.putalpha(ring)
    return out.resize((size, size), Image.LANCZOS)


DENSITIES = ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")
SCALE = dict(zip(DENSITIES, (1, 1.5, 2, 3, 4)))


def main():
    for d in DENSITIES:
        icon(round(48 * SCALE[d])).save(RES / f"mipmap-{d}/ic_launcher.png")
        adaptive_foreground(round(108 * SCALE[d])).save(RES / f"drawable-{d}/ic_launcher_foreground.png")
        splash_outline(round(80 * SCALE[d])).save(RES / f"drawable-{d}/splash_fork.png")
    tv_banner = banner(320, 180)
    for path in (RES / "drawable/banner.png", RES / "drawable-xhdpi/banner.png", ROOT / "assets/banner.png"):
        tv_banner.save(path)
    icon(512).save(ROOT / "assets/icon.png")
    icon(1024).save(ROOT / "fastlane/metadata/android/en-US/images/icon.png")
    print("brand images written")


if __name__ == "__main__":
    main()
