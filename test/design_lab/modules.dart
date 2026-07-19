// Per-surface toolset inventory, encoded as modules.
//
// Mirrors what each real surface actually hosts (send_page.dart / return_page.dart):
//  • Send 1  — full rig (rotation, warp, color grade/field/posterize, rect-copy)
//  • Send 2/3 — reduced (no rotation, no warp, no grade/field/posterize, no rect-copy)
//  • Return  — capture domain (output format + ADC tuning) + shape/texture/color
//
// A module carries a title, a size-class hint (so layout engines can place by
// visual mass), and a content builder that emits the inner controls (NOT the
// card — the layout decides how to wrap it).
import 'package:flutter/material.dart';
import 'package:SCION_Controller/grid.dart';
import 'package:SCION_Controller/panel.dart';
import 'blocks.dart';

enum Size3 { small, wide, medium, tall, hero }

class LabModule {
  final String key;
  final String title;
  final Size3 size;
  final WidgetBuilder content;
  const LabModule(this.key, this.title, this.size, this.content);
}

// ── shared content builders ──────────────────────────────────────────────────
Widget _inputContent(BuildContext c, {int active = 1}) {
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
              child: LabDropdown('Source', 'HDMI 1', width: double.infinity)),
          SizedBox(width: t.md),
          for (var i = 1; i <= 4; i++) ...[
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: t.sm * 1.5,
                height: t.sm * 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == active
                      ? const Color(0xFF56C271)
                      : const Color(0xFF2A2A2C),
                  border: Border.all(color: const Color(0xFF3A3A3E)),
                ),
              ),
              SizedBox(height: t.xs * 0.5),
              Text('$i', style: t.textCaption),
            ]),
            SizedBox(width: t.sm),
          ],
        ]),
      ]);
}

Widget _shapeContent(BuildContext c,
    {bool rotation = false, bool crop = true}) {
  final knobs = <(String, double)>[
    ('Scale X', 0.7),
    ('Scale Y', 0.7),
    ('Pos X', 0.5),
    ('Pos Y', 0.5),
    if (rotation) ('Rotate', 0.5),
  ];
  final cropKnobs = <(String, double)>[
    ('Left', 0.1),
    ('Right', 0.1),
    ('Top', 0.1),
    ('Bottom', 0.1)
  ];
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KnobGridPanel('Transform', knobs, perRow: rotation ? 5 : 4),
        if (crop) ...[
          SizedBox(height: t.sm),
          KnobPanel('Crop', cropKnobs, knobSize: t.knobSm),
        ],
      ]);
}

Widget _warpContent(BuildContext c) {
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KnobPanel('Affine',
            const [('Shear', 0.5), ('Persp X', 0.5), ('Persp Y', 0.5)],
            bipolar: true, knobSize: t.knobSm),
        SizedBox(height: t.sm),
        Panel(
            title: 'LUT',
            child: Row(children: [
              Expanded(
                  child:
                      LabDropdown('Mesh', 'barrel_01', width: double.infinity)),
              SizedBox(width: t.md),
              LabToggle('On', on: true),
            ])),
      ]);
}

Widget _textureContent(BuildContext c) => KnobGridPanel(
    null,
    const [
      ('Blur H', 0.2),
      ('Blur V', 0.2),
      ('Sharpen', 0.4),
      ('Grain', 0.15),
      ('Bloom', 0.3),
      ('Vignette', 0.25)
    ],
    perRow: 3);

Widget _textContent(BuildContext c) {
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LabTextField('Overlay text…'),
        SizedBox(height: t.sm),
        Row(children: [
          Expanded(
              child: LabDropdown('Font', 'DIN Pro', width: double.infinity)),
        ]),
        SizedBox(height: t.sm),
        KnobPanel(null,
            const [('Size', 0.5), ('X', 0.5), ('Y', 0.5), ('Opacity', 0.8)],
            knobSize: t.knobSm),
      ]);
}

Widget _colorGrade(BuildContext c) => Panel(
      title: 'Grade',
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: const [
            LabWheel('Lift'),
            LabWheel('Gamma'),
            LabWheel('Gain'),
          ]),
    );

Widget _colorContent(BuildContext c,
    {bool grade = false, bool field = false, bool posterize = false}) {
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grade) ...[_colorGrade(c), SizedBox(height: t.sm)],
        KnobPanel(
            'Adjust',
            const [
              ('Sat', 0.6),
              ('Contrast', 0.55),
              ('Hue', 0.5),
              ('Temp', 0.5),
              ('Tint', 0.5)
            ],
            bipolar: true,
            knobSize: t.knobSm),
        SizedBox(height: t.sm),
        Panel(title: 'Primaries', child: const LabSwatchStrip(n: 6)),
        if (field) ...[
          SizedBox(height: t.sm),
          Panel(
              title: 'Color Field',
              child: Row(children: [
                Expanded(child: const LabSwatchStrip(n: 3)),
                SizedBox(width: t.md),
                LabKnob('Mix', value: 0.4, size: t.knobSm),
              ])),
        ],
        if (posterize) ...[
          SizedBox(height: t.sm),
          KnobPanel('Posterize', const [('Levels', 0.3), ('Dither', 0.2)],
              knobSize: t.knobSm),
        ],
      ]);
}

