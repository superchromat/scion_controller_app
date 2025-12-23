#!/usr/bin/env python3
"""Reverse-engineer Apple's color wheel formula by analyzing pixel patterns."""

from PIL import Image
import math
import colorsys

img = Image.open('apple_wheel.png').convert('RGB')
width, height = img.size
cx, cy = width // 2, height // 2
radius = min(width, height) // 2 - 10

print("Analyzing Apple's color wheel to find the formula...")
print("="*70)

# Sample at multiple radii along key angles
print("\nRadial samples - checking how color changes from center to edge:")
print("\nAt 0° (red direction):")
print("Radius%\tRGB\t\t\tNormalized (r-w)")

for r_pct in [0, 25, 50, 75, 100]:
    x = int(cx + radius * (r_pct/100))
    y = cy
    r, g, b = img.getpixel((x, y))

    # Normalize relative to white (255,255,255)
    nr = (r - 255) / 255 if r_pct > 0 else 0
    ng = (g - 255) / 255 if r_pct > 0 else 0
    nb = (b - 255) / 255 if r_pct > 0 else 0

    print(f"{r_pct}%\t({r:3d},{g:3d},{b:3d})\t({nr:+.3f}, {ng:+.3f}, {nb:+.3f})")

# Check if it's linear interpolation from white to edge color
print("\n\nChecking if linear interpolation from white to edge:")
print("At 0° - if linear: RGB = (255,255,255) + t * (edge - white)")

# Get edge color at 0°
edge_r, edge_g, edge_b = img.getpixel((int(cx + radius * 0.95), cy))
print(f"Edge color at 95%: ({edge_r}, {edge_g}, {edge_b})")

for r_pct in [25, 50, 75]:
    t = r_pct / 95.0  # normalize to edge at 95%
    expected_r = int(255 + t * (edge_r - 255))
    expected_g = int(255 + t * (edge_g - 255))
    expected_b = int(255 + t * (edge_b - 255))

    x = int(cx + radius * (r_pct/100))
    actual_r, actual_g, actual_b = img.getpixel((x, cy))

    dr = actual_r - expected_r
    dg = actual_g - expected_g
    db = actual_b - expected_b

    print(f"{r_pct}%: expected ({expected_r},{expected_g},{expected_b}) "
          f"actual ({actual_r},{actual_g},{actual_b}) "
          f"diff ({dr:+d},{dg:+d},{db:+d})")

# Now check the hue function - is it standard HSV or something else?
print("\n\nAnalyzing hue function at 90% radius:")
print("Angle\tRGB\t\t\tHue(HSV)\tExpected")

for angle_deg in range(0, 360, 15):
    angle_rad = math.radians(angle_deg)
    x = int(cx + radius * 0.9 * math.cos(angle_rad))
    y = int(cy + radius * 0.9 * math.sin(angle_rad))
    r, g, b = img.getpixel((x, y))

    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    measured_hue = h * 360

    # Apple's 0° is at the right (standard math convention)
    # But their hue might be rotated
    print(f"{angle_deg:3d}°\t({r:3d},{g:3d},{b:3d})\t{measured_hue:5.1f}°")

# Check the relationship between angle and measured hue
print("\n\nAngle vs Measured Hue (checking for rotation/offset):")
hue_offsets = []
for angle_deg in range(0, 360, 30):
    angle_rad = math.radians(angle_deg)
    x = int(cx + radius * 0.9 * math.cos(angle_rad))
    y = int(cy + radius * 0.9 * math.sin(angle_rad))
    r, g, b = img.getpixel((x, y))
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    measured_hue = h * 360

    # The offset between position angle and color hue
    offset = (measured_hue - angle_deg) % 360
    if offset > 180:
        offset -= 360
    hue_offsets.append(offset)
    print(f"Position {angle_deg:3d}° → Hue {measured_hue:5.1f}° (offset: {offset:+.1f}°)")

print(f"\nAverage hue offset: {sum(hue_offsets)/len(hue_offsets):.1f}°")
