#!/usr/bin/env python3
"""Simplest possible HSV wheel - no lookups, no corrections, just math."""

from PIL import Image
import math

def hsv_to_rgb(h, s, v):
    """Pure HSV to RGB. h in [0,360), s,v in [0,1]."""
    c = v * s
    x = c * (1.0 - abs((h / 60.0) % 2.0 - 1.0))
    m = v - c

    if h < 60:
        r, g, b = c, x, 0
    elif h < 120:
        r, g, b = x, c, 0
    elif h < 180:
        r, g, b = 0, c, x
    elif h < 240:
        r, g, b = 0, x, c
    elif h < 300:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x

    return (
        int((r + m) * 255),
        int((g + m) * 255),
        int((b + m) * 255)
    )

size = 400
img = Image.new('RGB', (size, size), (0, 0, 0))
pixels = img.load()

center = size / 2.0
radius = center - 2

for y in range(size):
    for x in range(size):
        dx = x - center + 0.5
        dy = y - center + 0.5
        dist = math.sqrt(dx * dx + dy * dy)

        if dist <= radius:
            hue = (math.degrees(math.atan2(dy, dx)) + 360) % 360
            sat = dist / radius

            r, g, b = hsv_to_rgb(hue, sat, 1.0)
            pixels[x, y] = (r, g, b)

img.save('wheel_simple_hsv.png')
print("Saved wheel_simple_hsv.png")
print("\nThis is the simplest possible HSV wheel.")
print("If this has banding, it's inherent to HSV.")
print("If this looks good, Flutter's rendering is the problem.")
