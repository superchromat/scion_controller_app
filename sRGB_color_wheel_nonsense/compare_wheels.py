#!/usr/bin/env python3
"""Compare Apple vs Python-generated color wheels."""

from PIL import Image
import math
import colorsys

def analyze_wheel(path, name):
    print(f"\n{'='*60}")
    print(f"ANALYZING: {name}")
    print(f"{'='*60}")

    img = Image.open(path)
    img = img.convert('RGB')
    width, height = img.size
    print(f"Image size: {width}x{height}")

    center_x, center_y = width // 2, height // 2
    radius = min(width, height) // 2 - 5

    print(f"Center: ({center_x}, {center_y}), Radius: {radius}")

    # Sample at edge (85% radius for clean samples)
    print("\n--- EDGE COLORS (85% radius) ---")
    print("Angle\tRGB\t\t\tH\tS\tV\tLum")

    edge_data = []
    for angle_deg in range(0, 360, 30):
        angle_rad = math.radians(angle_deg)
        x = int(center_x + radius * 0.85 * math.cos(angle_rad))
        y = int(center_y + radius * 0.85 * math.sin(angle_rad))

        r, g, b = img.getpixel((x, y))
        h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
        lum = 0.2126 * (r/255) + 0.7152 * (g/255) + 0.0722 * (b/255)

        edge_data.append((angle_deg, r, g, b, h*360, s, v, lum))
        print(f"{angle_deg}°\t({r:3d},{g:3d},{b:3d})\t{h*360:5.1f}\t{s:.2f}\t{v:.2f}\t{lum:.3f}")

    return edge_data, img

# Analyze both
apple_data, apple_img = analyze_wheel('apple_wheel.png', 'APPLE')
python_data, python_img = analyze_wheel('python_wheel_large.png', 'PYTHON')

print(f"\n{'='*60}")
print("COMPARISON - EDGE COLORS")
print(f"{'='*60}")
print("\nAngle\tApple RGB\t\tPython RGB\t\tRGB Diff\t\tS Diff\tV Diff")
for a, p in zip(apple_data, python_data):
    angle = a[0]
    ar, ag, ab = a[1], a[2], a[3]
    pr, pg, pb = p[1], p[2], p[3]
    dr, dg, db = pr-ar, pg-ag, pb-ab
    ds = p[5] - a[5]  # saturation diff
    dv = p[6] - a[6]  # value diff
    print(f"{angle}°\t({ar:3d},{ag:3d},{ab:3d})\t({pr:3d},{pg:3d},{pb:3d})\t({dr:+4d},{dg:+4d},{db:+4d})\t{ds:+.2f}\t{dv:+.2f}")

# Summary stats
print(f"\n{'='*60}")
print("SUMMARY STATISTICS")
print(f"{'='*60}")

apple_s = [d[5] for d in apple_data]
apple_v = [d[6] for d in apple_data]
apple_lum = [d[7] for d in apple_data]

python_s = [d[5] for d in python_data]
python_v = [d[6] for d in python_data]
python_lum = [d[7] for d in python_data]

print(f"\nApple  - S: min={min(apple_s):.3f} max={max(apple_s):.3f} range={max(apple_s)-min(apple_s):.3f}")
print(f"Python - S: min={min(python_s):.3f} max={max(python_s):.3f} range={max(python_s)-min(python_s):.3f}")
print(f"\nApple  - V: min={min(apple_v):.3f} max={max(apple_v):.3f} range={max(apple_v)-min(apple_v):.3f}")
print(f"Python - V: min={min(python_v):.3f} max={max(python_v):.3f} range={max(python_v)-min(python_v):.3f}")
print(f"\nApple  - Lum: min={min(apple_lum):.3f} max={max(apple_lum):.3f} range={max(apple_lum)-min(apple_lum):.3f}")
print(f"Python - Lum: min={min(python_lum):.3f} max={max(python_lum):.3f} range={max(python_lum)-min(python_lum):.3f}")
