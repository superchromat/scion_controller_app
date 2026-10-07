// lazy_page_layout.dart — keeps inactive pages out of the resize path.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Holds an inactive child at the constraints it last saw while active, so a
/// window resize does not re-lay-it-out.
///
/// [IndexedStack] paints one child but *lays out all of them* — `RenderStack`
/// does the layout and `RenderIndexedStack` only overrides `paint`. With nine
/// pages mounted, every resize step re-laid-out all nine, and each page's
/// layout is dominated by text shaping and `IntrinsicHeight` intrinsic queries.
/// Rendering only the selected page cut a measured resize step from ~106 ms to
/// ~57 ms, and the frame-time tail (p99) from ~149 ms to ~28 ms.
///
/// The obvious ways to skip that work are both wrong here:
///   - `Offstage` still lays out its child (`RenderOffstage.performLayout`
///     calls `child.layout(constraints)` in the offstage branch).
///   - Not calling `child.layout()` at all leaves the child without a size, so
///     anything that reads `child.size` asserts, and a child dirtied while
///     hidden lingers in the pipeline's dirty set.
///
/// So instead of skipping the call, this makes the call free: the child is
/// always laid out, but while inactive it is laid out at the *frozen*
/// constraints. `RenderObject.layout` early-returns when the constraints are
/// unchanged and the subtree is clean, so a resize costs nothing for hidden
/// pages, while every page keeps a valid size at all times. When a page becomes
/// active it sees the live constraints again and re-lays-out once.
class LazyPageLayout extends SingleChildRenderObjectWidget {
  /// Whether this page is the one on screen.
  final bool active;

  const LazyPageLayout({
    super.key,
    required this.active,
    required Widget super.child,
  });

  @override
  RenderLazyPageLayout createRenderObject(BuildContext context) =>
      RenderLazyPageLayout(active: active);

  @override
  void updateRenderObject(
      BuildContext context, RenderLazyPageLayout renderObject) {
    renderObject.active = active;
  }
}

class RenderLazyPageLayout extends RenderProxyBox {
  RenderLazyPageLayout({required bool active}) : _active = active;

  bool _active;
  bool get active => _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    // Becoming active must re-run layout against the live constraints, which
    // may have changed many times while this page was frozen.
    markNeedsLayout();
  }

  /// The constraints this page was last laid out at while active.
  BoxConstraints? _frozen;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    if (_active) {
      _frozen = constraints;
      child.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child.size);
      return;
    }
    // Inactive: re-use the last active constraints. Unchanged constraints on a
    // clean subtree make this a no-op, which is the entire point.
    child.layout(_frozen ??= constraints, parentUsesSize: true);
    // Take the size the parent asked for, not the frozen child's — the page
    // must still occupy its slot in the stack.
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : constraints.constrain(child.size);
  }
}
