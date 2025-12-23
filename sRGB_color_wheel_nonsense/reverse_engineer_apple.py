#!/usr/bin/env python3
"""Reverse-engineer Apple's color wheel by sampling radially."""

from PIL import Image
import math
import colorsys

img = Image.open('apple_wheel.png').convert('RGB')
width, height = img.size
center_x, center_y = width // 2, height // 2
radius = min(width, height) // 2 - 5

print("Apple wheel - sampling along radial lines")
print("="*70)

# Sample at a few key hue angles
for angle_deg in [0, 30, 60, 90, 120, 180, 240, 300]:
    print(f"\n--- Angle {angle_deg}° ---")
    print("Radius%\tRGB\t\t\tH\tS\tV")

    angle_rad = math.radians(angle_deg)
    for r_pct in [0, 20, 40, 60, 80, 95]:
        if r_pct == 0:
            x, y = center_x, center_y
        else:
            x = int(center_x + radius * (r_pct/100) * math.cos(angle_rad))
            y = int(center_y + radius * (r_pct/100) * math.sin(angle_rad))

        r, g, b = img.getpixel((x, y))
        h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
        print(f"{r_pct}%\t({r:3d},{g:3d},{b:3d})\t{h*360:5.1f}\t{s:.3f}\t{v:.3f}")

# Check center color
print("\n\nCenter pixel:")
r, g, b = img.getpixel((center_x, center_y))
print(f"RGB: ({r}, {g}, {b})")

# Check if saturation is linear with radius
print("\n\nSaturation vs Radius (at 0° hue):")
print("Radius%\tExpected S\tActual S\tDiff")
for r_pct in [10, 20, 30, 40, 50, 60, 70, 80, 90]:
    x = int(center_x + radius * (r_pct/100))
    y = center_y
    r, g, b = img.getpixel((x, y))
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    expected_s = r_pct / 100
    print(f"{r_pct}%\t{expected_s:.2f}\t\t{s:.3f}\t\t{s - expected_s:+.3f}")
