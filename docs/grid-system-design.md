# SCION Controller — Grid System & Layout Architecture

## Problem Statement

The current UI has no coherent layout system. Spacing, sizing, and typography are defined ad-hoc with hardcoded pixel values scattered across dozens of files. This produces:

- Panels that almost-but-don't-quite align across cards
- Inconsistent padding/margins between and within cards
- No vertical rhythm — only horizontal columns exist
- Font sizes, weights, and colors chosen per-widget with no hierarchy
- Overflow at certain window sizes
- Brittle pixel calculations that break when anything changes

## Design Principles

1. **One source of truth.** Every spacing, sizing, and typography value derives from a small set of base constants defined in one file.
2. **Two-dimensional grid.** Both horizontal columns AND vertical rows snap to a common unit.
3. **Proportional scaling.** The base unit scales with viewport width. Nothing is an absolute pixel value except the base unit computation itself.
4. **Structural equality for visual equality.** If two things should be the same height, they must use the same widget structure — not matched pixel constants.
5. **Overflow is impossible by construction.** Content fills available space; it never specifies a size larger than its container can provide.

---

## 1. The Base Unit

All layout values derive from a single **base unit `u`**, computed from the viewport:

```
u = viewportWidth * scaleFactor
```

Where `scaleFactor` is a single constant (e.g., `0.008`), giving:
- At 1200px → u ≈ 9.6
- At 1600px → u ≈ 12.8
- At 1920px → u ≈ 15.4

`u` is computed once at the page level and provided to all descendants via an `InheritedWidget` (replacing the current `GridGutterProvider` which only provides gutter).

The provider exposes the full set of derived constants, not just the gutter. Every widget reads from this provider. No widget computes its own spacing.

---

## 2. Spacing Scale

All spacing is a multiple of `u`. Define a named scale:

| Token       | Value | Use |
|-------------|-------|-----|
| `space.xs`  | 0.5u  | Tight internal gaps (title-to-content within a panel) |
| `space.sm`  | 1u    | Panel internal padding, gap between knobs |
| `space.md`  | 1.5u  | Gap between panels within a card |
| `space.lg`  | 2u    | Gap between cards, page edge padding |

**Critical rule:** The gap between cards (horizontally and vertically) is always `space.lg`. The gap between panels within a card is always `space.md`. These never vary.

Padding inside a card (from card surface to content) is `space.md` on all sides. Padding inside a panel (NeumorphicInset surface to content) is `space.sm` on all sides.

---

## 3. Horizontal Grid

A 12-column grid, same concept as today but with `u`-based gutters.

- Column gutter = `space.lg` (2u)
- Page margin = `space.lg` (2u)
- Cell formula: `cellWidth = span * (contentWidth + gutter) / 12 - gutter`

Cards placed in GridRow cells. Single-column cards get `space.lg` horizontal padding. Multi-column rows distribute width proportionally with `space.lg` gutters between cells.

---

## 4. Vertical Grid — The Key Missing Piece

Currently there is no vertical grid. Panels within cards have ad-hoc heights determined by their content. This is why knob panels and text panels never align.

### The Row Unit

Define a **row unit `r`** — the height of one standard content row:

```
r = knobDiameter + labelHeight + space.xs
```

Where:
- `knobDiameter` = the standard knob size (a multiple of `u`, e.g., `5u` → 48-77px depending on viewport)
- `labelHeight` = one line of label text
- `space.xs` = visual breathing room

A standard knob panel (title + one row of knobs) has height:

```
panelHeight = panelPadding.top + titleHeight + space.xs + r + panelPadding.bottom
            = space.sm + titleLine + space.xs + r + space.sm
```

Call this `1R` — one "panel row."

### Snap-to-grid rule

Every panel's height must be an integer multiple of `R` (plus the inter-panel gap). If a panel's natural content is between 1R and 2R, it stretches to 2R. The content inside uses flexible layout to fill the space.

