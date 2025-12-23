#!/usr/bin/env python3
"""OKLCH L=0.65 with boosted chroma, no integer indexing."""

from PIL import Image
import math

def oklab_to_linear_srgb(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l = l_ ** 3
    m = m_ ** 3
    s = s_ ** 3
    r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return r, g, b

def linear_to_srgb(x):
    if x <= 0.0031308:
        return 12.92 * x
    return 1.055 * (x ** (1/2.4)) - 0.055

def oklch_to_srgb(L, C, h_rad):
    """OKLCH to sRGB. h_rad is in radians. Clamps to gamut."""
    a = C * math.cos(h_rad)
    b = C * math.sin(h_rad)
    r, g, b = oklab_to_linear_srgb(L, a, b)
    r = max(0, min(1, linear_to_srgb(r)))
    g = max(0, min(1, linear_to_srgb(g)))
    b = max(0, min(1, linear_to_srgb(b)))
    return int(r * 255), int(g * 255), int(b * 255)

def generate_wheel(size, filename, target_L, max_C):
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
                h_rad = math.atan2(dy, dx)  # Keep as radians, no conversion
                t = dist / radius

                # Interpolate L from 1.0 (white) to target_L
                L = 1.0 - t * (1.0 - target_L)
                # Interpolate C from 0 to max_C
                C = t * max_C

                r, g, b = oklch_to_srgb(L, C, h_rad)
                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"Saved {filename} (L={target_L}, C={max_C})")

# L=0.65 with various chroma levels
generate_wheel(400, 'oklch_L65_C20.png', 0.65, 0.20)
generate_wheel(400, 'oklch_L65_C25.png', 0.65, 0.25)
generate_wheel(400, 'oklch_L65_C30.png', 0.65, 0.30)
generate_wheel(400, 'oklch_L65_C35.png', 0.65, 0.35)

# Also try L=0.60 for slightly darker but more saturated
generate_wheel(400, 'oklch_L60_C30.png', 0.60, 0.30)
generate_wheel(400, 'oklch_L60_C35.png', 0.60, 0.35)
