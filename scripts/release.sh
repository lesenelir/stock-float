#!/bin/sh
# Build a universal app, zip it, and publish it as a GitHub release: scripts/release.sh 0.1.0
set -eu

cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release.sh <version>}
TAG="v$VERSION"

fail() {
  echo "$1" >&2
  exit 1
}

# The tag must point at a commit that is already on GitHub, so a release always matches public source.
[ -z "$(git status --porcelain)" ] || fail "Working tree is not clean"
[ "$(git branch --show-current)" = "master" ] || fail "Not on master"
git fetch --quiet --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || fail "master is not pushed"
if git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null; then
  fail "Tag $TAG already exists"
fi

swift test
VERSION="$VERSION" scripts/bundle.sh --universal

# ditto keeps the code signature intact; plain zip is not guaranteed to.
ZIP="build/StockFloat-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/StockFloat.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" \
  --title "StockFloat $VERSION" \
  --generate-notes \
  --notes "Universal build for Apple silicon and Intel, macOS 14 or later.

The app is not notarized, so macOS blocks the first launch. See \"First launch\" in the README.

SHA-256 of \`StockFloat-$VERSION.zip\`: \`$SHA\`"

echo "Released $TAG ($ZIP, sha256 $SHA)"
