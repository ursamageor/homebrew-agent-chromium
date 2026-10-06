#!/bin/bash
# Build Agent-Chromium.app from an ungoogled-chromium DMG.
#
#   scripts/build-app.sh [--arch arm64|x86_64|all] [--version <ver>] [--revision <n>] [--out <dir>]
#                        [--force]
#   scripts/build-app.sh --dmg <path> [--arch <arch>] [--version <ver>]   (try a local DMG)
#   scripts/build-app.sh --cask-only                    (regenerate the dev cask from the zips)
#
# The input is the latest release of ungoogled-chromium-macos on GitHub (or --version <ver>, an
# upstream tag like 154.0.8037.57-1.1), read through `gh`. Each DMG is checked against the sha256
# GitHub records for it and against upstream's Developer ID signature before anything is changed.
# --dmg skips the download and the checksum, never the signature check. Default arch: all.
#
# --revision <n> re-releases the same upstream build with changes of ours: the package version
# becomes <ver>_<n> (0, the default, gives plain <ver>).
#
# A zip is only rebuilt when its inputs changed (upstream DMG, version, and every repo file that
# goes into the app, this script included); otherwise the existing zip, and so its checksum, is
# kept. Rebuilds never produce the same bytes. --force rebuilds anyway.
#
# Output per arch: <out>/Agent-Chromium-<version>-<arch>.zip and its .sha256. Then
# <out>/agent-chromium-dev.rb, a copy of the cask pointing at the local zips (installable from the
# local dev tap, see below). scripts/release.sh publishes the zips and updates the real cask.
#
# Steps: copy the app out of the DMG, rename it, swap the main executable for the launcher stub,
# add launcher script + preferences + extensions, patch Info.plist, ad-hoc sign, zip.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="Agent-Chromium"
BUNDLE_ID="org.agent-chromium.browser"
PRODUCT_DIR="Agent-Chromium"          # CrProductDirName: ~/Library/{Application Support,Caches}/<this>
ARCHES=(arm64 x86_64)
UPSTREAM_REPO="ungoogled-software/ungoogled-chromium-macos"
UPSTREAM_TEAM_ID="B9A88FL5XJ"         # Developer ID team that signs the upstream app

dmg=""
arch=""
upstream_version=""   # --version: an upstream tag; default the latest release
revision=0
out="$repo/dist"
build="$repo/build"
cask_only=0   # --cask-only: regenerate the dev cask from existing zips, skip the app build
no_cask=0     # --no-cask: internal, set for the per-arch runs of --arch all
force=0       # --force: rebuild even when the inputs are unchanged

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg)       dmg="$2"; shift 2 ;;
    --arch)      arch="$2"; shift 2 ;;
    --version)   upstream_version="$2"; shift 2 ;;
    --revision)  revision="$2"; shift 2 ;;
    --out)       out="$2"; shift 2 ;;
    --cask-only) cask_only=1; shift ;;
    --no-cask)   no_cask=1; shift ;;
    --force)     force=1; shift ;;
    -h|--help)   usage ;;
    *)           die "unknown argument: $1" ;;
  esac
done
[[ "$revision" =~ ^[0-9]+$ ]] || die "--revision takes a number"
mkdir -p "$out" && out="$(cd "$out" && pwd)"   # absolute: file:// URLs, checks run from inside it

for tool in hdiutil ditto plutil codesign lipo xattr cc curl shasum unzip zip od; do need "$tool"; done

# Dev cask: the real cask with version, both sha256s, and a file:// URL pointing at the local
# zips (an arch not built locally gets a zero checksum). Homebrew only loads casks from a tap, so
# it is also copied into the local dev tap when that exists
# (`brew tap-new local/agent-chromium --no-git && brew trust local/agent-chromium`).
zip_sha256() {
  local f="$out/$APP_NAME-$version-$1.zip.sha256"
  if [ -f "$f" ]; then cut -d' ' -f1 "$f"; else printf '%064d' 0; fi
}
write_dev_cask() {
  local dev_cask="$out/agent-chromium-dev.rb" arm intel
  arm="$(zip_sha256 arm64)"
  intel="$(zip_sha256 x86_64)"
  [ "$arm$intel" != "$(printf '%0128d' 0)" ] || die "no $APP_NAME-$version-*.zip in $out (run a build first)"
  sed -e "s|^  version .*|  version \"$version\"|" \
      -e "s|^\(  sha256 arm: *\)\"[^\"]*\"|\1\"$arm\"|" \
      -e "s|^\( *intel: *\)\"[^\"]*\"|\1\"$intel\"|" \
      -e "s|^  url .*|  url \"file://$out/$APP_NAME-#{version}-#{arch}.zip\"|" \
      "$repo/Casks/agent-chromium.rb" > "$dev_cask"

  local dev_tap install_hint
  dev_tap="$(brew --repository local/agent-chromium 2>/dev/null || true)"
  if [ "$out" != "$repo/dist" ]; then
    install_hint="brew install --cask $dev_cask   (the dev tap only follows builds into dist/)"
  elif [ -n "$dev_tap" ] && [ -d "$dev_tap" ]; then
    mkdir -p "$dev_tap/Casks"
    cp "$dev_cask" "$dev_tap/Casks/agent-chromium.rb"
    # The URL (hence brew's cache filename) is the same for every rebuild of one version; a
    # stale cached copy would fail the checksum on reinstall.
    local cached
    cached="$(brew --cache --cask local/agent-chromium/agent-chromium 2>/dev/null || true)"
    [ -n "$cached" ] && [ -f "$cached" ] && rm -f "$cached"
    install_hint="brew install --cask local/agent-chromium/agent-chromium   # or: brew reinstall --cask …"
  else
    install_hint="brew tap-new local/agent-chromium --no-git && brew trust local/agent-chromium && re-run"
  fi
  printf '  arm64:    %s\n  x86_64:   %s\n  dev cask: %s\n' "$arm" "$intel" "$dev_cask" >&2
  printf '\nInstall locally with:\n  %s\n' "$install_hint" >&2
}

