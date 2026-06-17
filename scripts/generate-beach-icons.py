#!/usr/bin/env python3
"""Generate beach/resort stained glass icon PNGs with transparent backgrounds.

Tropical motifs rendered in the same stained-glass language as the cathedral
icons (visible lead lines, jewel-toned glass): sun, palm, wave, cocktail,
flamingo, seashell, starfish, pineapple. These drift across the video wall in
the "beach" theme.

Pure standard library (no numpy/PIL), matching generate-icons.py.

    SANCTUM_ICON_SIZE   override icon size (default 512)
    SANCTUM_ASSETS      override output root (default <repo>/Assets)
"""

import struct
import zlib
import math
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_ROOT = os.environ.get("SANCTUM_ASSETS", os.path.join(REPO_ROOT, "Assets"))
OUTPUT_DIR = os.path.join(ASSETS_ROOT, "icons")
SIZE = int(os.environ.get("SANCTUM_ICON_SIZE", "512"))


def make_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        row_start = y * width * 4
        raw += bytes(pixels[row_start:row_start + width * 4])
    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend


def dist(x1, y1, x2, y2):
    return math.hypot(x2 - x1, y2 - y1)


def lead_line(d, width=3):
    if d < width:
        return 0.16
    elif d < width + 1.5:
        return 0.42
    return 1.0


def glass(base_r, base_g, base_b, x, y):
    noise = math.sin(x * 0.3) * math.cos(y * 0.4) * 0.08
    grain = math.sin(x * 2.1 + y * 1.7) * 0.03
    f = 1.0 + noise + grain
    return (max(0, min(255, int(base_r * f))),
            max(0, min(255, int(base_g * f))),
            max(0, min(255, int(base_b * f))))


def new_canvas():
    return bytearray(SIZE * SIZE * 4)


def put(px, idx, rgb, lead=1.0):
    px[idx] = max(0, min(255, int(rgb[0] * lead)))
    px[idx + 1] = max(0, min(255, int(rgb[1] * lead)))
    px[idx + 2] = max(0, min(255, int(rgb[2] * lead)))
    px[idx + 3] = 255


def stamp_region(region, cx, cy, r, value):
    r = max(1, int(r))
    x0, x1 = max(0, int(cx - r)), min(SIZE - 1, int(cx + r))
    y0, y1 = max(0, int(cy - r)), min(SIZE - 1, int(cy + r))
    rr = r * r
    for yy in range(y0, y1 + 1):
        row = region[yy]
        dy = yy - cy
        for xx in range(x0, x1 + 1):
            dx = xx - cx
            if dx * dx + dy * dy <= rr:
                row[xx] = value


# ---------------------------------------------------------------- sun

def generate_sun():
    px = new_canvas()
    cx = cy = SIZE / 2
    core_r = SIZE * 0.30
    ray_in = core_r
    ray_out = SIZE * 0.47
    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            d = dist(x, y, cx, cy)
            ang = math.atan2(y - cy, x - cx)
            inside = False
            is_core = d <= core_r
            if is_core:
                inside = True
            elif ray_in < d < ray_out:
                slot = (ang % (math.pi / 6)) / (math.pi / 6)  # 0..1 in each of 12 slots
                halfw = 0.5 * (1.0 - (d - ray_in) / (ray_out - ray_in))
                if abs(slot - 0.5) < halfw * 0.5:
                    inside = True
            if not inside:
                continue
            lead = 1.0
            if is_core:
                # radial spokes + inner ring
                for i in range(12):
                    spoke = i * math.pi / 6
                    diff = abs(((ang - spoke + math.pi) % (2 * math.pi)) - math.pi)
                    lead = min(lead, lead_line(diff * d, 2))
                lead = min(lead, lead_line(abs(d - core_r * 0.55), 2))
                col = glass(255, 205, 40, x, y)
            else:
                col = glass(245, 150, 25, x, y)
            put(px, idx, col, lead)
    return px


# ---------------------------------------------------------------- palm

