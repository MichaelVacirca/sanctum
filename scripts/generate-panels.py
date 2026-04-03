#!/usr/bin/env python3
"""Generate stained glass panel textures (1920x1080) with no text.

Each panel is a full-screen stained glass pattern with visible lead lines,
jewel-toned glass, and a backlit glow effect.
"""

import struct
import zlib
import math
import os
import random

OUTPUT_DIR = "/Users/mvacirca/dev/sanctum/Assets/panels"
WIDTH, HEIGHT = 1920, 1080


def make_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = b''
    for y in range(height):
        raw += b'\x00'
        row_start = y * width * 4
        raw += bytes(pixels[row_start:row_start + width * 4])

    idat = chunk(b'IDAT', zlib.compress(raw, 6))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend


def hash2d(x, y):
    """Deterministic 2D hash for Voronoi."""
    n = math.sin(x * 127.1 + y * 311.7) * 43758.5453
    return n - math.floor(n)


def voronoi_cell(px, py, grid_size):
    """Return (min_dist, second_dist, cell_id) for Voronoi at point."""
    gx = int(px / grid_size)
    gy = int(py / grid_size)
    min_d = 999.0
    second_d = 999.0
    cell_id = 0

    for dy in range(-1, 2):
        for dx in range(-1, 2):
            cx = gx + dx
            cy = gy + dy
            # Cell center with jitter
            jx = cx * grid_size + hash2d(cx, cy) * grid_size * 0.8 + grid_size * 0.1
            jy = cy * grid_size + hash2d(cy + 100, cx + 200) * grid_size * 0.8 + grid_size * 0.1
            d = math.sqrt((px - jx) ** 2 + (py - jy) ** 2)
            if d < min_d:
                second_d = min_d
                min_d = d
                cell_id = (cx * 7919 + cy * 104729) % 256
            elif d < second_d:
                second_d = d

    return min_d, second_d, cell_id


def glass_tint(base_r, base_g, base_b, x, y):
    noise = math.sin(x * 0.02) * math.cos(y * 0.03) * 15
    grain = math.sin(x * 0.15 + y * 0.12) * 5
    return (
        max(0, min(255, int(base_r + noise + grain))),
        max(0, min(255, int(base_g + noise * 0.7 + grain))),
        max(0, min(255, int(base_b + noise * 0.5 + grain)))
    )


