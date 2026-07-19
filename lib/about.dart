import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_button.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'panel.dart';

const String kCompany = 'Superchromat';
const int kCopyrightYear = 2026;

// ---------------------------------------------------------------------------
// TODO(legal): The text below is a placeholder, NOT reviewed licence terms.
//
// Before any public release, replace `_legalese` with wording from a lawyer.
// A boilerplate "AS IS" disclaimer lifted from an open-source licence is not
// appropriate here: SCION is paid hardware plus companion software sold
// internationally, and consumer-protection law in the EU/UK/AU limits which
// warranties can be disclaimed and how liability can be capped. What is needed
// is a short EULA covering: licence grant and restrictions, warranty
// disclaimer, limitation of liability, beta/pre-release terms, termination,
// and governing law.
// ---------------------------------------------------------------------------
const String _copyright = '© $kCopyrightYear $kCompany. All rights reserved.';

// NOTE: use ® only once a mark is actually registered in the relevant
// jurisdiction — asserting registration you don't hold is penalised in some
// countries. ™ is fine for unregistered marks.
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
    return LabeledCard(
      title: 'About',
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
                style: t.textBody.copyWith(
                    fontWeight: FontWeight.w400, color: Colors.white),
              ),
            ),
            SizedBox(height: t.sm),
            Text(_copyright, style: t.textBody),
            SizedBox(height: t.xs),
            Text(_trademarks, style: t.textBody),
            SizedBox(height: t.sm),
            Text(_warranty, style: t.textBody),
            SizedBox(height: t.md),
            Row(
              children: [
                AppButton(
                  label: 'Third-Party Licences',
                  icon: Icons.article_outlined,
                  dense: true,
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
