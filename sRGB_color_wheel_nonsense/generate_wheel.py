#!/usr/bin/env python3
"""Generate HSV color wheel as PNG - no Flutter involved."""

from PIL import Image
import math

def hsv_to_rgb(h, s, v):
    """Standard HSV to RGB. H in [0,360), S,V in [0,1]. Returns (R,G,B) in [0,255]."""
    c = v * s
    h_prime = h / 60.0
    x = c * (1 - abs((h_prime % 2) - 1))
    m = v - c

    if h_prime < 1:
        r, g, b = c, x, 0
    elif h_prime < 2:
        r, g, b = x, c, 0
    elif h_prime < 3:
        r, g, b = 0, c, x
    elif h_prime < 4:
        r, g, b = 0, x, c
    elif h_prime < 5:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x

    return (
        int((r + m) * 255),
        int((g + m) * 255),
        int((b + m) * 255)
    )

def generate_wheel(size, filename):
    """Generate HSV color wheel: white center, saturated edge."""
    img = Image.new('RGB', (size, size), (0, 0, 0))
    pixels = img.load()

    center = size / 2.0
    radius = center

    for y in range(size):
        for x in range(size):
            dx = x - center + 0.5
            dy = y - center + 0.5
            dist = math.sqrt(dx*dx + dy*dy)

            if dist <= radius:
                angle = math.atan2(dy, dx)
                hue = (math.degrees(angle) + 360) % 360
                sat = min(dist / radius, 1.0)

                # HSV: H=hue, S=sat, V=1.0
                r, g, b = hsv_to_rgb(hue, sat, 1.0)
                pixels[x, y] = (r, g, b)
            else:
                pixels[x, y] = (0, 0, 0)

    img.save(filename)
    print(f"Saved {filename} ({size}x{size})")
    return img

if __name__ == '__main__':
    # Generate at same size as Flutter wheel (90px diameter = 180px image)
    generate_wheel(180, 'python_wheel.png')

    # Also generate larger version for comparison
    generate_wheel(400, 'python_wheel_large.png')