def generate_palm():
    px = new_canvas()
    region = [bytearray(SIZE) for _ in range(SIZE)]
    base_x, base_y = SIZE * 0.5, SIZE * 0.97
    crown_x, crown_y = SIZE * 0.52, SIZE * 0.34
    # trunk (region 1)
    steps = int(base_y - crown_y)
    for i in range(steps):
        t = i / max(1, steps - 1)
        tx = (base_x + (crown_x - base_x) * t) + math.sin(t * math.pi) * SIZE * 0.03
        ty = base_y - (base_y - crown_y) * t
        stamp_region(region, tx, ty, (1 - t) * SIZE * 0.028 + SIZE * 0.012, 1)
    # fronds (region 2)
    fronds = [(-2.4, 0.5), (-1.4, 0.28), (-0.5, 0.1),
              (0.5, 0.1), (1.4, 0.28), (2.4, 0.5), (0.0, -0.12)]
    flen = SIZE * 0.42
    for ang_bias, sag in fronds:
        ang = math.pi * 0.5 + ang_bias * 0.5
        fsteps = int(flen)
        for j in range(fsteps):
            t = j / max(1, fsteps - 1)
            fx = crown_x + math.cos(ang) * flen * t
            fy = crown_y - math.sin(ang) * flen * t + sag * flen * (t * t)
            stamp_region(region, fx, fy, (1 - t) * SIZE * 0.018 + SIZE * 0.003, 2)
    # coconuts (region 3)
    for ox in (-0.03, 0.03, 0.0):
        stamp_region(region, crown_x + ox * SIZE, crown_y + SIZE * 0.04, SIZE * 0.022, 3)
    for y in range(SIZE):
        for x in range(SIZE):
            rgv = region[y][x]
            if rgv == 0:
                continue
            idx = (y * SIZE + x) * 4
            if rgv == 1:
                col = glass(150, 95, 40, x, y)        # trunk brown
                lead = lead_line(abs(((y * 0.5) % 22) - 11), 2)
            elif rgv == 2:
                col = glass(35, 165, 70, x, y)         # frond green
                lead = 1.0
            else:
                col = glass(120, 80, 35, x, y)         # coconut
                lead = 1.0
            put(px, idx, col, lead)
    return px


# ---------------------------------------------------------------- wave

def generate_wave():
    px = new_canvas()
    curl_cx, curl_cy = SIZE * 0.34, SIZE * 0.44
    curl_r = SIZE * 0.26
    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            crest = SIZE * 0.34 + SIZE * 0.16 * math.sin(x / SIZE * 3.4 + 0.6)
            d_curl = dist(x, y, curl_cx, curl_cy)
            in_body = y > crest
            in_curl = d_curl < curl_r
            in_barrel = d_curl < curl_r * 0.42  # hollow eye of the wave
            if in_barrel:
                continue
            if not (in_body or in_curl):
                continue
            t = min(1.0, max(0.0, (y - crest) / (SIZE - crest)))
            col = glass(int(40 + 20 * (1 - t)), int(150 - 40 * t), int(210 - 40 * t), x, y)
            lead = 1.0
            # foam near crest and around curl rim
            if abs(y - crest) < SIZE * 0.03 or abs(d_curl - curl_r) < SIZE * 0.03:
                col = glass(235, 245, 255, x, y)
            # spiral foam lines in the curl
            if in_curl:
                ring = (d_curl / (SIZE * 0.05))
                lead = lead_line(abs(ring - round(ring)) * SIZE * 0.05, 2)
            put(px, idx, col, lead)
    return px


# ---------------------------------------------------------------- cocktail

