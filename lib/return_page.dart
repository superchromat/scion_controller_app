import 'package:flutter/material.dart';

import 'labeled_card.dart';
import 'lut_editor.dart';
import 'osc_dropdown.dart';
import 'osc_value_label.dart';
import 'osc_widget_binding.dart';
import 'numeric_slider.dart';
import 'adv_tuning.dart';

class ReturnPage extends StatelessWidget {
  const ReturnPage({super.key});

  static const List<String> _colorspaces = <String>['YUV', 'RGB'];
  static const List<String> _subsamplings = <String>['4:4:4', '4:2:2', '4:2:0'];
  static const List<int> _bitDepths = <int>[8, 10, 12];

  @override
  Widget build(BuildContext context) {
    return const OscPathSegment(
      segment: 'output',
      child: _ReturnPageBody(),
    );
  }
}

class _ReturnPageBody extends StatelessWidget {
  const _ReturnPageBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _ReturnOutputFormatCard(),
        SizedBox(height: 16),
        _ReturnOutputPictureCard(),
/*        SizedBox(height: 16),
        AdvTuningCard(), */
        SizedBox(height: 16),
        _ReturnOutputLutCard(),
      ],
    );
  }
}

class _ReturnOutputFormatCard extends StatelessWidget {
  const _ReturnOutputFormatCard();

  @override
  Widget build(BuildContext context) {
    return LabeledCard(
      title: 'Return Output Format',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ReturnOutputControls(),
          ],
        ),
      ),
    );
  }
}

class _ReturnOutputControls extends StatelessWidget {
  const _ReturnOutputControls();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: const [
        OscPathSegment(
          segment: 'resolution',
          child: OscValueLabel(label: 'Resolution'),
        ),
        OscPathSegment(
          segment: 'framerate',
          child: OscValueLabel(
            label: 'Framerate',
            defaultValue: '0.0',
          ),
        ),
        _ColorspaceDropdown(),
        _ChromaSubsamplingDropdown(),
        _BitDepthDropdown(),
      ],
    );
  }
}

class _ReturnOutputPictureCard extends StatelessWidget {
  const _ReturnOutputPictureCard();

  @override
  Widget build(BuildContext context) {
    return const LabeledCard(
      title: 'Output Picture',
      child: Padding(
        padding: EdgeInsets.all(16),
        child: _ReturnOutputPictureControls(),
      ),
    );
  }
}

class _ReturnOutputPictureControls extends StatefulWidget {
  const _ReturnOutputPictureControls();

  @override
  State<_ReturnOutputPictureControls> createState() =>
      _ReturnOutputPictureControlsState();
}

class _ReturnOutputPictureControlsState
    extends State<_ReturnOutputPictureControls> {
  final _brightnessKey = GlobalKey<NumericSliderState>();
  final _contrastKey = GlobalKey<NumericSliderState>();
  final _saturationKey = GlobalKey<NumericSliderState>();
  final _hueKey = GlobalKey<NumericSliderState>();

  static const double _initialBrightness = 0.5;
  static const double _initialContrast = 0.5;
  static const double _initialSaturation = 0.5;
  static const double _initialHue = 0.0;

  Widget _buildRow({required Widget child}) {
    return SizedBox(
      height: 32,
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required String segment,
    required GlobalKey<NumericSliderState> sliderKey,
    required double initialValue,
    required RangeValues range,
    List<double>? detents,
    required int precision,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 90, child: Text(label)),
        SizedBox(
          height: 24,
          width: 72,
          child: OscPathSegment(
            segment: segment,
            child: NumericSlider(
              key: sliderKey,
              value: initialValue,
              range: range,
              detents: detents,
              precision: precision,
              onChanged: (_) {},
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            sliderKey.currentState?.setValue(initialValue, immediate: true);
          },
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(
            child: _buildSlider(
              label: 'Brightness',
              segment: 'brightness',
              sliderKey: _brightnessKey,
              initialValue: _initialBrightness,
              range: const RangeValues(0, 1),
              detents: const [0.0, 0.5, 1.0],
              precision: 3,
            ),
          ),
          _buildRow(
            child: _buildSlider(
              label: 'Contrast',
              segment: 'contrast',
              sliderKey: _contrastKey,
              initialValue: _initialContrast,
              range: const RangeValues(0, 1),
              detents: const [0.0, 0.5, 1.0],
              precision: 3,
            ),
          ),
          _buildRow(
            child: _buildSlider(
              label: 'Saturation',
              segment: 'saturation',
              sliderKey: _saturationKey,
              initialValue: _initialSaturation,
              range: const RangeValues(0, 1),
              detents: const [0.0, 0.5, 1.0],
              precision: 3,
            ),
          ),
          _buildRow(
            child: _buildSlider(
              label: 'Hue',
              segment: 'hue',
              sliderKey: _hueKey,
              initialValue: _initialHue,
              range: const RangeValues(-180, 180),
              detents: const [0.0],
              precision: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnOutputLutCard extends StatelessWidget {
  const _ReturnOutputLutCard();

  @override
  Widget build(BuildContext context) {
    return const LabeledCard(
      title: 'Output LUT',
      child: SizedBox(
        height: 400,
        child: Card(
          color: Color(0xFF1F1F1F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: OscPathSegment(
              segment: 'lut',
              child: LUTEditor(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorspaceDropdown extends StatelessWidget {
  const _ColorspaceDropdown();

  @override
  Widget build(BuildContext context) {
    return OscDropdown<String>(
      label: 'Colorspace',
      displayLabel: 'Colorspace',
      pathSegment: 'colorspace',
      items: ReturnPage._colorspaces,
      defaultValue: ReturnPage._colorspaces.first,
    );
  }
}

class _ChromaSubsamplingDropdown extends StatelessWidget {
  const _ChromaSubsamplingDropdown();

  @override
  Widget build(BuildContext context) {
    return OscDropdown<String>(
      label: 'Chroma Subsampling',
      displayLabel: 'Chroma Subsampling',
      pathSegment: 'chroma_subsampling',
      items: ReturnPage._subsamplings,
      defaultValue: ReturnPage._subsamplings.first,
    );
  }
}

class _BitDepthDropdown extends StatelessWidget {
  const _BitDepthDropdown();

  @override
  Widget build(BuildContext context) {
    return OscDropdown<int>(
      label: 'Bit Depth',
      displayLabel: 'Bit Depth',
      pathSegment: 'bit_depth',
      items: ReturnPage._bitDepths,
      defaultValue: ReturnPage._bitDepths.first,
    );
  }
}
