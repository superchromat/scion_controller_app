#!/usr/bin/env python3
"""Analyze banding by measuring luminance variation along the circumference."""

from PIL import Image
import math

def get_luminance(r, g, b):
    """Rec. 709 luminance."""
    return 0.2126 * (r/255) + 0.7152 * (g/255) + 0.0722 * (b/255)

def analyze_banding(path, name):
    print(f"\n{'='*70}")
    print(f"BANDING ANALYSIS: {name}")
    print(f"{'='*70}")

    img = Image.open(path).convert('RGB')
    width, height = img.size
    center_x, center_y = width // 2, height // 2
    radius = min(width, height) // 2 - 5

    # Sample at 80% radius around the circumference, 1 degree steps
    print(f"\nSampling at 80% radius ({int(radius*0.8)}px from center)")

    samples = []
    for angle_deg in range(360):
        angle_rad = math.radians(angle_deg)
        x = int(center_x + radius * 0.8 * math.cos(angle_rad))
        y = int(center_y + radius * 0.8 * math.sin(angle_rad))
        r, g, b = img.getpixel((x, y))
        lum = get_luminance(r, g, b)
        samples.append((angle_deg, r, g, b, lum))

    # Calculate luminance derivatives (rate of change)
    derivatives = []
    for i in range(360):
        prev_lum = samples[(i - 1) % 360][4]
        curr_lum = samples[i][4]
        next_lum = samples[(i + 1) % 360][4]

        # Second derivative to detect sudden changes
        d2 = abs((next_lum - curr_lum) - (curr_lum - prev_lum))
        derivatives.append((i, d2, curr_lum))

    # Sort by derivative magnitude to find worst banding
    derivatives.sort(key=lambda x: x[1], reverse=True)

    print("\nTop 10 worst discontinuities (potential banding):")
    print("Angle\t2nd Deriv\tLuminance\tRGB")
    for i in range(min(10, len(derivatives))):
        angle, d2, lum = derivatives[i]
        r, g, b = samples[angle][1:4]
        print(f"{angle}°\t{d2:.4f}\t\t{lum:.3f}\t\t({r:3d},{g:3d},{b:3d})")

    # Check for banding at 60° intervals (HSV sector boundaries)
    print("\n\nLuminance at HSV sector boundaries (0°, 60°, 120°, 180°, 240°, 300°):")
    print("Angle\tLum\t\tΔ from prev")
    sector_angles = [0, 60, 120, 180, 240, 300]
    for i, angle in enumerate(sector_angles):
        lum = samples[angle][4]
        if i > 0:
            prev_lum = samples[sector_angles[i-1]][4]
            delta = lum - prev_lum
            print(f"{angle}°\t{lum:.3f}\t\t{delta:+.3f}")
        else:
            print(f"{angle}°\t{lum:.3f}")

    # Overall stats
    lums = [s[4] for s in samples]
    d2s = [d[1] for d in derivatives]

    print(f"\n\nSummary:")
    print(f"  Luminance range: {min(lums):.3f} - {max(lums):.3f}")
    print(f"  Max 2nd derivative: {max(d2s):.4f}")
    print(f"  Mean 2nd derivative: {sum(d2s)/len(d2s):.4f}")

    return samples, derivatives

# Analyze both
apple_samples, apple_derivs = analyze_banding('apple_wheel.png', 'APPLE')
python_samples, python_derivs = analyze_banding('python_wheel_large.png', 'PYTHON')

print(f"\n{'='*70}")
print("COMPARISON")
print(f"{'='*70}")
print("\nApple max discontinuity: {:.4f} at {}°".format(apple_derivs[0][1], apple_derivs[0][0]))
print("Python max discontinuity: {:.4f} at {}°".format(python_derivs[0][1], python_derivs[0][0]))
