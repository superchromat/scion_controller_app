#!/usr/bin/env python3
"""Generate color wheel with normalized brightness - all hues equally bright."""

from PIL import Image
import math

def hsv_to_rgb_normalized(h, s, v):
    """HSV to RGB, then normalize so total brightness matches red's brightness."""
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

    r, g, b = r + m, g + m, b + m

    # Calculate brightness (sum of RGB at full saturation for this hue)
    # At full sat, the hue color determines how many channels are lit
    if s > 0.01:
        # Get the fully saturated version of this hue
        c_full = v  # At S=1, C = V
        x_full = c_full * (1 - abs((h_prime % 2) - 1))

        if h_prime < 1: r_f, g_f, b_f = c_full, x_full, 0
        elif h_prime < 2: r_f, g_f, b_f = x_full, c_full, 0
        elif h_prime < 3: r_f, g_f, b_f = 0, c_full, x_full
        elif h_prime < 4: r_f, g_f, b_f = 0, x_full, c_full
        elif h_prime < 5: r_f, g_f, b_f = x_full, 0, c_full
        else: r_f, g_f, b_f = c_full, 0, x_full

        hue_brightness = r_f + g_f + b_f  # How bright this hue is at full sat
        red_brightness = 1.0  # Red at full sat has brightness = 1.0

        # Scale factor to match red's brightness
        if hue_brightness > 0:
            scale = red_brightness / hue_brightness
            # Apply scaling, interpolated by saturation
            # At S=0 (white), no scaling needed
            # At S=1 (full color), full scaling
            effective_scale = 1.0 + (scale - 1.0) * s

            r *= effective_scale
            g *= effective_scale
            b *= effective_scale

    return (
        min(255, max(0, int(r * 255))),
        min(255, max(0, int(g * 255))),
        min(255, max(0, int(b * 255)))
    )

def generate_wheel(size, filename, normalize=False):
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
                sat = min(dist / radius, 1.0)

                if normalize:
                    r, g, b = hsv_to_rgb_normalized(hue, sat, 1.0)
                else:
                    # Standard HSV
                    c = sat
                    h_prime = hue / 60.0
                    x2 = c * (1 - abs((h_prime % 2) - 1))
                    m = 1.0 - c
                    if h_prime < 1: r, g, b = c, x2, 0
                    elif h_prime < 2: r, g, b = x2, c, 0
                    elif h_prime < 3: r, g, b = 0, c, x2
                    elif h_prime < 4: r, g, b = 0, x2, c
                    elif h_prime < 5: r, g, b = x2, 0, c
                    else: r, g, b = c, 0, x2
                    r, g, b = int((r+m)*255), int((g+m)*255), int((b+m)*255)

                pixels[x, y] = (r, g, b)

    img.save(filename)
    print(f"Saved {filename}")

# Generate both versions
generate_wheel(400, 'wheel_standard.png', normalize=False)
generate_wheel(400, 'wheel_normalized.png', normalize=True)

print("\nCompare wheel_standard.png vs wheel_normalized.png")
print("Normalized version dims YCM to match RGB brightness")