if [ "$cask_only" -eq 1 ]; then
  # The newest version that has zips in <out>.
  version="$(find "$out" -maxdepth 1 -name "$APP_NAME-*.zip" -exec basename {} .zip \; 2>/dev/null \
    | sed -E "s/^$APP_NAME-(.*)-(arm64|x86_64)$/\1/" | sort -uV | tail -n 1)"
  [ -n "$version" ] || die "no $APP_NAME-*.zip in $out (run a build first)"
  log "Regenerating the dev cask for $version"
  write_dev_cask
  exit 0
fi

# --- Upstream release ---------------------------------------------------------------------------
# Resolved once for --arch all and handed to the per-arch runs, so both use the same release even
# if a new one appears mid-build. GitHub has recorded asset digests since mid-2025.
if [ -z "$dmg" ]; then
  need gh
  release="$(gh release view ${upstream_version:+"$upstream_version"} -R "$UPSTREAM_REPO" \
    --json tagName,assets --jq '.tagName, (.assets[] | "\(.name) \(.digest // "")")')" \
    || die "cannot read the ${upstream_version:-latest} release of $UPSTREAM_REPO"
  upstream_version="$(head -n 1 <<<"$release")"
elif [ -z "$upstream_version" ]; then
  # Upstream DMG names look like ungoogled-chromium_154.0.8037.57-1.1_arm64-macos.dmg
  upstream_version="$(basename "$dmg" | sed -nE 's/.*ungoogled-chromium_([0-9.]+-[0-9.]+)_.*/\1/p')"
  [ -n "$upstream_version" ] || die "cannot derive the version from $(basename "$dmg"); pass --version"
fi
version="$upstream_version"
[ "$revision" -eq 0 ] || version+="_$revision"

# --- One build per arch -------------------------------------------------------------------------
if [ -z "$dmg" ] && [ "${arch:-all}" = all ]; then
  log "ungoogled-chromium $upstream_version -> $APP_NAME $version"
  pass=()
  [ "$force" -eq 0 ] || pass+=(--force)
  for a in "${ARCHES[@]}"; do
    "$0" --arch "$a" --version "$upstream_version" --revision "$revision" --out "$out" --no-cask \
      ${pass[@]+"${pass[@]}"}
  done
  write_dev_cask
  exit 0
fi
[ -n "$arch" ] || arch="$(uname -m)"
case "$arch" in
  arm64|x86_64) ;;
  *) die "unknown arch: $arch (arm64, x86_64 or all)" ;;
esac

# --- Source DMG ---------------------------------------------------------------------------------
digest=""
if [ -z "$dmg" ]; then
  dmg="$build/downloads/ungoogled-chromium_${upstream_version}_${arch}-macos.dmg"
  digest="$(awk -v n="$(basename "$dmg")" '$1 == n { print $2 }' <<<"$release")"
  [[ "$digest" == sha256:* ]] || die "release $upstream_version has no $(basename "$dmg") with a sha256 digest"
  dmg_sha256="${digest#sha256:}"
else
  [ -f "$dmg" ] || die "DMG not found: $dmg"
  dmg_sha256="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
fi

app="$build/$arch/$APP_NAME.app"
contents="$app/Contents"
zip_path="$out/$APP_NAME-$version-$arch.zip"

