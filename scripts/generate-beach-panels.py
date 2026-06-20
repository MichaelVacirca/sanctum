#!/usr/bin/env python3
"""Generate beach/resort stained glass panel textures (1920x1080), no text.

Five panels, one per energy phase of the "beach" theme, forming a feel-good
nighttime-beach arc:

    1. panel-beach-sunset      — warm sun low over the water
    2. panel-beach-goldenhour  — golden sky, palm silhouettes
    3. panel-beach-dusk        — teal/magenta tropical twilight, first stars
    4. panel-beach-neonnight    — neon Miami night, moon + reflection
    5. panel-beach-midnight    — electric peak, starfield over moonlit waves

Each panel is rendered as a beach scene (sky gradient, sun/moon, sea with a
shimmering reflection, palm silhouettes, stars) and then "glassed" with a
Voronoi lead-line overlay so it reads as hand-crafted stained glass — the same
visual language as the cathedral panels.

Pure standard library (no numpy/PIL), matching generate-panels.py.

Resolution and output dir are configurable for quick previews:
    SANCTUM_PANEL_W / SANCTUM_PANEL_H   override size (default 1920x1080)
    SANCTUM_ASSETS                       override output root (default <repo>/Assets)
"""

import struct
import zlib
import math
import os
import random

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_ROOT = os.environ.get("SANCTUM_ASSETS", os.path.join(REPO_ROOT, "Assets"))
OUTPUT_DIR = os.path.join(ASSETS_ROOT, "panels")
WIDTH = int(os.environ.get("SANCTUM_PANEL_W", "1920"))
HEIGHT = int(os.environ.get("SANCTUM_PANEL_H", "1080"))


def make_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        row_start = y * width * 4
        raw += bytes(pixels[row_start:row_start + width * 4])
    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 6))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend


def hash2d(x, y):
    n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
    return n - math.floor(n)


def voronoi_cell(px, py, grid_size):
    """Return (min_dist, second_dist, cell_id) for a jittered Voronoi grid."""
    gx = int(px / grid_size)
    gy = int(py / grid_size)
    min_d = 1e9
    second_d = 1e9
    cell_id = 0
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            cx, cy = gx + dx, gy + dy
            jx = cx * grid_size + hash2d(cx, cy) * grid_size * 0.8 + grid_size * 0.1
            jy = cy * grid_size + hash2d(cy + 100, cx + 200) * grid_size * 0.8 + grid_size * 0.1
            d = math.hypot(px - jx, py - jy)
            if d < min_d:
                second_d = min_d
                min_d = d
                cell_id = (cx * 7919 + cy * 104729) % 4096
            elif d < second_d:
                second_d = d
    return min_d, second_d, cell_id


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_rgb(c1, c2, t):
    return (lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t))


def clamp8(v):
    return max(0, min(255, int(v)))


def build_palm_mask(width, height, palms):
    """Rasterize palm silhouettes into a boolean mask (list of bytearrays)."""
    mask = [bytearray(width) for _ in range(height)]
    if not palms:
        return mask

    def stamp(cx, cy, r):
        r = max(1, int(r))
        x0, x1 = max(0, int(cx - r)), min(width - 1, int(cx + r))
        y0, y1 = max(0, int(cy - r)), min(height - 1, int(cy + r))
        rr = r * r
        for yy in range(y0, y1 + 1):
            row = mask[yy]
            dy = yy - cy
            for xx in range(x0, x1 + 1):
                dx = xx - cx
                if dx * dx + dy * dy <= rr:
                    row[xx] = 1

    s = width / 1920.0  # scale factor relative to design resolution
    palm_defs = [
        (width * 0.16, height * 0.96, 1.05, -1),
        (width * 0.85, height * 0.99, 1.25, 1),
    ]
    for base_x, base_y, scale, lean in palm_defs:
        trunk_h = height * 0.46 * scale
        crown_x = base_x + lean * 26 * s * scale
        crown_y = base_y - trunk_h
        # Trunk: gentle curve from base to crown
        steps = int(trunk_h)
        for i in range(steps):
            t = i / max(1, steps - 1)
            tx = lerp(base_x, crown_x, t) + lean * math.sin(t * math.pi) * 18 * s * scale
            ty = lerp(base_y, crown_y, t)
            stamp(tx, ty, lerp(11 * s * scale, 6 * s * scale, t))
        # Fronds: arcs radiating from the crown
        fronds = [(-2.5, 0.55), (-1.5, 0.30), (-0.7, 0.12),
                  (0.7, 0.12), (1.5, 0.30), (2.5, 0.55), (0.0, -0.15)]
        flen = 230 * s * scale
        for ang_bias, sag in fronds:
            ang = math.pi * 0.5 + ang_bias * 0.55  # spread around upward
            fsteps = int(flen)
            for j in range(fsteps):
                t = j / max(1, fsteps - 1)
                fx = crown_x + math.cos(ang) * flen * t
                fy = crown_y - math.sin(ang) * flen * t + sag * flen * (t * t)
                stamp(fx, fy, lerp(7 * s * scale, 1.2 * s * scale, t))
    return mask


