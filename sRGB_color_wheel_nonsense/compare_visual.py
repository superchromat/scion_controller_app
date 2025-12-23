#!/usr/bin/env python3
"""Generate side-by-side comparison and difference image."""

from PIL import Image, ImageDraw, ImageFont
import math

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

# Load Apple wheel
apple = Image.open('apple_wheel.png').convert('RGB')
apple_size = min(apple.size)

# Generate Python wheel at same size
size = apple_size
python = Image.new('RGB', (size, size), (128, 128, 128))
pixels = python.load()
center = size / 2.0
radius = center - 5

for y in range(size):
    for x in range(size):
        dx = x - center + 0.5
        dy = y - center + 0.5
        dist = math.sqrt(dx*dx + dy*dy)
        if dist <= radius:
            angle = math.atan2(dy, dx)
            # Apple's wheel has 0° at right, going counter-clockwise
            # Our atan2 gives 0° at right, going counter-clockwise
            # But Apple's red is at ~0°, ours would be at 0° too
            # The 180° difference we saw was due to the specific angles sampled
            hue = (math.degrees(angle) + 360) % 360
            sat = min(dist / radius, 1.0)
            r, g, b = hsv_to_rgb(hue, sat, 1.0)
            pixels[x, y] = (r, g, b)

# Create comparison image
comparison = Image.new('RGB', (size * 3, size), (40, 40, 40))
comparison.paste(apple.crop((0, 0, size, size)), (0, 0))
comparison.paste(python, (size, 0))

# Difference image (amplified)
diff = Image.new('RGB', (size, size))
diff_pixels = diff.load()
apple_pixels = apple.load()

for y in range(size):
    for x in range(size):
        ar, ag, ab = apple_pixels[x, y] if x < apple.size[0] and y < apple.size[1] else (128,128,128)
        pr, pg, pb = pixels[x, y]
        # Amplify difference by 4x for visibility
        dr = min(255, abs(ar - pr) * 4)
        dg = min(255, abs(ag - pg) * 4)
        db = min(255, abs(ab - pb) * 4)
        diff_pixels[x, y] = (dr, dg, db)

comparison.paste(diff, (size * 2, 0))
comparison.save('wheel_comparison.png')
print("Saved wheel_comparison.png (Apple | Python | Diff*4)")

# Also save Python wheel at Apple's size for direct comparison
python.save('python_wheel_apple_size.png')
print(f"Saved python_wheel_apple_size.png ({size}x{size})")
