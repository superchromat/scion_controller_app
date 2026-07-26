#!/usr/bin/env bash
#
# Build → package the Windows app into a ready-to-send zip for beta testers.
# Output: build/scion-<version>-windows-x64.zip
#
# The zip contains a single top-level SCION_Controller/ folder; a tester unzips
# it anywhere and runs SCION_Controller.exe. No installer, no admin rights.
#
# Self-contained: windows/CMakeLists.txt bundles the Flutter engine, the plugin
# DLLs and the Visual C++ runtime (vcruntime140*.dll, msvcp140.dll) next to the
# exe, so it runs on a machine that has never had the VC++ Redistributable.
#
# NOT signed. On a tester's machine SmartScreen will show a blue
# "unknown publisher" warning; they click "More info" -> "Run anyway". To remove
# that warning you need a code-signing certificate (see the Windows distribution
# notes) — deliberately out of scope here.
#
# Run from Git Bash. Requires flutter on PATH and Windows PowerShell (for the
# zip step); both are present on a standard Flutter-on-Windows setup.
set -euo pipefail

APP_NAME="scion"
DIST_NAME="SCION_Controller"   # top-level folder name inside the zip

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RELEASE_DIR="build/windows/x64/runner/Release"

echo "==> Stamping version from git (and syncing Windows metadata)"
"$ROOT/scripts/set_version.sh"

echo "==> Building release"
flutter build windows --release

if [[ ! -f "$RELEASE_DIR/$DIST_NAME.exe" ]]; then
  echo "package_windows: expected $RELEASE_DIR/$DIST_NAME.exe not found." >&2
  echo "                 Did BINARY_NAME in windows/CMakeLists.txt change?" >&2
  exit 1
fi

# Version for the zip filename, read from the just-stamped pubspec.
# `0.9.1+29740952` -> `0.9.1-29740952` (`+` is legal in a filename but noisy).
VERSION_FULL="$(sed -n 's/^version: \(.*\)/\1/p' pubspec.yaml)"
VERSION="${VERSION_FULL/+/-}"
ZIP="build/${APP_NAME}-${VERSION}-windows-x64.zip"

# Stage under the distribution folder name so the zip has one clean root
# directory (SCION_Controller/...) rather than loose files.
STAGE="build/windows/_package"
rm -rf "$STAGE"
mkdir -p "$STAGE/$DIST_NAME"
cp -r "$RELEASE_DIR"/. "$STAGE/$DIST_NAME/"

echo "==> Zipping"
rm -f "$ZIP"
# Compress-Archive keeps the passed folder as the zip's root entry. Use Windows
# PowerShell rather than a `zip` binary, which Git Bash does not ship.
# Convert the bash-relative paths to what PowerShell expects.
SRC_WIN="$(cygpath -w "$STAGE/$DIST_NAME")"
ZIP_WIN="$(cygpath -w "$ROOT/$ZIP")"
powershell.exe -NoProfile -Command \
  "Compress-Archive -Path '$SRC_WIN' -DestinationPath '$ZIP_WIN' -Force"

rm -rf "$STAGE"

SIZE="$(du -h "$ZIP" | cut -f1)"
echo "==> Done: $ZIP  ($SIZE)"
echo "    Testers: unzip, run $DIST_NAME/$DIST_NAME.exe."
echo "    Unsigned — SmartScreen will warn (More info -> Run anyway)."