def _shadow(d, s):
    """Recessed-edge shadow factor: darkest at an edge, fading to 1.0 over s px."""
    if d < 0 or d >= s:
        return 1.0
    return 0.55 + 0.45 * (d / s)


def draw_resort_window(pixels):
    """Overlay an arched resort window (cream frame + sunburst arch + pane
    muntins + sill) so the beach scene becomes the view through the window."""
    FT = max(2, int(0.055 * WIDTH))       # frame thickness
    sill_h = max(3, int(0.11 * HEIGHT))
    op_l, op_r = FT, WIDTH - FT
    op_t, op_b = FT, HEIGHT - sill_h
    op_w = op_r - op_l
    cx = (op_l + op_r) / 2.0
    radius_x = op_w / 2.0
    y_spring = op_t + int(0.36 * HEIGHT)  # arch springline
    arch_h = y_spring - op_t
    mun_w = max(1, int(0.012 * WIDTH))    # muntin half-width
    col1 = op_l + op_w // 3
    col2 = op_l + 2 * op_w // 3
    tr_h = max(1, int(0.014 * HEIGHT))    # transom half-height
    shadow = max(2, int(0.014 * WIDTH))
    base = (240, 230, 210)

    for y in range(HEIGHT):
        grad = 1.0 - 0.18 * (y / HEIGHT)  # subtle top-lit gradient on the frame
        fcol = (base[0] * grad, base[1] * grad, base[2] * grad)
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            in_open = (op_l <= x < op_r and op_t <= y < op_b)
            is_frame = not in_open

            if in_open and y < y_spring:
                tnorm = (x - cx) / radius_x
                if abs(tnorm) >= 1.0:
                    is_frame = True
                elif y < y_spring - math.sqrt(1 - tnorm * tnorm) * arch_h:
                    is_frame = True

            is_mun = False
            if in_open and not is_frame:
                if y >= y_spring:
                    if abs(x - col1) < mun_w or abs(x - col2) < mun_w:
                        is_mun = True
                    if abs(y - y_spring) < tr_h:
                        is_mun = True
                else:
                    ang = math.atan2(y_spring - y, x - cx)
                    rad = math.hypot(x - cx, y_spring - y)
                    for i in range(1, 6):
                        if abs(ang - i * math.pi / 6) * rad < mun_w:
                            is_mun = True
                            break
                    if abs(y - y_spring) < tr_h:
                        is_mun = True

            if is_frame or is_mun:
                pixels[idx] = clamp8(fcol[0])
                pixels[idx + 1] = clamp8(fcol[1])
                pixels[idx + 2] = clamp8(fcol[2])
                pixels[idx + 3] = 255
            else:
                # Recessed shadow on the glass next to frame/muntins → depth.
                sh = min(_shadow(x - op_l, shadow), _shadow(op_r - 1 - x, shadow))
                if y >= y_spring:
                    sh = min(sh, _shadow(op_b - 1 - y, shadow),
                             _shadow(abs(x - col1) - mun_w, shadow),
                             _shadow(abs(x - col2) - mun_w, shadow),
                             _shadow(y - y_spring - tr_h, shadow))
                if sh < 1.0:
                    pixels[idx] = clamp8(pixels[idx] * sh)
                    pixels[idx + 1] = clamp8(pixels[idx + 1] * sh)
                    pixels[idx + 2] = clamp8(pixels[idx + 2] * sh)


