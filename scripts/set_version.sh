#!/usr/bin/env bash
#
# Stamps pubspec.yaml's version from git, so the shipped version is a product of
# building rather than something anyone has to remember to bump.
#
#   version: <MAJOR.MINOR.PATCH>+<build>
#            ^ from the latest git tag        ^ minutes since the Unix epoch
#
# The semantic part only changes when you deliberately tag a release:
#     git tag -a v1.1.0 -m "1.1.0" && git push --tags
#
# The build part is derived from the clock, which satisfies the one hard rule
# both stores enforce: it must strictly increase on every upload. Minutes (not
# seconds, and not YYMMDDHHMM) because Android's versionCode is a signed 32-bit
# int — 2,147,483,647 is the ceiling:
#     YYMMDDHHMM  2,607,190,023  overflows
#     epoch secs  1,784,000,000  fits, but only until 2038
#     epoch mins     29,733,333  fits, ~4000 years of headroom
#
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"

if [[ -z "$TAG" ]]; then
  echo "set_version: no git tag found." >&2
  echo "             Create the first one with:  git tag -a v1.0.0 -m '1.0.0'" >&2
  exit 1
fi

VERSION="${TAG#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "set_version: tag '$TAG' is not MAJOR.MINOR.PATCH (pubspec and Apple both require three numeric components)." >&2
  exit 1
fi

BUILD=$(( $(date +%s) / 60 ))

# Traceability for beta bug reports: how far past the tag, and whether the tree
# was dirty when built. Reported here rather than baked into the version, which
# has to stay strictly numeric.
COMMITS="$(git rev-list "${TAG}"..HEAD --count 2>/dev/null || echo 0)"
SHA="$(git rev-parse --short HEAD)"
DIRTY=""
git diff --quiet 2>/dev/null || DIRTY=" (dirty tree)"

# Portable in-place sed: BSD sed (macOS) requires an explicit backup suffix
# argument to -i; GNU sed (Linux, Git Bash on Windows) does not.
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Rewrite just the version line, preserving everything else.
sedi "s/^version: .*/version: ${VERSION}+${BUILD}/" pubspec.yaml

# Keep the Windows executable's version-info metadata in sync with the
# single source of truth in lib/about.dart. The .rc is a plain resource file
# and cannot import Dart, so without this it silently drifts from kCompany /
# kCopyrightYear (the drift about.dart's own comment warns against).
ABOUT="lib/about.dart"
RC="windows/runner/Runner.rc"
COMPANY="$(sed -n "s/^const String kCompany = '\(.*\)';.*/\1/p" "$ABOUT")"
YEAR="$(sed -n 's/^const int kCopyrightYear = \([0-9]*\);.*/\1/p' "$ABOUT")"
if [[ -z "$COMPANY" || -z "$YEAR" ]]; then
  echo "set_version: WARNING could not read kCompany/kCopyrightYear from ${ABOUT};" >&2
  echo "             leaving ${RC} untouched." >&2
elif [[ ! -f "$RC" ]]; then
  echo "set_version: WARNING ${RC} not found; skipping Windows metadata sync." >&2
else
  # Copyright string mirrors about.dart's `_copyright` exactly.
  COPYRIGHT="© ${YEAR} ${COMPANY}. All rights reserved."
  # Rewrites the content between the first pair of quotes after the value name,
  # leaving the trailing ` "\0"` intact. Escape sed-replacement metacharacters
  # (& \ and the | delimiter) so arbitrary company names substitute literally.
  rc_set() {
    local name="$1" esc
    esc="$(printf '%s' "$2" | sed -e 's/[&|\\]/\\&/g')"
    sedi "s|\(VALUE \"${name}\", \"\)[^\"]*\"|\1${esc}\"|" "$RC"
  }
  rc_set "CompanyName"   "$COMPANY"
  rc_set "LegalCopyright" "$COPYRIGHT"
  echo "set_version: windows metadata — ${COMPANY}, © ${YEAR}"
fi

echo "set_version: ${VERSION}+${BUILD}"
echo "             tag ${TAG}, +${COMMITS} commit(s), ${SHA}${DIRTY}"
