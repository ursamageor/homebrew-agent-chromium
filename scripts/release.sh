#!/bin/bash
# Point Casks/agent-chromium.rb at the built zips and, with --publish, upload them as a release.
#
#   scripts/release.sh            update the cask's version and sha256s; show what would be published
#   scripts/release.sh --publish  also create the GitHub release v<version> holding both zips
#
# Takes the newest version with zips in dist/ (Agent-Chromium-<version>-{arm64,x86_64}.zip from
# scripts/build-app.sh). The release goes to the repo named in the cask's url. Publish before
# pushing the cask: the pushed cask points users at the release's files.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cask="$repo/Casks/agent-chromium.rb"
out="$repo/dist"
APP_NAME="Agent-Chromium"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

publish=0
case "${1:-}" in
  --publish) publish=1 ;;
  "") ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

version="$(find "$out" -maxdepth 1 -name "$APP_NAME-*.zip" -exec basename {} .zip \; 2>/dev/null \
  | sed -E "s/^$APP_NAME-(.*)-(arm64|x86_64)$/\\1/" | sort -uV | tail -n 1)"
[ -n "$version" ] || die "no $APP_NAME-*.zip in $out (run scripts/build-app.sh)"
upstream_version="${version%_*}"   # without our _<revision>

zips=()
for arch in arm64 x86_64; do
  zip="$out/$APP_NAME-$version-$arch.zip"
  [ -f "$zip" ] && [ -f "$zip.sha256" ] || die "missing $zip (run scripts/build-app.sh)"
  zips+=("$zip")
done
arm="$(cut -d' ' -f1 "${zips[0]}.sha256")"
intel="$(cut -d' ' -f1 "${zips[1]}.sha256")"

sed -i '' \
  -e "s|^  version .*|  version \"$version\"|" \
  -e "s|^\(  sha256 arm: *\)\"[^\"]*\"|\1\"$arm\"|" \
  -e "s|^\( *intel: *\)\"[^\"]*\"|\1\"$intel\"|" \
  "$cask"
echo "cask: version $version, arm64 $arm, x86_64 $intel"

gh_repo="$(sed -nE 's|^  url "https://github.com/([^/]+/[^/]+)/releases/.*|\1|p' "$cask")"
[ -n "$gh_repo" ] || die "cannot read the GitHub repo from the cask url"
tag="v$version"

# Release notes: what went into this build, from the locks.
notes="ungoogled-chromium $upstream_version"
for lock in "$repo"/extensions/*.lock; do
  NAME="" VERSION=""
  # shellcheck disable=SC1090
  . "$lock"
  notes+=", $NAME $VERSION"
done

if [ "$publish" -eq 0 ]; then
  echo "dry run; with --publish: gh release create $tag -R $gh_repo (${zips[*]##*/})"
  echo "notes: $notes"
  exit 0
fi

command -v gh >/dev/null 2>&1 || die "missing tool: gh"
gh release view "$tag" -R "$gh_repo" >/dev/null 2>&1 \
  && die "release $tag already exists in $gh_repo; rebuild with scripts/build-app.sh --revision <n>"
gh release create "$tag" "${zips[@]}" -R "$gh_repo" --title "$APP_NAME $version" \
  --notes "Built from $notes."
echo "published $tag; now commit and push $cask"