# --- Skip when nothing changed ------------------------------------------------------------------
# The fingerprint of everything that goes into the zip. Kept next to the zip (.inputs) and in
# build/<arch>/ (whose app the smoke test runs). Not covered: the compiler and macOS tools.
inputs="$(
  {
    printf 'version %s\narch %s\ndmg %s\n' "$version" "$arch" "$dmg_sha256"
    cd "$repo" && find scripts/build-app.sh launcher prefs skills extensions licenses THIRD_PARTY.md \
      -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256
  } | shasum -a 256 | cut -d' ' -f1
)"
if [ "$force" -eq 0 ] && [ "$(cat "$zip_path.inputs" 2>/dev/null)" = "$inputs" ] \
   && (cd "$out" && shasum -a 256 -c "$zip_path.sha256" >/dev/null 2>&1); then
  log "$APP_NAME $version ($arch): inputs unchanged, keeping $zip_path (--force rebuilds)"
  if [ "$(cat "$build/$arch/inputs" 2>/dev/null)" != "$inputs" ]; then
    log "Unpacking it into $build/$arch"
    rm -rf "$app"
    mkdir -p "$build/$arch"
    ditto -x -k "$zip_path" "$build/$arch"
    printf '%s\n' "$inputs" > "$build/$arch/inputs"
  fi
  [ "$no_cask" -eq 1 ] || write_dev_cask
  exit 0
fi

if [ -n "$digest" ]; then
  if [ ! -f "$dmg" ]; then
    log "Downloading ungoogled-chromium $upstream_version ($arch)"
    mkdir -p "$build/downloads"
    curl -fL --progress-bar -o "$dmg.part" \
      "https://github.com/$UPSTREAM_REPO/releases/download/$upstream_version/$(basename "$dmg")"
    mv "$dmg.part" "$dmg"
  fi
  printf '%s  %s\n' "$dmg_sha256" "$dmg" | shasum -a 256 -c - >/dev/null \
    || die "sha256 mismatch for $dmg (delete it to re-download)"
else
  log "Using local DMG $dmg: no checksum, signature still checked"
fi

log "Building $APP_NAME $version ($arch) from $(basename "$dmg")"

# --- Copy the app out of the DMG ---------------------------------------------------------------
mkdir -p "$build/$arch" "$out"
rm -rf "$app" "$build/$arch/inputs" "$zip_path.inputs"

mount="$(mktemp -d /tmp/agent-chromium-dmg.XXXXXX)"
hdiutil attach -nobrowse -readonly -quiet -mountpoint "$mount" "$dmg"
trap 'hdiutil detach -quiet "$mount" 2>/dev/null || true' EXIT
upstream="$mount/Chromium.app"
[ -d "$upstream" ] || die "no Chromium.app inside the DMG"
ditto "$upstream" "$app"
hdiutil detach -quiet "$mount"
trap - EXIT
rmdir "$mount" 2>/dev/null || true

# Our ad-hoc re-sign below replaces upstream's Developer ID signature, so users can no longer
# check where the browser came from; this is where it gets checked, on the copy we repackage:
# a valid signature over the whole bundle by a Developer ID Application certificate of
# upstream's team. Extended attributes are not signed; some upstream DMGs carry Finder info
# that --strict rejects, so they go first.
xattr -cr "$app"
requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
requirement+=" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
requirement+=" and certificate leaf[subject.OU] = \"$UPSTREAM_TEAM_ID\""
codesign --verify --deep --strict -R="$requirement" "$app" \
  || die "upstream app is not signed by Developer ID team $UPSTREAM_TEAM_ID"
upstream_archs="$(lipo -archs "$contents/MacOS/Chromium")"
[ "$upstream_archs" = "$arch" ] || die "upstream binary is '$upstream_archs', expected $arch"

# --- Launcher -----------------------------------------------------------------------------------
log "Installing the launcher"
[ -f "$contents/MacOS/Chromium" ] || die "unexpected bundle layout: no Contents/MacOS/Chromium"
mv "$contents/MacOS/Chromium" "$contents/MacOS/Chromium-bin"
cc -O2 -Wall -Wextra -arch arm64 -arch x86_64 -o "$contents/MacOS/Chromium" "$repo/launcher/launcher.c"

mkdir -p "$contents/Resources/agent-chromium"
install -m 0755 "$repo/launcher/launch.sh" "$contents/Resources/agent-chromium/launch.sh"
install -m 0755 "$repo/launcher/setup.sh" "$contents/Resources/agent-chromium/setup.sh"
install -m 0644 "$repo/prefs/initial_preferences.json" "$contents/Resources/agent-chromium/initial_preferences.json"
printf '%s\n' "$version" > "$contents/Resources/agent-chromium/VERSION"
# Notices for what the zip redistributes (GPL and MIT ask for the license texts to travel along).
install -m 0644 "$repo/THIRD_PARTY.md" "$contents/Resources/agent-chromium/THIRD_PARTY.md"
rm -rf "$contents/Resources/agent-chromium/licenses"
ditto "$repo/licenses" "$contents/Resources/agent-chromium/licenses"