def generate_beach_panel(name, cfg):
    print(f"  rendering {name} ({WIDTH}x{HEIGHT})...")
    pixels = bytearray(WIDTH * HEIGHT * 4)
    rng = random.Random(cfg.get("seed", 1))

    horizon = cfg["horizon"]
    horizon_y = HEIGHT * horizon
    sky_top = cfg["sky_top"]
    sky_horizon = cfg["sky_horizon"]
    sea_horizon = cfg["sea_horizon"]
    sea_near = cfg["sea_near"]
    sun = cfg.get("sun")            # (x_frac, y_frac, r_frac, color, glow) or None
    neon = cfg.get("neon", 0.0)
    glass_grid = cfg.get("glass_grid", 150) * (WIDTH / 1920.0)

    palm_mask = build_palm_mask(WIDTH, HEIGHT, cfg.get("palms", False))

    sun_cx = sun[0] * WIDTH if sun else 0
    sun_cy = sun[1] * HEIGHT if sun else 0
    sun_r = sun[2] * HEIGHT if sun else 0

    for y in range(HEIGHT):
        in_sea = y >= horizon_y
        if in_sea:
            t = (y - horizon_y) / max(1.0, (HEIGHT - horizon_y))
            base_row = lerp_rgb(sea_horizon, sea_near, t)
        else:
            t = y / max(1.0, horizon_y)
            base_row = lerp_rgb(sky_top, sky_horizon, t)

        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            r, g, b = base_row

            # Sun / moon disc + glow
            if sun:
                d = math.hypot(x - sun_cx, y - sun_cy)
                if d < sun_r:
                    edge = 1.0 - (d / sun_r) ** 2
                    r, g, b = lerp_rgb((r, g, b), sun[3], min(1.0, 0.55 + 0.45 * edge))
                else:
                    # Soft, contained halo — the live shader adds the bright,
                    # beat-pulsing glow on top, so keep the baked one restrained.
                    glow = max(0.0, 1.0 - (d - sun_r) / (sun_r * 1.8))
                    if glow > 0:
                        gc = sun[4]
                        r += (gc[0]) * glow * 0.3
                        g += (gc[1]) * glow * 0.3
                        b += (gc[2]) * glow * 0.3

            # Sea sparkle + sun reflection column
            if in_sea:
                band = 0.5 + 0.5 * math.sin(y * 0.25 + math.sin(x * 0.01) * 2.0)
                shimmer = band * (0.10 + 0.10 * (1.0 - t))
                if sun and abs(x - sun_cx) < sun_r * (1.0 + t * 3.0):
                    refl = (1.0 - abs(x - sun_cx) / (sun_r * (1.0 + t * 3.0)))
                    refl *= (0.5 + 0.5 * math.sin(y * 0.6 + x * 0.05))
                    shimmer += refl * 0.6
                r += sun[3][0] * shimmer * 0.3 if sun else 0
                g += sun[3][1] * shimmer * 0.3 if sun else 0
                b += sun[3][2] * shimmer * 0.3 if sun else 0

            # Horizon neon rim
            if neon > 0 and abs(y - horizon_y) < HEIGHT * 0.012:
                glowline = 1.0 - abs(y - horizon_y) / (HEIGHT * 0.012)
                r += 255 * neon * glowline * 0.6
                g += 80 * neon * glowline * 0.6
                b += 220 * neon * glowline * 0.6

            # (No stained-glass facets — the view through the window is a clean
            # beach scene; the sun pulse and rolling waves are added live by the
            # effects shader.)

            # Palm silhouette
            if palm_mask[y][x]:
                r, g, b = lerp_rgb((r, g, b), (10, 12, 22), 0.9)

            pixels[idx] = clamp8(r)
            pixels[idx + 1] = clamp8(g)
            pixels[idx + 2] = clamp8(b)
            pixels[idx + 3] = 255

    # Stars (stamped after, upper sky region)
    star_count = int(cfg.get("stars", 0) * (WIDTH * HEIGHT) / (1920 * 1080))
    for _ in range(star_count):
        sx = rng.randint(0, WIDTH - 1)
        sy = rng.randint(0, int(horizon_y * 0.9))
        bright = rng.uniform(0.5, 1.0)
        col = cfg.get("star_color", (255, 255, 235))
        for ox, oy, f in [(0, 0, 1.0), (1, 0, 0.4), (-1, 0, 0.4), (0, 1, 0.4), (0, -1, 0.4)]:
            px, py = sx + ox, sy + oy
            if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                i = (py * WIDTH + px) * 4
                pixels[i] = clamp8(pixels[i] + col[0] * bright * f)
                pixels[i + 1] = clamp8(pixels[i + 1] + col[1] * bright * f)
                pixels[i + 2] = clamp8(pixels[i + 2] + col[2] * bright * f)

    # Frame the beach as the view through an arched resort window (drawn last,
    # on top of the scene + stars).
    draw_resort_window(pixels)

    path = os.path.join(OUTPUT_DIR, f"{name}.png")
    data = make_png(WIDTH, HEIGHT, pixels)
    with open(path, 'wb') as f:
        f.write(data)
    print(f"  saved {name}.png ({len(data) / 1024:.0f} KB)")


