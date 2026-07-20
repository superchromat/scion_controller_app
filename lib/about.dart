import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_button.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'panel.dart';

const String kCompany = 'Superchromat Pty. Ltd. (AU)';
const int kCopyrightYear = 2026;

const String _copyright = '© $kCopyrightYear $kCompany. All rights reserved.';

const String _trademarks =
    'SCION™ and Superchromat™ are trademarks of $kCompany.';

const String _warranty =
    'This software is pre-release and is provided "as is", without warranty '
    'of any kind, express or implied. Interim terms pending final licence '
    'agreement.';

/// Reads the version stamped into the platform bundle by scripts/set_version.sh
/// (`<tag>+<epoch-minutes>`). Read at runtime rather than duplicated in a Dart
/// constant, which would silently drift from pubspec.yaml.
Future<String> appVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final v = info.version;
    final b = info.buildNumber;
    return b.isEmpty ? v : '$v  (build $b)';
  } catch (_) {
    return 'unknown version';
  }
}

/// Flutter's built-in licence page, covering the engine, every pub package and
/// every pub package.
void showScionLicensePage(BuildContext context, String version) {
  showLicensePage(
    context: context,
    applicationName: 'SCION Controller',
    applicationVersion: version,
    applicationLegalese: '$_copyright\n\n$_trademarks',
  );
}

/// Setup-page card showing the about/legal notices inline.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // LabeledCard gives its child no horizontal padding (it assumes a GridRow of
    // Panels, which bring their own). This card's content is plain text, so it
    // has to inset itself to line up with the card title.
    // One gap value between every row, so the notices read as an evenly set
    // block rather than ad-hoc groups. Anything other than `gap` here breaks it.
    final gap = SizedBox(height: t.xs);
    return LabeledCard(
      title: 'About',
      // A step darker than the standard card face: this is legal boilerplate,
      // and it should sit behind the controls above it rather than compete.
      baseColor: const Color(0xFF2B2B2F),
      child: CardBody(
        top: t.xs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FutureBuilder<String>(
              future: appVersionLabel(),
              builder: (context, snap) => Text(
                'SCION Controller  ${snap.data ?? '…'}  •  beta',
                // Must not be smaller than the prose it heads.
                style: t.textBody
                    .copyWith(fontWeight: FontWeight.w400, color: Colors.white),
              ),
            ),
            gap,
            Text(_copyright, style: t.textBody),
            gap,
            Text(_trademarks, style: t.textBody),
            gap,
            Text(_warranty, style: t.textBody),
            gap,
            Row(
              children: [
                // Full-size and label-only: it is the same kind of action as
                // Save / Load / Firmware Update, so it gets the same button.
                AppButton(
                  label: 'Third-Party Licences',
                  onPressed: () async =>
                      showScionLicensePage(context, await appVersionLabel()),
                ),
                SizedBox(width: t.sm),
                Expanded(
                  child: Text(
                    'Includes Flutter and bundled packages.',
                    style: t.textBody,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