This means:
- A knob panel with one row of knobs = **1R**
- A knob panel with two rows of knobs = **2R**
- A text input panel = **1R** (text field fills the space)
- A color wheel panel = **2R** (or whatever multiple fits)

Panels within the same card stack vertically with `space.md` gaps. Panels at the same vertical position across adjacent cards are guaranteed to align because they're all multiples of the same `R`.

### Implementation

A `Panel` widget replaces the current ad-hoc `NeumorphicInset` usage. It takes:
- `rows`: integer, how many row-units tall (default 1)
- `title`: optional string
- `child`: content widget

The Panel widget computes its height from `rows * R` (where R accounts for title, padding, and content), applies NeumorphicInset styling, and gives the child flexible constraints to fill the space.

A `CardColumn` widget replaces the current `Column` + `GridRow` + `GridGap` nesting inside LabeledCards. It takes a list of Panels and arranges them vertically with `space.md` gaps, ensuring consistent spacing.

---

## 5. Typography Scale

Define exactly **5 text styles**, derived from `u`:

| Token          | Size   | Weight | Color        | Use |
|----------------|--------|--------|--------------|-----|
| `text.title`   | 2u     | w600   | white        | Card titles ("Shape", "Texture") |
| `text.heading` | 1.2u   | w600   | grey.light   | Panel titles ("Scale", "Horizontal Blur") |
| `text.label`   | 1.1u   | w400   | grey.mid     | Knob labels, dropdown labels |
| `text.value`   | 1.1u   | w400   | white        | Knob values, text fields |
| `text.caption` | 1u     | w400   | grey.dark    | Secondary info, hints |

Color palette for text (3 levels):
- `white` — primary interactive text
- `grey.light` — 0xFFAAAAAA — headings, active labels
- `grey.mid` — 0xFF888888 — standard labels
- `grey.dark` — 0xFF666666 — disabled, hints

No widget defines its own TextStyle. All text uses one of these 5 tokens.

---

## 6. Control Sizing

Knob diameter is derived from `u`:

| Token          | Value | Use |
|----------------|-------|-----|
| `knob.sm`      | 4u    | Compact contexts |
| `knob.md`      | 5u    | Standard panels (Shape, Texture, Text) |
| `knob.lg`      | 6u    | Spacious panels (Color globals) |

Knobs are always circular (width = height = diameter). The knob + label constitutes one `r` (row unit).

Other control sizes:
- Dropdown height: derived from `text.value` size + padding
- Checkbox/toggle: derived from `text.label` size
- Color wheel: a defined multiple of `u` (e.g., `8u`)

---

## 7. Widget Hierarchy

The nesting is strictly:

```
Page
  └─ GridProvider (computes u, R, all tokens)
     └─ ScrollView (padding: space.lg)
        └─ GridColumn (vertical card layout, gap: space.lg)
           └─ GridRow (horizontal card layout, 12-col, gutter: space.lg)
              └─ Card (title + content, padding: space.md)
                 └─ CardColumn (vertical panel layout, gap: space.md)
                    └─ Panel (rows: N, optional title, padding: space.sm)
                       └─ [content widgets]
```

### Card

Replaces current `LabeledCard`. Provides:
- Neumorphic surface decoration
- Title row with consistent `text.title` style
- Content area with `space.md` padding on all four sides
- Content arranged by `CardColumn`

### Panel

Replaces current ad-hoc `NeumorphicInset` usage. Provides:
- Inset neumorphic decoration
- Optional title with `text.heading` style
- Fixed height: `rows * R` (where R is computed to include title, content, and padding)
- Content fills available space within the panel

### GridRow

Unchanged concept — 12-column horizontal layout. But gutter is `space.lg` (from the grid provider), not a separate calculation.

### CardColumn

New widget. Arranges Panels vertically within a Card with `space.md` gaps. Ensures consistent inter-panel spacing. No manual `GridGap` or `SizedBox` spacers.

---

## 8. Responsive Behavior

Since `u` scales with viewport width:
- All spacing scales proportionally
- Knob diameters scale (but remain circular)
- Panel heights scale (row unit R scales with knob size)
- Font sizes scale
- Cards can change aspect ratio (they fill their grid cell width, height determined by content rows)

