#!/usr/bin/env python3
"""Generate OKLCH wheel with maximum saturation per hue."""

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

def oklch_to_srgb_clamp(L, C, h_deg):
    """Convert OKLCH to sRGB, clamping to gamut."""
    h_rad = math.radians(h_deg)
    a = C * math.cos(h_rad)
    b = C * math.sin(h_rad)
    r, g, b = oklab_to_linear_srgb(L, a, b)
    r = max(0, min(1, linear_to_srgb(r)))
    g = max(0, min(1, linear_to_srgb(g)))
    b = max(0, min(1, linear_to_srgb(b)))
    return int(r * 255), int(g * 255), int(b * 255)

def find_optimal_LC(h_deg):
    """Find the L and C that gives maximum chroma while staying in sRGB."""
    best_C = 0
    best_L = 0.5
    # Search L from 0.3 to 0.9, find max C at each
    for L_int in range(30, 91, 2):
        L = L_int / 100.0
        for C_int in range(50, 0, -1):
            C = C_int / 100.0
            h_rad = math.radians(h_deg)
            a = C * math.cos(h_rad)
            b = C * math.sin(h_rad)
            r, g, bl = oklab_to_linear_srgb(L, a, b)
            r_s = linear_to_srgb(r)
            g_s = linear_to_srgb(g)
            b_s = linear_to_srgb(bl)
            if 0 <= r_s <= 1 and 0 <= g_s <= 1 and 0 <= b_s <= 1:
                if C > best_C:
                    best_C = C
                    best_L = L
                break
    return best_L, best_C

# Pre-compute optimal L and C for each hue
print("Finding optimal L,C for each hue...")
optimal = {}
for h in range(360):
    optimal[h] = find_optimal_LC(h)

print("\nOptimal values at key hues:")
for h in [0, 60, 120, 180, 240, 300]:
    L, C = optimal[h]
    print(f"  {h}° (hue): L={L:.2f}, C={C:.2f}")

def generate_wheel(size, filename):
    img = Image.new('RGB', (size, size), (0, 0, 0))
    pixels = img.load()
    center = size / 2.0
    radius = center - 2

    for y in range(size):
        for x in range(size):
            dx = x - center + 0.5
            dy = y - center + 0.5
            dist = math.sqrt(dx*dx + dy*dy)

            if dist <= radius:
                angle = math.atan2(dy, dx)
                hue = (math.degrees(angle) + 360) % 360
                t = min(dist / radius, 1.0)

                h_idx = int(hue) % 360
                target_L, max_C = optimal[h_idx]

                # Interpolate from white center to optimal color at edge
                L = 1.0 - t * (1.0 - target_L)
                C = t * max_C

                r, g, b = oklch_to_srgb_clamp(L, C, hue)
                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"\nSaved {filename}")

generate_wheel(400, 'wheel_oklch_maxsat.png')

# Also try with boosted chroma (will clip but look more saturated)
def generate_wheel_boosted(size, filename, boost=1.3):
    img = Image.new('RGB', (size, size), (0, 0, 0))
    pixels = img.load()
    center = size / 2.0
    radius = center - 2

    for y in range(size):
        for x in range(size):
            dx = x - center + 0.5
            dy = y - center + 0.5
            dist = math.sqrt(dx*dx + dy*dy)

            if dist <= radius:
                angle = math.atan2(dy, dx)
                hue = (math.degrees(angle) + 360) % 360
                t = min(dist / radius, 1.0)

                h_idx = int(hue) % 360
                target_L, max_C = optimal[h_idx]

                L = 1.0 - t * (1.0 - target_L)
                C = t * max_C * boost  # Boost chroma

                r, g, b = oklch_to_srgb_clamp(L, C, hue)
                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"Saved {filename} (boost={boost})")

generate_wheel_boosted(400, 'wheel_oklch_boost130.png', boost=1.3)
generate_wheel_boosted(400, 'wheel_oklch_boost150.png', boost=1.5)
