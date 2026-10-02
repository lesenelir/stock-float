#!/bin/sh
# Tag a version and push the tag; GitHub Actions then builds and publishes the release.
# Usage: scripts/release.sh 0.2.0
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

git tag "$TAG"
git push origin "$TAG"
echo "Pushed $TAG. The release workflow is building it: $(gh repo view --json url --jq .url)/actions"