Widget _glitchContent(BuildContext c, {bool rectCopy = false}) {
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KnobPanel(
            'Displace',
            const [
              ('Amount', 0.3),
              ('Rate', 0.5),
              ('Seed', 0.6),
              ('Chroma', 0.4)
            ],
            knobSize: t.knobSm),
        if (rectCopy) ...[
          SizedBox(height: t.sm),
          KnobPanel('Rect Copy',
              const [('X', 0.5), ('Y', 0.5), ('W', 0.4), ('H', 0.4)],
              knobSize: t.knobSm),
        ],
      ]);
}

Widget _dacContent(BuildContext c) => KnobPanel(null,
    const [('Bright', 0.5), ('Contrast', 0.5), ('Black', 0.4), ('White', 0.7)],
    bipolar: false);

// ── Return-only content ──────────────────────────────────────────────────────
Widget _formatContent(BuildContext c) {
  final t = GridProvider.of(c);
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(
        flex: 4,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              LabValue('Resolution', '1920×1080', live: true),
              SizedBox(height: 10),
              LabValue('Framerate', '59.94', live: true),
            ])),
    SizedBox(width: t.md),
    Expanded(
        flex: 6,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LabDropdown('Colorspace', 'YUV', width: double.infinity),
          SizedBox(height: t.sm),
          LabDropdown('Chroma Subsampling', '4:2:2', width: double.infinity),
          SizedBox(height: t.sm),
          LabDropdown('Bit Depth', '10', width: double.infinity),
        ])),
  ]);
}

Widget _adcContent(BuildContext c) {
  final t = GridProvider.of(c);
  return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridRow(gutter: t.md, cells: [
          (
            span: 8,
            child: KnobPanel('DE Window',
                const [('X', 0.5), ('Y', 0.5), ('W', 0.6), ('H', 0.6)],
                knobSize: t.knobSm)
          ),
          (
            span: 4,
            child: KnobPanel('Offset', const [('H', 0.5), ('V', 0.5)],
                bipolar: true, knobSize: t.knobSm)
          ),
        ]),
        SizedBox(height: t.sm),
        GridRow(gutter: t.md, cells: [
          (
            span: 8,
            child: KnobPanel('Sync Adjust',
                const [('H Phase', 0.5), ('V Phase', 0.5), ('Coast', 0.4)],
                knobSize: t.knobSm)
          ),
          (
            span: 4,
            child: Panel(
                title: 'LLC Phase',
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  LabToggle('DLL', on: false),
                  SizedBox(width: t.md),
                  LabKnob('Phase', value: 0.3, size: t.knobSm),
                ]))
          ),
        ]),
        SizedBox(height: t.sm),
        Panel(
            title: 'ADC Anti-Alias Filter',
            child: Row(children: [
              LabToggle('Enable', on: true),
              SizedBox(width: t.lg),
              LabKnob('Cutoff MHz', value: 0.5, size: t.knobSm),
            ])),
        SizedBox(height: t.sm),
        Panel(
            title: 'Input Gain (AGC)',
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              LabToggle('AGC', on: true),
              SizedBox(width: t.lg),
              LabKnob('A·G', value: 0.5, size: t.knobSm),
              SizedBox(width: t.sm),
              LabKnob('B·B', value: 0.5, size: t.knobSm),
              SizedBox(width: t.sm),
              LabKnob('C·R', value: 0.5, size: t.knobSm),
            ])),
      ]);
}

// ── inventories ──────────────────────────────────────────────────────────────
List<LabModule> send1Modules() => [
      LabModule('input', 'Input Source', Size3.wide, (c) => _inputContent(c)),
      LabModule('shape', 'Shape', Size3.tall,
          (c) => _shapeContent(c, rotation: true)),
      LabModule('warp', 'Warp', Size3.medium, _warpContent),
      LabModule('texture', 'Texture', Size3.medium, _textureContent),
      LabModule('text', 'Text', Size3.medium, _textContent),
      LabModule('color', 'Color', Size3.hero,
          (c) => _colorContent(c, grade: true, field: true, posterize: true)),
      LabModule('glitch', 'Glitch', Size3.medium,
          (c) => _glitchContent(c, rectCopy: true)),
      LabModule('dac', 'DAC', Size3.wide, _dacContent),
    ];

List<LabModule> send23Modules() => [
      LabModule('input', 'Input Source', Size3.wide,
          (c) => _inputContent(c, active: 2)),
      LabModule('shape', 'Shape', Size3.medium,
          (c) => _shapeContent(c, rotation: false)),
      LabModule('texture', 'Texture', Size3.medium, _textureContent),
      LabModule('text', 'Text', Size3.medium, _textContent),
      LabModule('color', 'Color', Size3.medium, (c) => _colorContent(c)),
      LabModule('glitch', 'Glitch', Size3.medium, (c) => _glitchContent(c)),
      LabModule('dac', 'DAC', Size3.wide, _dacContent),
    ];

List<LabModule> returnModules() => [
      LabModule('format', 'Return Output Format', Size3.wide, _formatContent),
      LabModule('adc', 'ADC Adjustments', Size3.hero, _adcContent),
      LabModule('shape', 'Shape', Size3.medium,
          (c) => _shapeContent(c, rotation: false)),
      LabModule('texture', 'Texture', Size3.medium, _textureContent),
      LabModule(
          'color', 'Color', Size3.tall, (c) => _colorContent(c, grade: true)),
    ];

LabModule moduleByKey(List<LabModule> mods, String key) =>
    mods.firstWhere((m) => m.key == key);