def generate_cocktail():
    px = new_canvas()
    cx = SIZE * 0.5
    cup_top, cup_tip = SIZE * 0.30, SIZE * 0.56
    cup_halfw = SIZE * 0.26
    base_y = SIZE * 0.86
    umb_cx, umb_cy = SIZE * 0.66, SIZE * 0.20
    umb_r = SIZE * 0.18
    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            col = None
            lead = 1.0
            # umbrella
            d_umb = dist(x, y, umb_cx, umb_cy)
            if y <= umb_cy and d_umb < umb_r:
                seg = int(((math.atan2(y - umb_cy, x - umb_cx) + math.pi) / (2 * math.pi)) * 8) % 8
                pink = (240, 70, 120) if seg % 2 == 0 else (255, 220, 60)
                col = glass(*pink, x=x, y=y)
                lead = lead_line(abs(((math.atan2(y - umb_cy, x - umb_cx)) % (math.pi / 4)) * d_umb), 2)
            # umbrella stick
            elif abs(x - (umb_cx - SIZE * 0.0)) < SIZE * 0.006 and umb_cy < y < cup_top + SIZE * 0.05:
                col = glass(120, 80, 40, x, y)
            # cup (inverted triangle)
            elif cup_top <= y <= cup_tip:
                hw = (cup_tip - y) / (cup_tip - cup_top) * cup_halfw
                if abs(x - cx) <= hw:
                    if y < cup_top + (cup_tip - cup_top) * 0.55:
                        col = glass(255, 140, 40, x, y)     # tropical drink
                    else:
                        col = glass(255, 200, 90, x, y)
                    lead = min(lead_line(hw - abs(x - cx), 3), lead_line(abs(x - cx), 2))
            # stem
            elif cup_tip < y < base_y and abs(x - cx) < SIZE * 0.018:
                col = glass(220, 230, 240, x, y)
            # base
            elif abs(y - base_y) < SIZE * 0.02 and abs(x - cx) < SIZE * 0.14:
                col = glass(220, 230, 240, x, y)
            if col is None:
                continue
            put(px, idx, col, lead)
    return px


# ---------------------------------------------------------------- flamingo

def generate_flamingo():
    px = new_canvas()
    region = [bytearray(SIZE) for _ in range(SIZE)]
    # body (1)
    bx, by = SIZE * 0.44, SIZE * 0.56
    for yy in range(SIZE):
        for xx in range(SIZE):
            if ((xx - bx) / (SIZE * 0.20)) ** 2 + ((yy - by) / (SIZE * 0.15)) ** 2 < 1.0:
                region[yy][xx] = 1
    # neck (2): S-curve up to head
    nsteps = 120
    for i in range(nsteps):
        t = i / (nsteps - 1)
        nx = bx + SIZE * 0.12 * math.sin(t * 2.2)
        ny = by - SIZE * 0.04 - t * SIZE * 0.36
        stamp_region(region, nx, ny, SIZE * 0.028 * (1 - 0.3 * t), 2)
    head_x, head_y = bx + SIZE * 0.12 * math.sin(2.2), by - SIZE * 0.04 - SIZE * 0.36
    stamp_region(region, head_x, head_y, SIZE * 0.05, 2)
    # beak (3)
    for i in range(40):
        t = i / 39
        stamp_region(region, head_x + t * SIZE * 0.10, head_y + t * SIZE * 0.05,
                     SIZE * 0.02 * (1 - t), 3)
    # legs (4)
    for lx in (bx - SIZE * 0.02, bx + SIZE * 0.05):
        for i in range(120):
            t = i / 119
            stamp_region(region, lx + math.sin(t * 3) * SIZE * 0.01,
                         by + SIZE * 0.13 + t * SIZE * 0.26, SIZE * 0.008, 4)
    for y in range(SIZE):
        for x in range(SIZE):
            rgv = region[y][x]
            if rgv == 0:
                continue
            idx = (y * SIZE + x) * 4
            if rgv == 3:
                col = glass(30, 30, 40, x, y)              # beak tip
            elif rgv == 4:
                col = glass(235, 120, 150, x, y)           # legs
            else:
                col = glass(240, 110, 160, x, y)           # body/neck pink
            put(px, idx, col)
    # eye
    ei = (int(head_y - SIZE * 0.01) * SIZE + int(head_x + SIZE * 0.02)) * 4
    if 0 <= ei < len(px) - 4:
        put(px, ei, (20, 20, 30))
    return px


# ---------------------------------------------------------------- shell

