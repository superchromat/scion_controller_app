import 'package:flutter/material.dart';

import 'grid.dart';
import 'osc_checkbox.dart';
import 'osc_rotary_knob.dart';
import 'osc_value_dropdown.dart';
import 'osc_widget_binding.dart';
import 'rotary_knob.dart';

class SendOverlaySource extends StatelessWidget {
  final int pageNumber;

  const SendOverlaySource({super.key, required this.pageNumber});

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'pip',
      child: const _SendOverlaySourceInner(),
    );
  }
}

class _SendOverlaySourceInner extends StatelessWidget {
  const _SendOverlaySourceInner();

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OscPathSegment(
                segment: 'enabled',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OscCheckbox(
                    initialValue: false,
                    label: 'Enable',
                    size: 20,
                  ),
                ),
              ),
            ),
            SizedBox(width: t.sm),
            Expanded(
              child: _FixedSourceBadge(),
            ),
            SizedBox(width: t.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Blend', style: t.textLabel),
                  SizedBox(height: t.xs),
                  OscPathSegment(
                    segment: 'opaque_blend',
                    child: OscValueDropdown<int>(
                      values: const [0, 1, 2],
                      labels: const ['Off', 'On', 'Reverse'],
                      initialValue: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: t.sm),
        Row(
          children: [
            Expanded(
              child: Center(
                child: OscPathSegment(
                  segment: 'alpha',
                  child: OscRotaryKnob(
                    initialValue: 1.0,
                    minValue: 0.0,
                    maxValue: 1.0,
                    format: '%.2f',
                    label: 'A',
                    defaultValue: 1.0,
                    size: t.knobSm,
                    labelStyle: t.textLabel,
                    snapConfig: const SnapConfig(
                      snapPoints: [0.0, 0.25, 0.5, 0.75, 1.0],
                      snapRegionHalfWidth: 0.02,
                      snapBehavior: SnapBehavior.hard,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: OscPathSegment(
                  segment: 'opaque_thres_y',
                  child: OscRotaryKnob(
                    initialValue: 0.0,
                    minValue: 0.0,
                    maxValue: 4095.0,
                    format: '%.0f',
                    label: 'Y',
                    defaultValue: 0.0,
                    size: t.knobSm,
                    labelStyle: t.textLabel,
                    preferInteger: true,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: OscPathSegment(
                  segment: 'opaque_thres_c',
                  child: OscRotaryKnob(
                    initialValue: 0.0,
                    minValue: 0.0,
                    maxValue: 255.0,
                    format: '%.0f',
                    label: 'C',
                    defaultValue: 0.0,
                    size: t.knobSm,
                    labelStyle: t.textLabel,
                    preferInteger: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FixedSourceBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Source', style: t.textLabel),
        SizedBox(height: t.xs),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs),
          decoration: BoxDecoration(
            color: const Color(0x22222222),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x55A0A0A0)),
          ),
          child: Text(
            'Send 2 (Fixed)',
            style: t.textValue,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
