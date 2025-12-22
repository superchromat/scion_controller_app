import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'osc_widget_binding.dart';
import 'lighting_settings.dart';

/// Callback type for custom onChanged handling.
typedef OnChangedCallback<T> = void Function(T value);

/// A generic OSC-backed dropdown with neumorphic styling.
class OscDropdown<T> extends StatelessWidget {
  final String label;
  final List<T> items;
  final T? defaultValue;
  final OnChangedCallback<T>? onChanged;
  final String? pathSegment;
  final String? displayLabel;
  final bool enabled;
  final double width;

  const OscDropdown({
    super.key,
    required this.label,
    required this.items,
    this.defaultValue,
    this.onChanged,
    this.pathSegment,
    this.displayLabel,
    this.enabled = true,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    final segment = (pathSegment ?? label).toLowerCase();
    final uiLabel = displayLabel ?? label;
    return OscPathSegment(
      segment: segment,
      child: _OscDropdownInner<T>(
        label: uiLabel,
        items: items,
        defaultValue: defaultValue,
        onChanged: onChanged,
        enabled: enabled,
        width: width,
      ),
    );
  }
}

class _OscDropdownInner<T> extends StatefulWidget {
  final String label;
  final List<T> items;
  final T? defaultValue;
  final OnChangedCallback<T>? onChanged;
  final bool enabled;
  final double width;

  const _OscDropdownInner({
    super.key,
    required this.label,
    required this.items,
    this.defaultValue,
    this.onChanged,
    this.enabled = true,
    this.width = 160,
  });