# Agent skills, installed into the user's agents by setup.sh. Claude Desktop takes a .skill file
# (the skill folder zipped, folder at the top level) opened with the app; -X drops macOS metadata.
rm -rf "$contents/Resources/agent-chromium/skills"
ditto "$repo/skills" "$contents/Resources/agent-chromium/skills"
rm -f "$contents/Resources/agent-chromium/agent-chromium.skill"
(cd "$repo/skills" && zip -qrX "$contents/Resources/agent-chromium/agent-chromium.skill" agent-chromium -x '*/.*')

# --- Extensions ---------------------------------------------------------------------------------
# Each extensions/<name>.lock is a shell fragment: NAME, VERSION, URL, SHA256, and optionally
# ROOT (subdirectory inside the archive that holds manifest.json) and KEY (public key written into
# manifest.json, which fixes the extension ID).
crx_to_zip() {  # CRX3 = "Cr24" + u32 version + u32 header length + header + zip
  local crx="$1" zip="$2" header_len
  [ "$(head -c 4 "$crx")" = "Cr24" ] || die "not a CRX file: $crx"
  header_len="$(od -An -t u4 -j 8 -N 4 "$crx" | tr -d ' ')"
  tail -c +$((12 + header_len + 1)) "$crx" > "$zip"
}

ext_root="$contents/Resources/extensions"
mkdir -p "$ext_root" "$build/downloads"
for lock in "$repo"/extensions/*.lock; do
  [ -f "$lock" ] || continue
  NAME="" VERSION="" URL="" SHA256="" ROOT="" KEY=""
  # shellcheck disable=SC1090
  . "$lock"
  [ -n "$NAME" ] && [ -n "$VERSION" ] && [ -n "$URL" ] && [ -n "$SHA256" ] || die "incomplete lock: $lock"
  log "Extension $NAME $VERSION"

  archive="$build/downloads/$NAME-$VERSION.${URL##*.}"
  [ -f "$archive" ] || curl -fsSL -o "$archive" "$URL"
  printf '%s  %s\n' "$SHA256" "$archive" | shasum -a 256 -c - >/dev/null \
    || die "sha256 mismatch for $archive"

  zip="$archive"
  case "$archive" in
    *.crx) zip="${archive%.crx}.zip"; crx_to_zip "$archive" "$zip" ;;
  esac

  dest="$ext_root/$NAME"
  rm -rf "$dest"
  mkdir -p "$dest"
  unzip -q -o "$zip" -d "$dest"
  if [ -n "$ROOT" ]; then
    [ -f "$dest/$ROOT/manifest.json" ] || die "$NAME: no manifest.json under $ROOT"
    tmp="$dest.tmp"; mv "$dest/$ROOT" "$tmp"; rm -rf "$dest"; mv "$tmp" "$dest"
  fi
  [ -f "$dest/manifest.json" ] || die "$NAME: manifest.json not at the archive root; set ROOT in $lock"
  # Chromium refuses to load an unpacked extension that contains a reserved "_metadata" dir.
  rm -rf "$dest/_metadata"
  if [ -n "$KEY" ]; then
    plutil -replace key -string "$KEY" "$dest/manifest.json" || die "$NAME: could not add key to manifest.json"
  fi
done

# --- Identity -----------------------------------------------------------------------------------
log "Patching Info.plist"
plist="$contents/Info.plist"
plutil -replace CFBundleIdentifier  -string "$BUNDLE_ID"   "$plist"
plutil -replace CFBundleName        -string "$APP_NAME"    "$plist"
plutil -replace CFBundleDisplayName -string "$APP_NAME"    "$plist"
plutil -replace CrProductDirName    -string "$PRODUCT_DIR" "$plist"

# --- Sign ---------------------------------------------------------------------------------------
# Editing Info.plist and the main executable broke the upstream Developer ID signature, so the
# bundle is re-signed ad-hoc. See the isolation note for what that costs.
log "Signing (ad-hoc)"
xattr -cr "$app"
codesign --force --deep --sign - "$app" 2>&1 | grep -v 'replacing existing signature' >&2 || true
codesign --verify --deep --strict "$app" || die "signature verification failed"

# --- Package ------------------------------------------------------------------------------------
log "Zipping to $zip_path"
rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
printf '%s  %s\n' "$(shasum -a 256 "$zip_path" | cut -d' ' -f1)" "$(basename "$zip_path")" \
  > "$zip_path.sha256"
printf '%s\n' "$inputs" | tee "$zip_path.inputs" > "$build/$arch/inputs"

log "Done: $zip_path"
[ "$no_cask" -eq 1 ] || write_dev_cask
