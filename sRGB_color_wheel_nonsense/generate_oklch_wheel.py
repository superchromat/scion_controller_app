#!/usr/bin/env python3
"""Generate color wheel using OKLCH - perceptually uniform color space."""

from PIL import Image
import math

def oklab_to_linear_srgb(L, a, b):
    """Convert OKLab to linear sRGB."""
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
    """Linear to sRGB gamma."""
    if x <= 0.0031308:
        return 12.92 * x
    return 1.055 * (x ** (1/2.4)) - 0.055

def oklch_to_srgb(L, C, h_deg):
    """Convert OKLCH to sRGB (0-255)."""
    h_rad = math.radians(h_deg)
    a = C * math.cos(h_rad)
    b = C * math.sin(h_rad)

    r, g, b = oklab_to_linear_srgb(L, a, b)

    # Convert to sRGB and clamp
    r = max(0, min(1, linear_to_srgb(r)))
    g = max(0, min(1, linear_to_srgb(g)))
    b = max(0, min(1, linear_to_srgb(b)))

    return int(r * 255), int(g * 255), int(b * 255)

def find_max_chroma(L, h_deg):
    """Find maximum chroma that stays in sRGB gamut."""
    for C in [x * 0.01 for x in range(40, 0, -1)]:  # 0.40 down to 0.01
        h_rad = math.radians(h_deg)
        a = C * math.cos(h_rad)
        b = C * math.sin(h_rad)
        r, g, bl = oklab_to_linear_srgb(L, a, b)
        r, g, bl = linear_to_srgb(r), linear_to_srgb(g), linear_to_srgb(bl)
        if 0 <= r <= 1 and 0 <= g <= 1 and 0 <= bl <= 1:
            return C
    return 0.01

def generate_oklch_wheel(size, filename, L=0.7):
    """Generate wheel with constant lightness L in OKLCH."""
    img = Image.new('RGB', (size, size), (0, 0, 0))
    pixels = img.load()
    center = size / 2.0
    radius = center - 2

    # Pre-compute max chroma for each hue at this lightness
    max_chroma = {}
    for h in range(360):
        max_chroma[h] = find_max_chroma(L, h)

    for y in range(size):
        for x in range(size):
            dx = x - center + 0.5
            dy = y - center + 0.5
            dist = math.sqrt(dx*dx + dy*dy)

            if dist <= radius:
                angle = math.atan2(dy, dx)
                hue = (math.degrees(angle) + 360) % 360
                t = min(dist / radius, 1.0)  # 0 at center, 1 at edge

                # At center: L=1 (white), C=0
                # At edge: L=target, C=max for that hue
                h_idx = int(hue) % 360
                C = t * max_chroma[h_idx]
                L_interp = 1.0 - t * (1.0 - L)  # 1.0 at center, L at edge

                r, g, b = oklch_to_srgb(L_interp, C, hue)
                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"Saved {filename} (OKLCH, L={L})")

# Generate at different lightness levels
generate_oklch_wheel(400, 'wheel_oklch_L70.png', L=0.70)
generate_oklch_wheel(400, 'wheel_oklch_L75.png', L=0.75)
generate_oklch_wheel(400, 'wheel_oklch_L65.png', L=0.65)

print("\nOKLCH wheels have constant perceptual lightness - no bright/dark banding")
