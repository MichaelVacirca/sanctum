#!/usr/bin/env python3
"""Generate stained glass icon PNGs with transparent backgrounds.

Creates simple but recognizable religious iconography rendered in a stained glass style
with visible 'lead lines' and jewel-toned glass segments.
"""

import struct
import zlib
import math
import os

OUTPUT_DIR = "/Users/mvacirca/dev/sanctum/Assets/icons"
SIZE = 512  # 512x512 icons


def make_png(width, height, pixels):
    """Create a PNG file from RGBA pixel data."""
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter none
        for x in range(width):
            idx = (y * width + x) * 4
            raw += bytes(pixels[idx:idx+4])

    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend


def dist(x1, y1, x2, y2):
    return math.sqrt((x2-x1)**2 + (y2-y1)**2)


def lead_line(d, width=3):
    """Returns darkness factor for lead came lines."""
    if d < width:
        return 0.15  # dark lead
    elif d < width + 1.5:
        return 0.4  # edge shadow
    return 1.0


def glass_color(base_r, base_g, base_b, x, y):
    """Add glass texture variation to a base color."""
    # Subtle variation for glass texture
    noise = math.sin(x * 0.3) * math.cos(y * 0.4) * 0.08
    grain = math.sin(x * 2.1 + y * 1.7) * 0.03
    factor = 1.0 + noise + grain
    r = max(0, min(255, int(base_r * factor)))
    g = max(0, min(255, int(base_g * factor)))
    b = max(0, min(255, int(base_b * factor)))
    return r, g, b