def generate_shell():
    px = new_canvas()
    hinge_x, hinge_y = SIZE * 0.5, SIZE * 0.86
    R = SIZE * 0.74
    ribs = 9
    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            dx, dy = x - hinge_x, y - hinge_y
            if dy > 0:
                continue
            d = math.hypot(dx, dy)
            ang = math.atan2(-dy, dx)  # 0..pi across the top
            if ang < 0.15 or ang > math.pi - 0.15:
                continue
            rib = (ang / math.pi) * ribs
            edge = R * (0.92 + 0.08 * math.cos(rib * math.pi * 2))
            if d > edge:
                continue
            base = lerp3((255, 150, 130), (255, 210, 170), d / R)
            col = glass(int(base[0]), int(base[1]), int(base[2]), x, y)
            lead = lead_line(abs(rib - round(rib)) * (R * 0.18), 2)
            lead = min(lead, lead_line(R - d, 3) if d > R * 0.85 else 1.0)
            put(px, idx, col, lead)
    return px


# ---------------------------------------------------------------- starfish

def generate_starfish():
    px = new_canvas()
    cx = cy = SIZE / 2
    outer, inner = SIZE * 0.46, SIZE * 0.20
    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            ang = math.atan2(dy, dx) - math.pi / 2
            k = (math.cos(5 * ang) + 1) / 2  # 1 at points, 0 between
            radius = inner + (outer - inner) * k
            if d > radius:
                continue
            col = glass(245, 140, 45, x, y)
            lead = 1.0
            # arm midline leads + center
            armline = abs((( (ang) % (2 * math.pi / 5)) - (math.pi / 5)))
            lead = min(lead, lead_line(armline * d, 2))
            lead = min(lead, lead_line(d - inner * 0.7, 2) if d < inner else 1.0)
            # little bumps
            if (int(x * 0.18) + int(y * 0.18)) % 7 == 0 and d < radius * 0.85:
                col = glass(255, 180, 80, x, y)
            put(px, idx, col, lead)
    return px


# ---------------------------------------------------------------- pineapple

def generate_pineapple():
    px = new_canvas()
    cx = SIZE * 0.5
    body_cy = SIZE * 0.62
    body_hw = SIZE * 0.22
    body_hh = SIZE * 0.30
    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            # crown leaves (upper)
            if y < body_cy - body_hh * 0.7:
                leaf = False
                for off, h in [(-0.12, 0.0), (-0.05, -0.06), (0.0, -0.10),
                               (0.05, -0.06), (0.12, 0.0)]:
                    lx = cx + off * SIZE
                    tip_y = SIZE * (0.18 + h)
                    base_y = body_cy - body_hh * 0.6
                    if tip_y < y < base_y:
                        t = (y - tip_y) / (base_y - tip_y)
                        w = SIZE * 0.035 * t
                        if abs(x - lx) < w:
                            leaf = True
                if leaf:
                    put(px, idx, glass(40, 160, 70, x, y))
                continue
            # body (ellipse) with cross-hatch diamonds
            nx = (x - cx) / body_hw
            ny = (y - body_cy) / body_hh
            if nx * nx + ny * ny <= 1.0:
                col = glass(225, 175, 45, x, y)
                u = (x - cx) * 0.10 + (y - body_cy) * 0.10
                v = (x - cx) * 0.10 - (y - body_cy) * 0.10
                lead = min(lead_line(abs(u - round(u)) * 10, 2),
                           lead_line(abs(v - round(v)) * 10, 2))
                put(px, idx, col, lead)
    return px


def lerp3(a, b, t):
    return (a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t)


def save_icon(name, px):
    path = os.path.join(OUTPUT_DIR, f"{name}.png")
    data = make_png(SIZE, SIZE, px)
    with open(path, 'wb') as f:
        f.write(data)
    print(f"  {name}.png ({len(data) / 1024:.1f} KB)")


GENERATORS = {
    "icon-beach-sun": generate_sun,
    "icon-beach-palm": generate_palm,
    "icon-beach-wave": generate_wave,
    "icon-beach-cocktail": generate_cocktail,
    "icon-beach-flamingo": generate_flamingo,
    "icon-beach-shell": generate_shell,
    "icon-beach-starfish": generate_starfish,
    "icon-beach-pineapple": generate_pineapple,
}


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Generating beach stained glass icons into {OUTPUT_DIR}")
    for name, fn in GENERATORS.items():
        save_icon(name, fn())
    print("Done!")