PANELS = {
    "panel-beach-sunset": {
        "horizon": 0.62,
        "sky_top": (250, 150, 70), "sky_horizon": (255, 110, 90),
        "sea_horizon": (240, 120, 80), "sea_near": (120, 50, 90),
        "sun": (0.5, 0.5, 0.16, (255, 240, 200), (255, 170, 90)),
        "palms": False, "stars": 0, "glass_grid": 160, "seed": 1,
    },
    "panel-beach-goldenhour": {
        "horizon": 0.6,
        "sky_top": (255, 200, 90), "sky_horizon": (255, 160, 110),
        "sea_horizon": (230, 150, 100), "sea_near": (150, 90, 110),
        "sun": (0.5, 0.5, 0.12, (255, 245, 210), (255, 200, 120)),
        "palms": True, "stars": 0, "glass_grid": 150, "seed": 2,
    },
    "panel-beach-dusk": {
        "horizon": 0.58,
        "sky_top": (40, 50, 130), "sky_horizon": (220, 90, 150),
        "sea_horizon": (150, 70, 140), "sea_near": (30, 50, 110),
        "sun": (0.5, 0.5, 0.10, (255, 210, 180), (230, 110, 150)),
        "palms": True, "stars": 60, "glass_grid": 145,
        "star_color": (255, 240, 220), "seed": 3,
    },
    "panel-beach-neonnight": {
        "horizon": 0.56,
        "sky_top": (10, 10, 45), "sky_horizon": (120, 30, 130),
        "sea_horizon": (60, 20, 110), "sea_near": (10, 15, 60),
        "sun": (0.5, 0.5, 0.09, (220, 250, 255), (90, 200, 255)),
        "palms": True, "stars": 150, "neon": 0.7, "glass_grid": 140,
        "star_color": (180, 240, 255), "seed": 4,
    },
    "panel-beach-midnight": {
        "horizon": 0.55,
        "sky_top": (4, 6, 30), "sky_horizon": (40, 20, 90),
        "sea_horizon": (30, 25, 95), "sea_near": (5, 10, 45),
        "sun": (0.5, 0.5, 0.08, (235, 250, 255), (120, 210, 255)),
        "palms": True, "stars": 320, "neon": 1.0, "glass_grid": 135,
        "star_color": (200, 245, 255), "seed": 5,
    },
}


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Generating beach stained glass panels into {OUTPUT_DIR}")
    for name, cfg in PANELS.items():
        generate_beach_panel(name, cfg)
    print("Done!")