def generate_cross():
    """Gothic cross with jewel-toned glass segments."""
    pixels = [0] * (SIZE * SIZE * 4)
    cx, cy = SIZE // 2, SIZE // 2
    arm_w = SIZE // 8  # cross arm half-width
    v_len = SIZE // 2 - 30  # vertical arm length from center
    h_len = SIZE // 3 - 10  # horizontal arm length

    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            rx, ry = x - cx, y - cy

            # Cross shape
            in_vertical = abs(rx) < arm_w and abs(ry) < v_len
            in_horizontal = abs(ry) < arm_w and abs(rx) < h_len and ry < arm_w * 2

            if not (in_vertical or in_horizontal):
                pixels[idx:idx+4] = [0, 0, 0, 0]  # transparent
                continue

            # Lead lines at cross edges
            d_to_edge = min(
                abs(abs(rx) - arm_w) if in_vertical else 999,
                abs(abs(ry) - arm_w) if in_horizontal else 999,
                abs(abs(rx) - h_len) if in_horizontal else 999,
                abs(abs(ry) - v_len) if in_vertical else 999,
            )
            lead = lead_line(d_to_edge, 4)

            # Internal lead lines dividing the cross into segments
            d_center_h = abs(rx) if in_vertical else 999
            d_center_v = abs(ry) if in_horizontal else 999
            d_cross_center = min(abs(rx), abs(ry))
            internal_lead = min(lead_line(d_center_h, 2), lead_line(d_center_v, 2))
            lead = min(lead, internal_lead)

            # Color segments
            if ry < -arm_w:  # top
                r, g, b = glass_color(180, 30, 30, x, y)  # ruby red
            elif ry > arm_w:  # bottom
                r, g, b = glass_color(120, 20, 120, x, y)  # purple
            elif rx < 0:  # left
                r, g, b = glass_color(20, 50, 160, x, y)  # blue
            else:  # right
                r, g, b = glass_color(20, 120, 50, x, y)  # green
            # Center jewel
            if dist(rx, ry, 0, 0) < arm_w * 0.7:
                r, g, b = glass_color(220, 180, 40, x, y)  # gold

            r = int(r * lead)
            g = int(g * lead)
            b = int(b * lead)
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_rose_circle():
    """Circular rose window pattern."""
    pixels = [0] * (SIZE * SIZE * 4)
    cx, cy = SIZE // 2, SIZE // 2
    radius = SIZE // 2 - 20
    inner_r = radius * 0.3
    mid_r = radius * 0.65

    colors = [
        (180, 30, 30),   # ruby
        (20, 50, 180),   # sapphire
        (160, 120, 20),  # gold
        (20, 140, 60),   # emerald
        (140, 20, 140),  # amethyst
        (180, 80, 20),   # amber
        (30, 100, 160),  # cerulean
        (160, 40, 60),   # crimson
    ]

    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            dx, dy = x - cx, y - cy
            d = dist(0, 0, dx, dy)

            if d > radius:
                pixels[idx:idx+4] = [0, 0, 0, 0]
                continue

            # Lead lines: outer rim, middle ring, inner ring
            lead = 1.0
            lead = min(lead, lead_line(abs(d - radius), 5))
            lead = min(lead, lead_line(abs(d - mid_r), 3))
            lead = min(lead, lead_line(abs(d - inner_r), 3))

            # Radial lead lines (8 spokes)
            angle = math.atan2(dy, dx)
            for i in range(8):
                spoke_angle = i * math.pi / 4
                angle_diff = abs(((angle - spoke_angle + math.pi) % (2 * math.pi)) - math.pi)
                spoke_dist = angle_diff * d
                lead = min(lead, lead_line(spoke_dist, 2))

            # Color by segment
            segment = int(((angle + math.pi) / (2 * math.pi)) * 8) % 8
            base = colors[segment]

            if d < inner_r:
                r, g, b = glass_color(220, 180, 40, x, y)  # gold center
            else:
                r, g, b = glass_color(*base, x, y)

            # Backlight glow effect
            glow = 0.7 + 0.3 * (1.0 - d / radius)
            r = int(min(255, r * glow * lead))
            g = int(min(255, g * glow * lead))
            b = int(min(255, b * glow * lead))
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_chalice():
    """Holy grail / chalice shape."""
    pixels = [0] * (SIZE * SIZE * 4)
    cx = SIZE // 2

    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            ny = y / SIZE  # normalized 0-1

            # Chalice profile
            if ny < 0.1 or ny > 0.92:
                pixels[idx:idx+4] = [0, 0, 0, 0]
                continue

            # Cup (top portion)
            if ny < 0.45:
                t = (ny - 0.1) / 0.35
                half_w = int(SIZE * (0.22 - 0.08 * t))  # widens toward top
            # Stem
            elif ny < 0.7:
                half_w = int(SIZE * 0.04)
            # Base
            else:
                t = (ny - 0.7) / 0.22
                half_w = int(SIZE * (0.04 + 0.14 * t))

            if abs(x - cx) > half_w:
                pixels[idx:idx+4] = [0, 0, 0, 0]
                continue

            # Lead lines at edges
            d_edge = half_w - abs(x - cx)
            lead = lead_line(d_edge, 4)

            # Horizontal lead divisions
            for div_y in [0.15, 0.25, 0.35, 0.45, 0.7, 0.82]:
                lead = min(lead, lead_line(abs(ny - div_y) * SIZE, 2))
            # Vertical center line
            lead = min(lead, lead_line(abs(x - cx), 2))

            # Colors by section
            if ny < 0.25:
                r, g, b = glass_color(180, 30, 30, x, y)  # ruby cup top
            elif ny < 0.45:
                r, g, b = glass_color(220, 170, 30, x, y)  # gold cup bottom
            elif ny < 0.7:
                r, g, b = glass_color(160, 130, 20, x, y)  # gold stem
            else:
                r, g, b = glass_color(20, 50, 160, x, y)   # blue base

            r = int(r * lead)
            g = int(g * lead)
            b = int(b * lead)
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_skull():
    """Corrupted skull icon."""
    pixels = [0] * (SIZE * SIZE * 4)
    cx, cy = SIZE // 2, SIZE // 2

    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            nx = (x - cx) / (SIZE / 2)
            ny = (y - cy) / (SIZE / 2)

            # Skull outline - oval
            skull_d = (nx * 1.1) ** 2 + (ny * 0.85 - 0.05) ** 2
            if skull_d > 0.65 or ny > 0.55:
                # Jaw
                if ny > 0.3 and ny < 0.7 and abs(nx) < 0.35 * (1.0 - (ny - 0.3) * 1.5):
                    pass  # in jaw
                else:
                    pixels[idx:idx+4] = [0, 0, 0, 0]
                    continue

            # Eye sockets
            left_eye = dist(nx, ny, -0.22, -0.1)
            right_eye = dist(nx, ny, 0.22, -0.1)
            if left_eye < 0.15 or right_eye < 0.15:
                # Dark void with sickly glow at edge
                eye_d = min(left_eye, right_eye)
                if eye_d < 0.1:
                    pixels[idx:idx+4] = [5, 2, 8, 255]
                else:
                    t = (eye_d - 0.1) / 0.05
                    r, g, b = glass_color(60, 180, 40, x, y)
                    pixels[idx:idx+4] = [int(r * t), int(g * t), int(b * t), 255]
                continue

            # Nose
            if dist(nx, ny, 0, 0.12) < 0.07:
                pixels[idx:idx+4] = [10, 5, 15, 255]
                continue

            # Lead cracks
            lead = 1.0
            crack1 = abs(nx + ny * 0.3 - 0.1)
            crack2 = abs(nx * 0.5 - ny + 0.2)
            lead = min(lead, lead_line(crack1 * SIZE, 2))
            lead = min(lead, lead_line(crack2 * SIZE, 2))
            # Outline lead
            lead = min(lead, lead_line(abs(math.sqrt(skull_d) - math.sqrt(0.65)) * SIZE * 0.5, 4))

            # Sickly corruption colors
            if ny < -0.1:
                r, g, b = glass_color(80, 20, 100, x, y)  # dark purple
            elif ny < 0.2:
                r, g, b = glass_color(40, 100, 30, x, y)   # sickly green
            else:
                r, g, b = glass_color(100, 30, 60, x, y)   # blood

            r = int(r * lead)
            g = int(g * lead)
            b = int(b * lead)
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_dove():
    """Peace dove with spread wings."""
    pixels = [0] * (SIZE * SIZE * 4)
    cx, cy = SIZE // 2, SIZE * 4 // 10

    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            nx = (x - cx) / (SIZE / 2)
            ny = (y - cy) / (SIZE / 2)

            in_shape = False

            # Body (oval)
            body_d = (nx * 2) ** 2 + (ny * 1.3) ** 2
            if body_d < 0.3:
                in_shape = True

            # Wings (swept back arcs)
            wing_y = ny + 0.05
            wing_spread = 0.8 - abs(wing_y) * 2
            if wing_spread > 0:
                if abs(nx) < wing_spread and abs(nx) > 0.15 and wing_y > -0.3 and wing_y < 0.2:
                    wing_thickness = 0.15 * (1.0 - abs(nx) / wing_spread)
                    if abs(wing_y - (-0.05 + abs(nx) * 0.3)) < wing_thickness:
                        in_shape = True

            # Tail (triangle going down-back)
            if ny > 0.1 and ny < 0.6 and abs(nx) < 0.12 * (1.0 - (ny - 0.1) / 0.5):
                in_shape = True

            if not in_shape:
                pixels[idx:idx+4] = [0, 0, 0, 0]
                continue

            # Lead lines
            lead = 1.0
            # Wing divisions
            for div in [-0.4, -0.2, 0.2, 0.4]:
                lead = min(lead, lead_line(abs(nx - div) * SIZE, 2))
            # Body outline vs wings
            lead = min(lead, lead_line(abs(body_d - 0.3) * SIZE * 0.3, 3))

            # Colors - white/pale blue/gold
            if body_d < 0.15:
                r, g, b = glass_color(230, 230, 240, x, y)  # white body
            elif body_d < 0.3:
                r, g, b = glass_color(200, 210, 240, x, y)  # pale blue
            else:
                r, g, b = glass_color(180, 200, 240, x, y)  # blue wings

            # Head highlight
            if dist(nx, ny, 0, -0.2) < 0.1:
                r, g, b = glass_color(240, 220, 180, x, y)  # gold head

            r = int(r * lead)
            g = int(g * lead)
            b = int(b * lead)
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def generate_halo():
    """Radiant golden halo/nimbus."""
    pixels = [0] * (SIZE * SIZE * 4)
    cx, cy = SIZE // 2, SIZE // 2
    outer_r = SIZE // 2 - 20
    inner_r = outer_r - SIZE // 6

    for y in range(SIZE):
        for x in range(SIZE):
            idx = (y * SIZE + x) * 4
            d = dist(x, y, cx, cy)

            if d > outer_r or d < inner_r:
                # Ray extensions beyond the ring
                angle = math.atan2(y - cy, x - cx)
                ray_match = False
                for i in range(12):
                    ray_angle = i * math.pi / 6
                    angle_diff = abs(((angle - ray_angle + math.pi) % (2 * math.pi)) - math.pi)
                    if angle_diff < 0.06 and d < outer_r + 30 and d > outer_r - 5:
                        ray_match = True
                if not ray_match:
                    pixels[idx:idx+4] = [0, 0, 0, 0]
                    continue

            # Lead lines
            lead = lead_line(abs(d - outer_r), 4)
            lead = min(lead, lead_line(abs(d - inner_r), 4))
            mid_r = (outer_r + inner_r) / 2
            lead = min(lead, lead_line(abs(d - mid_r), 2))

            # Radial leads (12 segments)
            angle = math.atan2(y - cy, x - cx)
            for i in range(12):
                spoke = i * math.pi / 6
                diff = abs(((angle - spoke + math.pi) % (2 * math.pi)) - math.pi)
                lead = min(lead, lead_line(diff * d, 2))

            # Gold/amber colors
            seg = int(((angle + math.pi) / (2 * math.pi)) * 12) % 12
            if seg % 2 == 0:
                r, g, b = glass_color(230, 190, 40, x, y)   # bright gold
            else:
                r, g, b = glass_color(200, 150, 20, x, y)   # darker gold

            r = int(r * lead)
            g = int(g * lead)
            b = int(b * lead)
            pixels[idx:idx+4] = [r, g, b, 255]

    return pixels


def save_icon(name, pixels):
    path = os.path.join(OUTPUT_DIR, f"{name}.png")
    data = make_png(SIZE, SIZE, pixels)
    with open(path, 'wb') as f:
        f.write(data)
    print(f"  {name}.png ({len(data)} bytes)")


if __name__ == "__main__":
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print("Generating stained glass icons...")
    save_icon("icon-cross", generate_cross())
    save_icon("icon-rose", generate_rose_circle())
    save_icon("icon-chalice", generate_chalice())
    save_icon("icon-skull", generate_skull())
    save_icon("icon-dove", generate_dove())
    save_icon("icon-halo", generate_halo())
    print("Done!")
