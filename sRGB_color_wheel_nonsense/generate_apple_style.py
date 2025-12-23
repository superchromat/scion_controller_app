#!/usr/bin/env python3
"""Generate wheel matching Apple's approach: linear RGB interp, clockwise hue."""

from PIL import Image
import math
import colorsys

def hsv_to_rgb(h, s, v):
    """Standard HSV to RGB."""
    r, g, b = colorsys.hsv_to_rgb(h / 360.0, s, v)
    return int(r * 255), int(g * 255), int(b * 255)

def generate_apple_style(size, filename):
    """Apple style: clockwise hue, linear RGB interpolation."""
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
                angle = math.atan2(dy, dx)
                angle_deg = math.degrees(angle)

                # Apple uses CLOCKWISE hue (negative direction)
                hue = (-angle_deg + 360) % 360

                t = dist / radius  # 0 at center, 1 at edge

                # Get the pure saturated color for this hue
                edge_r, edge_g, edge_b = hsv_to_rgb(hue, 1.0, 1.0)

                # Linear RGB interpolation from white to edge
                r = int(255 + t * (edge_r - 255))
                g = int(255 + t * (edge_g - 255))
                b = int(255 + t * (edge_b - 255))

                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"Saved {filename}")

generate_apple_style(400, 'wheel_apple_style.png')

# Also generate our current OKLCH for comparison
def oklch_to_rgb(L, C, h_rad):
    """OKLCH to sRGB."""
    a = C * math.cos(h_rad)
    b = C * math.sin(h_rad)

    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b

    l = l_ ** 3
    m = m_ ** 3
    s = s_ ** 3

    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    def linear_to_srgb(x):
        if x <= 0.0031308:
            return 12.92 * x
        return 1.055 * (x ** (1/2.4)) - 0.055

    r = max(0, min(255, int(linear_to_srgb(r) * 255)))
    g = max(0, min(255, int(linear_to_srgb(g) * 255)))
    bl = max(0, min(255, int(linear_to_srgb(bl) * 255)))

    return r, g, bl

def generate_oklch(size, filename, target_L, max_C):
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
                h_rad = math.atan2(dy, dx)
                t = dist / radius

                L = 1.0 - t * (1.0 - target_L)
                C = t * max_C

                r, g, b = oklch_to_rgb(L, C, h_rad)
                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"Saved {filename}")

generate_oklch(400, 'wheel_oklch_L60_C30_fresh.png', 0.60, 0.30)

print("\nCompare wheel_apple_style.png with apple_wheel.png")
print("If they match, the difference you see is Display P3 vs sRGB")