Minimum `u` should be clamped (e.g., `u >= 6`) so controls remain usable on small screens. Maximum `u` should also be clamped (e.g., `u <= 20`) so spacing doesn't become excessive.

---

## 9. Alignment Guarantees

With this system, alignment is guaranteed by construction:

**Horizontal:** Cards snap to 12-column grid. Panels fill their card's content width. No panel specifies an absolute width.

**Vertical:** Panels snap to multiples of R. Two 1R panels in adjacent cards have exactly the same height because R is a global constant. A 2R panel aligns with two 1R panels + one `space.md` gap in the adjacent card (if `2R = 2 * 1R + space.md`... this needs the row unit to account for this).

### Vertical alignment math

For panels to align across cards, the vertical grid increment must account for the inter-panel gap:

```
G = R + space.md     (one panel + one gap)
```

A card with N panels has total content height: `N * R + (N-1) * space.md = N * G - space.md`.

Two cards with the same number of panel-rows will have the same content height. This guarantees alignment when:
- Card A has panels: [1R, 1R] → total = 2G - space.md
- Card B has panels: [1R, 1R] → total = 2G - space.md ✓
- Card C has panels: [2R] → total = 2R = 2G - 2*space.md ≠ 2G - space.md ✗

This reveals a design tension: a single 2R panel is NOT the same height as two 1R panels with a gap between them. The gap matters.

**Resolution:** Define panel height as `rows * R_inner + title + padding`, where `R_inner` is the content row height. Then:
- 1-row panel intrinsic height = `P` (some value)
- 2-row panel intrinsic height = `P + R_inner + space.xs` (adds one more content row)
- Two 1-row panels with gap = `P + space.md + P = 2P + space.md`

For `2P + space.md = P + R_inner + space.xs` to hold: `P + space.md = R_inner + space.xs`.

This won't naturally hold. So the rule should be: **within the 4-4-4 Shape/Texture/Text row, all cards must have the same panel structure** — same number of panels, same row counts per panel. If one card needs a different structure, it gets its own GridRow (not sharing IntrinsicHeight with dissimilar cards).

In practice:
- Shape (2 panels: 1R, 1R), Texture (2 panels: 1R, 1R), Text (2 panels: 1R, 1R) — all match ✓
- If Text needs a single tall panel, it goes in a separate row or the tall panel is split into title area + content area to match the two-panel structure

---

## 10. Migration Path

This is a significant refactor. Suggested order:

1. **Define the grid provider** — single file with `u`, all spacing tokens, all text styles, all control sizes, `R`, `G`. Every value computable from `u` alone.

2. **Build Panel and CardColumn widgets** — replacements for the current NeumorphicInset + Column + GridGap pattern.

3. **Migrate one page** — the Send page is the most complex. Migrate it card by card:
   - Replace hardcoded padding/spacing with tokens from the provider
   - Replace NeumorphicInset + manual spacing with Panel(rows: N)
   - Replace Column + GridGap with CardColumn
   - Verify alignment at multiple window widths

4. **Migrate remaining pages** — System, Return, Setup.

5. **Remove old constants** — delete `AppGrid` individual constants, `TileLayout`, and any file-local sizing constants.

6. **Typography pass** — replace every `TextStyle(...)` with the 5 named styles.

---

## 11. What This Solves

| Current problem | How it's solved |
|---|---|
| Text panel doesn't match knob panel height | Both are Panel(rows: 1) — same widget, same height by construction |
| Inconsistent card spacing | Single `space.lg` token used everywhere |
| Hardcoded pixel values scattered across files | All values derived from `u` in one provider |
| Panels overflow at small sizes | Panel fills available space; knob sizes scale with `u` |
| Font sizes/weights inconsistent | 5 named styles, no per-widget TextStyle |
| Vertical misalignment across cards | Panel heights snap to multiples of R |
| Horizontal spacing varies between pages | Same GridRow + gutter logic on all pages |
