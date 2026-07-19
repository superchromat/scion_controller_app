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

# Rewrite just the version line, preserving everything else.
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: ${VERSION}+${BUILD}/" pubspec.yaml
else
  sed -i "s/^version: .*/version: ${VERSION}+${BUILD}/" pubspec.yaml
fi

echo "set_version: ${VERSION}+${BUILD}"
echo "             tag ${TAG}, +${COMMITS} commit(s), ${SHA}${DIRTY}"