  @override
  State<_OscDropdownInner<T>> createState() => _OscDropdownInnerState<T>();
}

class _OscDropdownInnerState<T> extends State<_OscDropdownInner<T>>
    with OscAddressMixin {
  late T _selected;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.defaultValue != null &&
        widget.items.contains(widget.defaultValue)) {
      _selected = widget.defaultValue as T;
    } else {
      _selected = widget.items.first;
    }
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    final incoming = args.isNotEmpty ? args.first : null;
    if (incoming is T && widget.items.contains(incoming)) {
      setState(() => _selected = incoming);
      return OscStatus.ok;
    }
    if (incoming is double) {
      for (final item in widget.items) {
        if (item is double && (item - incoming).abs() < 0.01) {
          setState(() => _selected = item as T);
          return OscStatus.ok;
        }
      }
    }
    return OscStatus.error;
  }

  void _showDropdownMenu() {
    if (!widget.enabled) return;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final buttonPos = button.localToGlobal(Offset.zero, ancestor: overlay);
    final lighting = context.read<LightingSettings>();

    // Find index of current selection
    final selectedIndex = widget.items.indexOf(_selected);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (context) => _NeumorphicDropdownMenu<T>(
        items: widget.items,
        selected: _selected,
        selectedIndex: selectedIndex,
        buttonRect: Rect.fromLTWH(
          buttonPos.dx,
          buttonPos.dy,
          button.size.width,
          button.size.height,
        ),
        lighting: lighting,
        formatLabel: _formatLabel,
        onSelected: (value) {
          Navigator.of(context).pop();
          setState(() => _selected = value);
          sendOsc(value);
          widget.onChanged?.call(value);
        },
      ),
    );
  }

  String _formatLabel(T item) {
    if (item is double) {
      final value = item;
      if ((value - value.roundToDouble()).abs() < 1e-6) {
        return value.toStringAsFixed(0);
      }
      return value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return item.toString();
  }

  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              color: widget.enabled ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Button
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: _showDropdownMenu,
            child: _NeumorphicDropdownButton(
              lighting: lighting,
              width: widget.width,
              enabled: widget.enabled,
              isHovered: _isHovered,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatLabel(_selected),
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: widget.enabled ? Colors.white : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.unfold_more,
                    size: 16,
                    color: widget.enabled ? Colors.grey[400] : Colors.grey[700],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Neumorphic styled dropdown button with global position tracking
class _NeumorphicDropdownButton extends StatefulWidget {
  final LightingSettings lighting;
  final double width;
  final bool enabled;
  final bool isHovered;
  final Widget child;

  const _NeumorphicDropdownButton({
    required this.lighting,
    required this.width,
    required this.enabled,
    required this.isHovered,
    required this.child,
  });

  @override
  State<_NeumorphicDropdownButton> createState() => _NeumorphicDropdownButtonState();
}

class _NeumorphicDropdownButtonState extends State<_NeumorphicDropdownButton> {
  final GlobalKey _key = GlobalKey();
  Rect? _globalRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());
  }

  void _updateGlobalRect() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      final newRect = position & renderBox.size;
      if (_globalRect != newRect) {
        setState(() => _globalRect = newRect);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    return Container(
      key: _key,
      width: widget.width,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: widget.enabled
            ? widget.lighting.createNeumorphicShadows(elevation: widget.isHovered ? 3.0 : 2.0)
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          painter: _DropdownButtonPainter(
            lighting: widget.lighting,
            enabled: widget.enabled,
            isHovered: widget.isHovered,
            globalRect: _globalRect,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _DropdownButtonPainter extends CustomPainter {
  final LightingSettings lighting;
  final bool enabled;
  final bool isHovered;
  final Rect? globalRect;

  _DropdownButtonPainter({
    required this.lighting,
    required this.enabled,
    required this.isHovered,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Base color - slightly lighter when hovered
    final baseColor = enabled
        ? (isHovered ? const Color(0xFF454548) : const Color(0xFF3A3A3C))
        : const Color(0xFF2A2A2C);

    // Gradient fill with global position for Phong shading
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: enabled ? 0.04 : 0.02,
      globalRect: globalRect,
    );
    final gradientPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, gradientPaint);

    // Edge highlight
    if (enabled) {
      final light = lighting.lightDir2D;
      final highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment(light.dx, light.dy),
          end: Alignment(-light.dx, -light.dy),
          colors: [
            Colors.white.withValues(alpha: isHovered ? 0.15 : 0.10),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.12),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);

      canvas.drawRRect(rrect.deflate(0.5), highlightPaint);
    }

    // Noise texture
    if (lighting.noiseImage != null && enabled) {
      final noisePaint = Paint()
        ..shader = ImageShader(
          lighting.noiseImage!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay;

      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(rect, noisePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DropdownButtonPainter oldDelegate) {
    return oldDelegate.enabled != enabled ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.lighting.lightDistance != lighting.lightDistance ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}

/// Dropdown menu overlay - positions selected item at the button location
class _NeumorphicDropdownMenu<T> extends StatelessWidget {
  final List<T> items;
  final T selected;
  final int selectedIndex;
  final Rect buttonRect;
  final LightingSettings lighting;
  final String Function(T) formatLabel;
  final ValueChanged<T> onSelected;

  static const double _itemHeight = 36.0;
  static const double _menuPadding = 4.0;

  const _NeumorphicDropdownMenu({
    required this.items,
    required this.selected,
    required this.selectedIndex,
    required this.buttonRect,
    required this.lighting,
    required this.formatLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final totalMenuHeight = items.length * _itemHeight + _menuPadding * 2;
    final maxMenuHeight = 300.0;
    final menuHeight = totalMenuHeight.clamp(0.0, maxMenuHeight);

    // Calculate where the selected item would be in the menu
    final selectedItemTop = selectedIndex * _itemHeight + _menuPadding;

    // Position menu so selected item aligns with button center
    final buttonCenterY = buttonRect.top + buttonRect.height / 2;
    final selectedItemCenterOffset = selectedItemTop + _itemHeight / 2;

    // Calculate ideal menu top position
    var menuTop = buttonCenterY - selectedItemCenterOffset;

    // Clamp to screen bounds with some margin
    const margin = 8.0;
    menuTop = menuTop.clamp(margin, screenSize.height - menuHeight - margin);

    // Calculate scroll offset if menu is smaller than total content
    double initialScrollOffset = 0;
    if (totalMenuHeight > maxMenuHeight) {
      // We need to scroll to show the selected item
      final visibleTop = menuTop;
      final visibleBottom = menuTop + menuHeight;
      final idealSelectedTop = buttonCenterY - _itemHeight / 2;

      // Calculate how much to scroll so selected item is visible and centered
      initialScrollOffset = selectedItemTop - (menuHeight / 2 - _itemHeight / 2);
      initialScrollOffset = initialScrollOffset.clamp(0.0, totalMenuHeight - menuHeight);
    }

    return Stack(
      children: [
        // Dismiss area
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Menu
        Positioned(
          left: buttonRect.left,
          top: menuTop,
          child: _NeumorphicMenuContainer(
            lighting: lighting,
            width: buttonRect.width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: menuHeight),
              child: _ScrollableMenuContent<T>(
                items: items,
                selected: selected,
                lighting: lighting,
                formatLabel: formatLabel,
                onSelected: onSelected,
                initialScrollOffset: initialScrollOffset,
                itemHeight: _itemHeight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollableMenuContent<T> extends StatefulWidget {
  final List<T> items;
  final T selected;
  final LightingSettings lighting;
  final String Function(T) formatLabel;
  final ValueChanged<T> onSelected;
  final double initialScrollOffset;
  final double itemHeight;

  const _ScrollableMenuContent({
    required this.items,
    required this.selected,
    required this.lighting,
    required this.formatLabel,
    required this.onSelected,
    required this.initialScrollOffset,
    required this.itemHeight,
  });

  @override
  State<_ScrollableMenuContent<T>> createState() => _ScrollableMenuContentState<T>();
}

class _ScrollableMenuContentState<T> extends State<_ScrollableMenuContent<T>> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.items.map((item) {
          final isSelected = item == widget.selected;
          return _NeumorphicMenuItem(
            lighting: widget.lighting,
            label: widget.formatLabel(item),
            isSelected: isSelected,
            onTap: () => widget.onSelected(item),
          );
        }).toList(),
      ),
    );
  }
}

/// Container for the dropdown menu with global position tracking
class _NeumorphicMenuContainer extends StatefulWidget {
  final LightingSettings lighting;
  final double width;
  final Widget child;

  const _NeumorphicMenuContainer({
    required this.lighting,
    required this.width,
    required this.child,
  });

  @override
  State<_NeumorphicMenuContainer> createState() => _NeumorphicMenuContainerState();
}

class _NeumorphicMenuContainerState extends State<_NeumorphicMenuContainer> {
  final GlobalKey _key = GlobalKey();
  Rect? _globalRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());
  }

  void _updateGlobalRect() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      final newRect = position & renderBox.size;
      if (_globalRect != newRect) {
        setState(() => _globalRect = newRect);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    return Container(
      key: _key,
      width: widget.width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _MenuContainerPainter(
            lighting: widget.lighting,
            globalRect: _globalRect,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _MenuContainerPainter extends CustomPainter {
  final LightingSettings lighting;
  final Rect? globalRect;

  _MenuContainerPainter({
    required this.lighting,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    // Solid dark background with Phong shading and global position
    const baseColor = Color(0xFF2E2E30);
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.03,
      globalRect: globalRect,
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);

    // Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawRRect(rrect.deflate(0.5), borderPaint);

    // Noise
    if (lighting.noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ImageShader(
          lighting.noiseImage!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay;

      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(rect, noisePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MenuContainerPainter oldDelegate) {
    return oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.lighting.lightDistance != lighting.lightDistance ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}

/// Individual menu item
class _NeumorphicMenuItem extends StatefulWidget {
  final LightingSettings lighting;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NeumorphicMenuItem({
    required this.lighting,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NeumorphicMenuItem> createState() => _NeumorphicMenuItemState();
}

class _NeumorphicMenuItemState extends State<_NeumorphicMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isSelected
        ? const Color(0xFF4A4A4C)
        : (_isHovered ? const Color(0xFF3A3A3C) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: widget.isSelected
                        ? const Color(0xFFFFF176)
                        : Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                const Icon(
                  Icons.check,
                  size: 14,
                  color: Color(0xFFFFF176),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
