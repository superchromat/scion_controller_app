#!/usr/bin/env python3
"""Check if Apple compensates for primary vs secondary brightness."""

from PIL import Image
import math

def get_total_brightness(r, g, b):
    """Simple sum - how much light is being emitted."""
    return r + g + b

def get_luminance(r, g, b):
    """Perceptual luminance."""
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

img = Image.open('apple_wheel.png').convert('RGB')
width, height = img.size
cx, cy = width // 2, height // 2
radius = min(width, height) // 2 - 10

print("Apple wheel - Primary vs Secondary colors at 90% radius")
print("="*70)
print("\nAngle\tColor\t\tRGB\t\t\tSum\tLuminance")

# Sample at 90% radius
for angle_deg in [0, 60, 120, 180, 240, 300]:
    angle_rad = math.radians(angle_deg)
    x = int(cx + radius * 0.9 * math.cos(angle_rad))
    y = int(cy + radius * 0.9 * math.sin(angle_rad))
    r, g, b = img.getpixel((x, y))

    # Determine color name based on which channels are high
    if r > 200 and g < 100 and b < 100: name = "RED"
    elif r > 200 and g > 200 and b < 100: name = "YELLOW"
    elif r < 100 and g > 200 and b < 100: name = "GREEN"
    elif r < 100 and g > 200 and b > 200: name = "CYAN"
    elif r < 100 and g < 100 and b > 200: name = "BLUE"
    elif r > 200 and g < 100 and b > 200: name = "MAGENTA"
    else: name = "?"

    total = get_total_brightness(r, g, b)
    lum = get_luminance(r, g, b)
    print(f"{angle_deg}°\t{name}\t\t({r:3d},{g:3d},{b:3d})\t{total}\t{lum:.1f}")

print("\n" + "="*70)
print("If Apple compensates, secondaries should have similar Sum to primaries.")
print("If no compensation, secondaries should have ~2x the Sum of primaries.")

# Now check what the THEORETICAL values would be
print("\n\nTheoretical HSV wheel at 90% saturation:")
print("Angle\tColor\t\tRGB\t\t\tSum\tLuminance")

def hsv_to_rgb(h, s, v):
    c = v * s
    h_prime = h / 60.0
    x = c * (1 - abs((h_prime % 2) - 1))
    m = v - c
    if h_prime < 1: r, g, b = c, x, 0
    elif h_prime < 2: r, g, b = x, c, 0
    elif h_prime < 3: r, g, b = 0, c, x
    elif h_prime < 4: r, g, b = 0, x, c
    elif h_prime < 5: r, g, b = x, 0, c
    else: r, g, b = c, 0, x
    return int((r+m)*255), int((g+m)*255), int((b+m)*255)

for angle_deg, name in [(0, "RED"), (60, "YELLOW"), (120, "GREEN"),
                         (180, "CYAN"), (240, "BLUE"), (300, "MAGENTA")]:
    r, g, b = hsv_to_rgb(angle_deg, 0.9, 1.0)
    total = get_total_brightness(r, g, b)
    lum = get_luminance(r, g, b)
    print(f"{angle_deg}°\t{name}\t\t({r:3d},{g:3d},{b:3d})\t{total}\t{lum:.1f}")