def generate_sacred_blue():
    """Deep blue/gold rose window pattern — sacred phase."""
    pixels = [0] * (WIDTH * HEIGHT * 4)
    cx, cy = WIDTH // 2, HEIGHT // 2
    colors = [
        (15, 30, 140), (20, 25, 120), (30, 20, 160),
        (140, 110, 20), (25, 40, 130), (160, 30, 40),
        (20, 35, 150), (130, 100, 15),
    ]

    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            dx, dy = x - cx, y - cy
            d = math.sqrt(dx*dx + dy*dy)
            angle = math.atan2(dy, dx)

            # Voronoi glass segments
            _, second_d, cell_id = voronoi_cell(x, y, 80)
            min_d_edge = second_d - _

            # Lead lines from Voronoi edges
            lead = 1.0
            if min_d_edge < 4:
                lead = 0.12
            elif min_d_edge < 6:
                lead = 0.3

            # Radial structure lines
            for i in range(12):
                spoke = i * math.pi / 6
                diff = abs(((angle - spoke + math.pi) % (2*math.pi)) - math.pi)
                if diff * d < 3:
                    lead = min(lead, 0.15)

            # Concentric rings
            for r in range(100, int(max(WIDTH, HEIGHT)), 120):
                if abs(d - r) < 2.5:
                    lead = min(lead, 0.15)

            color = colors[cell_id % len(colors)]
            r, g, b = glass_tint(*color, x, y)

            # Backlight glow from center
            glow = 0.6 + 0.4 * max(0, 1.0 - d / 600)
            r = int(min(255, r * lead * glow))
            g = int(min(255, g * lead * glow))
            b = int(min(255, b * lead * glow))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_ruby_red():
    """Ruby red and gold — warm sacred panel."""
    pixels = [0] * (WIDTH * HEIGHT * 4)
    colors = [
        (160, 25, 25), (180, 30, 20), (140, 15, 30),
        (200, 160, 30), (170, 20, 35), (190, 140, 20),
        (150, 25, 40), (210, 170, 25),
    ]

    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            _, second_d, cell_id = voronoi_cell(x, y, 100)
            min_d_edge = second_d - _

            lead = 1.0
            if min_d_edge < 5:
                lead = 0.12
            elif min_d_edge < 7:
                lead = 0.35

            color = colors[cell_id % len(colors)]
            r, g, b = glass_tint(*color, x, y)

            # Subtle vertical gradient (lighter at top = backlit)
            vert_glow = 0.7 + 0.3 * (1.0 - y / HEIGHT)
            r = int(min(255, r * lead * vert_glow))
            g = int(min(255, g * lead * vert_glow))
            b = int(min(255, b * lead * vert_glow))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_emerald_purple():
    """Emerald and amethyst — lancet window style."""
    pixels = [0] * (WIDTH * HEIGHT * 4)
    colors = [
        (20, 130, 50), (25, 110, 60), (15, 140, 40),
        (120, 20, 130), (130, 25, 120), (100, 15, 140),
        (25, 120, 55), (110, 20, 125),
    ]

    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            _, second_d, cell_id = voronoi_cell(x, y, 90)
            min_d_edge = second_d - _

            lead = 1.0
            if min_d_edge < 4:
                lead = 0.12
            elif min_d_edge < 6:
                lead = 0.3

            # Gothic arch pattern — vertical emphasis
            arch_x = abs(x - WIDTH // 2) / (WIDTH // 2)
            arch_curve = arch_x ** 2
            if y < HEIGHT * 0.15:
                if abs(y / HEIGHT - arch_curve * 0.15) < 0.008:
                    lead = 0.12

            color = colors[cell_id % len(colors)]
            r, g, b = glass_tint(*color, x, y)

            glow = 0.65 + 0.35 * (1.0 - y / HEIGHT)
            r = int(min(255, r * lead * glow))
            g = int(min(255, g * lead * glow))
            b = int(min(255, b * lead * glow))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_corrupted():
    """Dark, cracked, corrupted stained glass — profane/abyss phase."""
    pixels = [0] * (WIDTH * HEIGHT * 4)
    colors = [
        (80, 15, 80), (60, 10, 70), (40, 60, 20),
        (90, 20, 30), (50, 70, 15), (70, 10, 90),
        (100, 25, 25), (30, 50, 25),
    ]

    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            _, second_d, cell_id = voronoi_cell(x, y, 60)  # smaller = more fragmented
            min_d_edge = second_d - _

            lead = 1.0
            if min_d_edge < 5:
                lead = 0.08  # darker lead — more oppressive
            elif min_d_edge < 8:
                lead = 0.2

            # Extra crack lines
            crack1 = math.sin(x * 0.05 + y * 0.03) * math.cos(x * 0.02 - y * 0.04)
            if abs(crack1) < 0.02:
                lead = min(lead, 0.1)

            color = colors[cell_id % len(colors)]
            r, g, b = glass_tint(*color, x, y)

            # Dark, oppressive — minimal backlight
            darkness = 0.4 + 0.2 * hash2d(x * 0.01, y * 0.01)
            r = int(min(255, r * lead * darkness))
            g = int(min(255, g * lead * darkness))
            b = int(min(255, b * lead * darkness))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_golden_amber():
    """Warm golden amber — candlelit cathedral."""
    pixels = [0] * (WIDTH * HEIGHT * 4)
    colors = [
        (210, 170, 30), (190, 150, 25), (220, 180, 35),
        (180, 130, 20), (200, 160, 28), (230, 190, 40),
        (170, 120, 18), (215, 175, 32),
    ]

    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            _, second_d, cell_id = voronoi_cell(x, y, 110)
            min_d_edge = second_d - _

            lead = 1.0
            if min_d_edge < 4:
                lead = 0.12
            elif min_d_edge < 6:
                lead = 0.35

            color = colors[cell_id % len(colors)]
            r, g, b = glass_tint(*color, x, y)

            # Warm candlelight from center-bottom
            cx_d = abs(x - WIDTH // 2) / (WIDTH // 2)
            cy_d = (HEIGHT - y) / HEIGHT
            warmth = 0.5 + 0.5 * max(0, 1.0 - math.sqrt(cx_d**2 + (1-cy_d)**2))
            r = int(min(255, r * lead * warmth))
            g = int(min(255, g * lead * warmth))
            b = int(min(255, b * lead * warmth))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_fire():
    """Crimson and orange flames — intense energy panel."""
    pixels = [0] * (WIDTH * HEIGHT * 4)
    colors = [
        (200, 40, 10), (220, 80, 10), (180, 30, 15),
        (240, 120, 15), (190, 50, 12), (210, 90, 10),
        (230, 100, 12), (170, 35, 18),
    ]

    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = (y * WIDTH + x) * 4
            _, second_d, cell_id = voronoi_cell(x, y, 70)
            min_d_edge = second_d - _

            lead = 1.0
            if min_d_edge < 4:
                lead = 0.1
            elif min_d_edge < 6:
                lead = 0.25

            color = colors[cell_id % len(colors)]
            r, g, b = glass_tint(*color, x, y)

            # Fire rises — brighter at bottom
            fire_glow = 0.4 + 0.6 * (y / HEIGHT)
            # Flame flicker
            flicker = 0.9 + 0.1 * math.sin(x * 0.08 + y * 0.05)
            r = int(min(255, r * lead * fire_glow * flicker))
            g = int(min(255, g * lead * fire_glow * flicker))
            b = int(min(255, b * lead * fire_glow * flicker))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def save_panel(name, pixels):
    path = os.path.join(OUTPUT_DIR, f"{name}.png")
    data = make_png(WIDTH, HEIGHT, pixels)
    with open(path, 'wb') as f:
        f.write(data)
    size_kb = len(data) / 1024
    print(f"  {name}.png ({size_kb:.0f} KB)")


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Generating stained glass panels (1920x1080)...")
    print("This takes a minute per panel...")

    save_panel("panel-sacred-blue", generate_sacred_blue())
    save_panel("panel-ruby-red", generate_ruby_red())
    save_panel("panel-emerald-purple", generate_emerald_purple())
    save_panel("panel-corrupted", generate_corrupted())
    save_panel("panel-golden-amber", generate_golden_amber())
    save_panel("panel-fire", generate_fire())
    print("Done!")
