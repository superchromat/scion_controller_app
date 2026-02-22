# Rotary Knob with Transient Linear Drag Bar

## 1. Purpose

This control resolves the ambiguity of rotary knobs in mouse-driven UIs by separating
representation from manipulation.

- The rotary knob represents the current state compactly.
- A transient horizontal bar provides an explicit, linear interaction surface.
- Value changes are incremental and continuous, with no jumps.

---

## 2. Core Principles

- Rotary knob = state indicator
- Horizontal bar = interaction surface
- Mouse motion controls value deltas, not absolute positions
- Cursor is visually aligned to the current value at drag start
- All snapping and non-linearity operate in value space

---

## 3. Data Model

### 3.1 Required Properties

- `minValue: double`
- `maxValue: double`
- `value: double`
- `format: string` (printf-style format string)
- `label: string`

Constraint:
- `value` is clamped to `[minValue, maxValue]`

### 3.2 Optional Properties

- `defaultValue: double`
- `isBipolar: bool`

If `isBipolar` is true, `0` must lie within `[minValue, maxValue]`.

---

## 4. Value Mapping

### 4.1 Spaces

- Normalized space: `t ∈ [0, 1]`
- Value space: `v ∈ [minValue, maxValue]`

### 4.2 Piecewise Mapping

Mapping is defined by ordered segments:

Each segment contains:
- `t0, t1` — normalized bounds
- `v0, v1` — value bounds
- `curve` — monotonic mapping function

Required functions:
- `valueFromNormalized(t) -> v`
- `normalizedFromValue(v) -> t`

Rules:
- Segments fully cover `[0,1]`
- Mapping is strictly monotonic
- Round-trip stability is required within tolerance

---

## 5. Snapping (Value Space)

### 5.1 Configuration

- `snapPoints: List<double>`
- `snapRegionHalfWidth: double`
- `snapHysteresisMultiplier: double`
- `snapAvoidanceSpeedThreshold: double`
- `snapBriefHoldTimeMs: int`
- `snapBehavior: Hard | Soft`

Notes:
- Snap points are defined in value space
- All snap points are equally weighted
- Endpoints are clamps only (no magnetism)

---

### 5.2 Direction of Travel

- `dv = vProposed - vPrevious`
- `direction = sign(dv)`

If two snap points are equidistant, choose the one in the direction of travel.

---

### 5.3 Mouse-Only Snap Avoidance

Compute instantaneous speed:
- `speed = |dv| / dt`

If:
- `speed < snapAvoidanceSpeedThreshold`

Then snapping is suppressed, allowing deliberate slow motion to bypass snaps.

---

### 5.4 Capture and Hysteresis

Capture condition:
- `|vProposed - s| ≤ snapRegionHalfWidth`

Release condition:
- `|vProposed - s| > snapRegionHalfWidth * snapHysteresisMultiplier`

---

### 5.5 Fast Crossing Behavior

If a snap region is crossed at high speed:
- Snap briefly
- Hold snap for `snapBriefHoldTimeMs`
- After hold expiration, apply hysteresis rules

---

### 5.6 Hard vs Soft Snap

**Hard Snap**
- Output value is exactly the snap point

**Soft Snap**
- Bias toward the snap point using a smooth weighting function
- Output value approaches snap point near center, continuous at edges

Display rule:
- While snapped, the displayed value is the exact snap value
- The format string must render snap values unambiguously

---

## 6. Idle Visual State

### 6.1 Layout

- Rotary knob (theme-defined size)
- Label text area
- Center numeric value display

### 6.2 Rotary Indicator

- Arc or pointer mapped from normalized value
- Fixed sweep angle with dead zone

#### Bipolar Knobs
- Zero marker at `normalizedFromValue(0)`
- Visual distinction between negative and positive regions

---

## 7. Interaction States

- Idle
- Armed (mouse down, no movement yet)
- Dragging (horizontal bar visible)
- Settling (optional fade-out)

---

## 8. Mouse Interaction

### 8.1 Mouse Down

On mouse-down:
- Record `startValue`
- Record `startNormalized`
- Record `startMouseX`
- Record `startTime`

No value change occurs at this stage.

---

### 8.2 Drag Initiation

When horizontal movement exceeds a small threshold:
- Enter Dragging state
- Show horizontal bar

---

## 9. Horizontal Bar Interaction

### 9.1 Geometry

- Fixed bar width (e.g. 500 px)
- Theme-defined height

### 9.2 Incremental Mapping

During drag:
- `dx = mouseX - startMouseX`
- `dt = dx / effectiveDragWidth`
- `tProposed = clamp01(startNormalized + dt)`
- `vProposed = valueFromNormalized(tProposed)`
- Apply snapping to produce `vFinal`

---

### 9.3 Cursor Recentering

At drag start:
- The value indicator is drawn under the cursor
- Achieved by offsetting the bar’s internal scale
- Cursor never maps to an absolute bar position
- Cursor motion represents value delta only

---

## 10. Constrained Window Placement

### 10.1 Placement Policy: Clamp to Viewport

1. Compute ideal bar rect centered below the knob.
2. Clamp horizontally to viewport bounds.
3. If insufficient space below, attempt placement above.
4. If still constrained, clamp vertically.

If bar width exceeds viewport width:
- Reduce bar width to viewport width
- Preserve interaction semantics

Clamping affects placement only, not interaction behavior.

---

## 11. Display During Drag

- Center numeric display updates live
- Bar shows:
  - min/max extents
  - current value indicator
  - zero marker for bipolar knobs
  - optional tick marks

---

## 12. Mouse Up

On mouse-up:
- Commit final value
- Clear snap state
- Hide horizontal bar

---

## 13. Behavioral Guarantees

- No value jump on mouse-down
- Explicit drag direction
- Full range visibility during interaction
- Snapping avoidable via slow motion
- Fast motion produces brief, informative snaps
- Endpoints clamp without magnetism
- Displayed values match snap points exactly when snapped

---

