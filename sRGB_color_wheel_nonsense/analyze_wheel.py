#!/usr/bin/env python3
"""Compare Apple vs Flutter color wheels."""

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

    # Sample at edge
    print("\n--- EDGE COLORS (full saturation) ---")
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

    return edge_data, img, center_x, center_y, radius

# Analyze both
apple_data, apple_img, ax, ay, ar = analyze_wheel('/Users/joshreich/superchromat/scion_controller_app/apple_wheel.png', 'APPLE')
flutter_data, flutter_img, fx, fy, fr = analyze_wheel('/Users/joshreich/superchromat/scion_controller_app/bandy_shit.png', 'FLUTTER')

print(f"\n{'='*60}")
print("COMPARISON - EDGE COLORS")
print(f"{'='*60}")
print("\nAngle\tApple RGB\t\tFlutter RGB\t\tDiff")
for a, f in zip(apple_data, flutter_data):
    angle = a[0]
    ar_c, ag, ab = a[1], a[2], a[3]
    fr_c, fg, fb = f[1], f[2], f[3]
    dr, dg, db = fr_c-ar_c, fg-ag, fb-ab
    print(f"{angle}°\t({ar_c:3d},{ag:3d},{ab:3d})\t({fr_c:3d},{fg:3d},{fb:3d})\t({dr:+4d},{dg:+4d},{db:+4d})")

# Radial comparison at multiple angles
print(f"\n{'='*60}")
print("RADIAL COMPARISON")
print(f"{'='*60}")

for test_angle in [0, 60, 120, 180, 240, 300]:
    print(f"\n--- Angle {test_angle}° ---")
    print("Radius%\tApple\t\t\tFlutter\t\t\tDiff")

    angle_rad = math.radians(test_angle)
    for r_pct in [20, 40, 60, 80, 95]:
        # Apple
        if r_pct == 0:
            ax_s, ay_s = ax, ay
        else:
            ax_s = int(ax + ar * (r_pct/100) * math.cos(angle_rad))
            ay_s = int(ay + ar * (r_pct/100) * math.sin(angle_rad))
        ar_c, ag_c, ab_c = apple_img.getpixel((ax_s, ay_s))

        # Flutter
        if r_pct == 0:
            fx_s, fy_s = fx, fy
        else:
            fx_s = int(fx + fr * (r_pct/100) * math.cos(angle_rad))
            fy_s = int(fy + fr * (r_pct/100) * math.sin(angle_rad))
        fr_c, fg_c, fb_c = flutter_img.getpixel((fx_s, fy_s))

        dr, dg, db = fr_c-ar_c, fg_c-ag_c, fb_c-ab_c
        print(f"{r_pct}%\t({ar_c:3d},{ag_c:3d},{ab_c:3d})\t({fr_c:3d},{fg_c:3d},{fb_c:3d})\t({dr:+4d},{dg:+4d},{db:+4d})")
