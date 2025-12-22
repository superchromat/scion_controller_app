# Colorspace Matrix Editor: Three-Wheel Specification

## Overview

A visual interface for defining custom RGB-to-colorspace transformation matrices using three interactive color wheels. Replaces direct 3x3 matrix entry with an intuitive primary-color selection model.

---

## Linear Algebra Foundation

### The Primary Color Model

The user selects three **primary colors** P1, P2, P3. Each primary represents the RGB color that maps to a pure unit vector in the output colorspace:

- P1 → the RGB color that becomes [1, 0, 0] in output space
- P2 → the RGB color that becomes [0, 1, 0] in output space
- P3 → the RGB color that becomes [0, 0, 1] in output space

### Matrix Construction

Arrange the primaries as **columns** of matrix M:

```
M = [ P1 | P2 | P3 ]

    [ P1.r  P2.r  P3.r ]
  = [ P1.g  P2.g  P3.g ]
    [ P1.b  P2.b  P3.b ]
```

This matrix M converts **from** the custom colorspace **to** RGB:

```
M × [custom] = [RGB]
```

The desired RGB-to-custom transformation matrix is the inverse:

```
T = M⁻¹

T × [RGB] = [custom]
```

### Invertibility Constraint

For M⁻¹ to exist, the three primaries must be **linearly independent** — they cannot lie on a plane through the origin in RGB space.

Geometrically:
- det(M) ≠ 0
- The volume of the parallelepiped formed by P1, P2, P3 is non-zero

### Numerical Stability

Not all invertible matrices are equally well-behaved under IEEE 754 floating-point arithmetic. The **condition number** κ(M) quantifies numerical stability:

```
κ(M) = σ_max / σ_min
```

Where σ_max and σ_min are the largest and smallest singular values of M.

| Condition Number | Interpretation |
|-----------------|----------------|
| κ ≈ 1 | Ideal (identity matrix = 1.0) |
| κ < 10 | Excellent |
| κ < 100 | Good |
| κ > 1000 | Poor — expect precision loss |
| κ → ∞ | Singular — matrix not invertible |

The condition number increases as the primaries become more coplanar.

### Example: Identity Matrix (RGB passthrough)

```
P1 = [1, 0, 0]  (pure red)
P2 = [0, 1, 0]  (pure green)
P3 = [0, 0, 1]  (pure blue)

M = I, M⁻¹ = I, κ(M) = 1.0
```

### Example: YUV (BT.601)

The primaries are the columns of the YUV→RGB matrix:

```
P1 = [1.000,  1.000,  1.000]   (white — luma responds to all)
P2 = [0.000, -0.394,  2.032]   (blue-ish, outside sRGB)
P3 = [1.140, -0.581,  0.000]   (red-ish, outside sRGB)
```

Note: P2 and P3 have negative components and magnitudes exceeding 1.0. These are "impossible" colors in sRGB but valid mathematical basis vectors.

---

## User Interface Specification

### Three Symmetric Color Wheels

Each wheel is an identical, peer control. No ordering or hierarchy — any wheel can define any channel, including the luma channel.

#### Wheel Geometry

```
        ┌─────────────────────┐
       ╱   Extended Gamut      ╲
      ╱   (hatched/faded)       ╲
     ╱  ┌─────────────────┐      ╲
    │  ╱    sRGB Gamut     ╲      │
    │ │                     │     │
    │ │    ○ (white at      │     │
    │ │       center)       │     │
    │ │                     │     │
    │  ╲                   ╱      │
     ╲  └─────────────────┘      ╱
      ╲                         ╱
       ╲                       ╱
        └─────────────────────┘
```

- **Center:** White/grey (saturation = 0)
- **Inner region:** sRGB gamut at V=1.0, shown with full saturation
- **Outer region:** Extended gamut beyond sRGB, visually distinguished (faded, hatched, or desaturated background)
- **Hue:** Angular position around the wheel
- **Saturation/Magnitude:** Radial distance from center

#### Extended Gamut Representation

Since useful transforms like YUV require primaries outside sRGB:

- The wheel extends beyond the normal sRGB boundary
- Extended region uses distinct visual treatment (e.g., diagonal hatching, reduced opacity, or subtle grid pattern)
- RGB values in this region may be negative or exceed 1.0
- Selection is unconstrained — user can pick any point

### Condition Number Heat Map

Each wheel displays a real-time overlay showing the conditioning impact of each possible selection, given the current positions of the other two wheels.

#### Visualization

