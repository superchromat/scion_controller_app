# sRGB Color Wheel Experiments (Archived)

## Goal

The goal was to replicate Apple's color wheel exactly in Flutter. Apple's color wheel uses:

- **Display P3 color space** - wider gamut than sRGB, more saturated colors
- **HSV with S=1, V=1** at the edge - pure saturated colors
- **Linear RGB interpolation** from white center to saturated edge
- **Clockwise hue direction**

## The Problem

Flutter on macOS does not support Display P3 rendering. Despite:

1. Using `Color.from(colorSpace: ui.ColorSpace.displayP3)`
2. Adding `FLTEnableWideGamut` to Info.plist
3. Creating native macOS platform views with `CGColorSpace.displayP3`
4. Setting window colorSpace to P3
5. Rendering to 16-bit float P3 bitmap contexts
6. Using fragment shaders

...all color output is converted to sRGB by Flutter's compositor before reaching the display. Digital Color Meter confirmed identical RGB values for "P3" and "sRGB" colors.

## Resolution

Since P3 is not achievable in Flutter, we use **OKLCH** instead:

- OKLCH is a perceptually uniform color space
- Eliminates the harsh banding visible at 60° intervals in HSV/HSL wheels
- The L (lightness) and C (chroma) parameters allow tuning the wheel appearance
- Default values: L=0.58, C=0.26

The OKLCH wheel doesn't match Apple's exactly (less saturated due to sRGB limitations), but it looks smooth and professional without the piecewise artifacts of HSV.

## Files in this directory

- `*.py` - Python scripts used to analyze Apple's wheel and generate test images
- `*.png` - Generated wheel images and screenshots for comparison
- `apple_wheel*.png` - Screenshots of Apple's color picker for reference
