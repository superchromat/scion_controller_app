import 'package:flutter/foundation.dart';

/// Which kind of overlay element is currently selected in a Send's Shape card.
enum ShapeSel { none, text, sprite }

/// UI-only shared state for one Send's Shape card, provided above the canvas
/// ([ShapeCanvas]) and the two editors ([SendText], [SpritePanel]). It is NOT
/// device state — it only coordinates the three sibling widgets so that:
///
///  * editing a text region / sprite highlights it on the canvas, and
///  * tapping a text/sprite on the canvas opens its editor page, and
///  * a region already holding text is shown as unavailable for a sprite (and
///    vice-versa), since the device gives each region 2-4 to text OR a sprite.
///
/// Occupancy is fed by the canvas, which already mirrors the relevant device
/// state (text strings + sprite show/hide echoes).
class ShapeSelection extends ChangeNotifier {
  ShapeSel kind = ShapeSel.none;
  int region = 1; // text: 1..4, sprite: 2..4

  // Per-region occupancy, indexed [region-1] for regions 1..4.
  final List<bool> _textOn = List.filled(4, false);
  final List<bool> _spriteOn = List.filled(4, false);

  bool textOccupied(int region) =>
      region >= 1 && region <= 4 && _textOn[region - 1];
  bool spriteOccupied(int region) =>
      region >= 1 && region <= 4 && _spriteOn[region - 1];

  /// Select an element. No-op (no notification) if already selected, so the
  /// editors/canvas can call this freely without causing feedback loops.
  void select(ShapeSel k, int r) {
    if (kind == k && region == r) return;
    kind = k;
    region = r;
    notifyListeners();
  }

  void setTextOccupied(int region, bool on) {
    if (region < 1 || region > 4 || _textOn[region - 1] == on) return;
    _textOn[region - 1] = on;
    notifyListeners();
  }

  void setSpriteOccupied(int region, bool on) {
    if (region < 1 || region > 4 || _spriteOn[region - 1] == on) return;
    _spriteOn[region - 1] = on;
    notifyListeners();
  }
}