```
Color coding (suggested):
  Green  → κ < 10     (excellent)
  Yellow → κ < 100    (good)
  Orange → κ < 1000   (marginal)
  Red    → κ > 1000   (poor)
  Black  → singular   (invalid)
```

The heat map is rendered as a semi-transparent overlay on the wheel, allowing the underlying hue/gamut information to remain visible.

#### Update Behavior

- Dragging any wheel causes the **other two wheels** to update their heat maps
- Updates occur in real-time during drag operations
- The dragged wheel's own heat map is not shown (or shown dimmed) since its position is actively changing

### Numeric Display

Adjacent to the wheels, display:

#### Per-Wheel Values
```
Channel 1:  R: 1.000   G: 1.000   B: 1.000
Channel 2:  R: 0.000   G: -0.394  B: 2.032
Channel 3:  R: 1.140   G: -0.581  B: 0.000
```

#### Matrix and Metrics
```
Condition Number: κ = 3.47

Transform Matrix (RGB → Custom):
┌                           ┐
│  0.299   0.587   0.114    │
│ -0.147  -0.289   0.436    │
│  0.615  -0.515  -0.100    │
└                           ┘
```

### Preset Configurations

Quick-access buttons for common colorspaces:

| Preset | P1 (Ch.1) | P2 (Ch.2) | P3 (Ch.3) |
|--------|-----------|-----------|-----------|
| RGB (Identity) | Red [1,0,0] | Green [0,1,0] | Blue [0,0,1] |
| YUV (BT.601) | White | Blue-ish | Red-ish |
| YUV (BT.709) | White | Blue-ish | Red-ish |
| YCbCr | White | Blue-ish | Red-ish |

Selecting a preset animates the wheels to their target positions.

---

## Interaction Behavior

### Wheel Dragging

1. User clicks/touches a wheel
2. Drag moves the selection point (hue + saturation/magnitude)
3. Other two wheels update their heat maps in real-time
4. Numeric displays update continuously
5. Condition number updates continuously

### Constraint Feedback

As the user drags toward a poorly-conditioned configuration:

1. Heat maps on other wheels shift toward red/warning colors
2. Condition number display changes color (green → yellow → red)
3. No hard stops — user can select any configuration
4. If truly singular (det = 0), display "Matrix Singular" warning

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Two primaries identical | Third wheel shows a "band" of invalid colors (the plane constraint) |
| All three approaching same point | All wheels go red, condition number → ∞ |
| Primary at origin [0,0,0] | Singular; show warning. (Note: with the wheel design at V=1, the origin is not selectable — center is white, not black) |

---

## Performance Considerations

### Condition Number Computation

Computing κ(M) requires SVD, which for a 3×3 matrix is O(1) but non-trivial per-pixel.

#### Optimization Strategies

1. **Coarse grid:** Compute heat map on a 32×32 or 64×64 grid, interpolate
2. **On-demand:** Only compute for pixels near the cursor during drag
3. **Caching:** Cache the other two primaries; only recompute when they change
4. **GPU:** Compute heat map in a fragment shader

For a 3×3 matrix, even naive CPU computation at 60fps on a 64×64 grid (~4000 SVDs/frame) should be feasible on modern hardware.

---

## Implementation Notes

### Coordinate Systems

- **Wheel coordinates:** Polar (angle, radius) where angle = hue, radius = magnitude
- **RGB coordinates:** Cartesian, unbounded (negative values and >1.0 allowed)
- **Conversion:** Standard HSV-to-RGB at V=1.0 for the sRGB region; linear extrapolation for extended gamut

### Extended Gamut Mapping

For radii beyond the sRGB boundary:

```
rgb = hsv_to_rgb(hue, 1.0, 1.0)  // Unit vector in RGB direction
rgb = rgb × (radius / srgb_boundary_radius)  // Scale by magnitude
```

This allows negative values when the "hue" points toward a direction that would require negative RGB to achieve.

Actually, for negative components, consider:
- The wheel center is white [1,1,1]
- Moving toward a hue reduces the opposite component
- Extending past the boundary continues linearly, allowing negatives

### Matrix Inversion

For 3×3, use the analytical formula (adjugate / determinant) rather than general-purpose LU decomposition. Check determinant magnitude before inverting; if |det| < ε, display warning.

---

## Future Considerations

- **Linked sliders view:** RGB sliders where adjusting one updates the color bands displayed on the others
- **3D visualization:** Show the three primaries as vectors in a 3D RGB cube
- **Gamut boundary display:** Show which output colors are achievable given the current matrix
- **Undo/redo:** State history for wheel positions
