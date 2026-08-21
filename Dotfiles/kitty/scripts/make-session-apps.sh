#!/usr/bin/env bash
# Builds one small macOS app bundle per dedicated kitty session, so each one
# shows up in Cmd-Tab under its own name and icon instead of five identical
# "kitty" entries. Reads kitty/session-apps.conf; writes to
# ~/Applications/Kitty Sessions/<App Name>.app.
#
# Safe to re-run at any time - each bundle is rebuilt from scratch.
# You MUST re-run it after `brew upgrade kitty`, see "Upgrades" below.
#
# WHY A WRAPPER BUNDLE AT ALL
# Cmd-Tab switches applications, not windows, and the name it shows comes from
# the bundle's CFBundleName - there is no per-process override. All the
# dedicated instances executed /Applications/kitty.app, so LaunchServices
# listed them as five indistinguishable "kitty" entries (confirmed with
# `lsappinfo list`). A per-session bundle is the only way to give them
# distinct names there.
#
# The layout below is copied from kitty's own kitty-quick-access.app, which
# lives inside kitty.app/Contents and does exactly this: own Info.plist,
# everything heavy symlinked back to the real bundle. Cost is ~460 KB each.
#
# WHY THE EXECUTABLE IS A COPY, NOT A SYMLINK
# Contents/MacOS/<App Name> must be a real copy of kitty's launcher binary.
# Symlinking it there instead makes the bundle fail to launch outright with
# "_LSOpenURLsWithCompletionHandler() failed ... error -54" (confirmed
# empirically) - which is presumably why kitty copies the binary for its own
# quick-access bundle rather than linking it. Everything else (Frameworks,
# each entry in Resources, the kitty and kitten binaries the launcher
# re-executes) IS symlinked, so it tracks the real install.
#
# UPGRADES
# Because of that copy, a kitty upgrade leaves each bundle running an old
# launcher against new Frameworks/Resources. Re-run this script after
# `brew upgrade kitty` to refresh them.
#
# STRIPPED PLIST KEYS
# kitty's Info.plist registers it as a handler for .sh/.command/folders and
# for file/ftp/git/gopher/... URL schemes, and exports a Services menu entry.
# Inheriting those would add five bogus entries to every "Open With" menu and
# have them fight over URL schemes, so they're removed from each wrapper.
# CFBundleIconName is removed too: it points at the "kitty" image in the
# symlinked Assets.car and takes precedence over CFBundleIconFile, so leaving
# it in would silently override the per-session icon we just generated.
set -euo pipefail

kitty_app="/Applications/kitty.app"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
conf="$here/../session-apps.conf"
dest_dir="$HOME/Applications/Kitty Sessions"

[[ -d "$kitty_app" ]] || { echo "error: $kitty_app not found" >&2; exit 1; }
[[ -r "$conf" ]] || { echo "error: $conf not found" >&2; exit 1; }

mkdir -p "$dest_dir"

# Icon sizes required by iconutil for a complete .icns.
iconset_specs=(
  "16 icon_16x16.png"      "32 icon_16x16@2x.png"
  "32 icon_32x32.png"      "64 icon_32x32@2x.png"
  "128 icon_128x128.png"   "256 icon_128x128@2x.png"
  "256 icon_256x256.png"   "512 icon_256x256@2x.png"
  "512 icon_512x512.png"   "1024 icon_512x512@2x.png"
)

built=0
wanted=()
while IFS='|' read -r glob app_name letter rgb; do
  # Skip comments and blank lines.
  [[ -z "${glob// }" || "${glob:0:1}" == "#" ]] && continue

  slug="$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  app="$dest_dir/$app_name.app"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

  # Heavy shared parts: symlinked, so they follow the real install.
  ln -s "$kitty_app/Contents/Frameworks" "$app/Contents/Frameworks"
  # Resources is symlinked entry-by-entry rather than wholesale, because the
  # generated .icns has to live inside it alongside kitty's own resources.
  for res in "$kitty_app/Contents/Resources/"*; do
    ln -s "$res" "$app/Contents/Resources/$(basename "$res")"
  done
  ln -s "$kitty_app/Contents/MacOS/kitty"  "$app/Contents/MacOS/kitty"
  ln -s "$kitty_app/Contents/MacOS/kitten" "$app/Contents/MacOS/kitten"

  # The one real copy - see "WHY THE EXECUTABLE IS A COPY" above.
  cp "$kitty_app/Contents/MacOS/kitty" "$app/Contents/MacOS/$app_name"

  # Icon: render, slice into an iconset, compile to .icns.
  # shellcheck disable=SC2086 # rgb is three space-separated args on purpose
  # (>/dev/null: osascript echoes the script's last value, a bare "true")
  osascript -l JavaScript "$here/make-session-icon.js" "$letter" $rgb "$tmp/icon.png" >/dev/null
  mkdir -p "$tmp/icon.iconset"
  for spec in "${iconset_specs[@]}"; do
    sips -z "${spec%% *}" "${spec%% *}" "$tmp/icon.png" \
      --out "$tmp/icon.iconset/${spec#* }" >/dev/null
  done
  iconutil -c icns "$tmp/icon.iconset" -o "$app/Contents/Resources/$slug.icns"

  # Identity.
  plist="$app/Contents/Info.plist"
  cp "$kitty_app/Contents/Info.plist" "$plist"
  for key in CFBundleName CFBundleDisplayName CFBundleExecutable; do
    plutil -replace "$key" -string "$app_name" "$plist"
  done
  plutil -replace CFBundleIdentifier -string "net.kovidgoyal.kitty.session.$slug" "$plist"
  plutil -replace CFBundleIconFile -string "$slug" "$plist"
  for key in CFBundleIconName CFBundleDocumentTypes CFBundleURLTypes NSServices; do
    plutil -remove "$key" "$plist" >/dev/null 2>&1 || true
  done

  # Ad-hoc signature: the copied launcher's original signature does not cover
  # this bundle's Info.plist, so re-sign or macOS may refuse to launch it.
  codesign --force --sign - "$app" >/dev/null 2>&1

  rm -rf "$tmp"
  trap - EXIT
  wanted+=("$app_name")
  built=$((built + 1))
  printf '  built %-14s -> %s\n' "$glob" "$app"
done < "$conf"

# Drop bundles for sessions that were renamed or removed from the conf -
# otherwise renaming e.g. Mail -> Neomutt leaves the old Mail.app behind and
# it keeps showing up in Cmd-Tab and Spotlight forever. Only bundles carrying
# our own identifier prefix are ever deleted, so anything else the user keeps
# in this folder is left strictly alone.
shopt -s nullglob
for existing in "$dest_dir"/*.app; do
  keep=0
  for w in ${wanted[@]+"${wanted[@]}"}; do
    [[ "$existing" == "$dest_dir/$w.app" ]] && { keep=1; break; }
  done
  [[ "$keep" == "1" ]] && continue
  id="$(plutil -extract CFBundleIdentifier raw -o - "$existing/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$id" == net.kovidgoyal.kitty.session.* ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -u "$existing" >/dev/null 2>&1 || true
    rm -rf "$existing"
    printf '  removed stale  -> %s\n' "$existing"
  fi
done

# Nudge LaunchServices so the new/changed bundles are picked up without a
# logout; without this a rebuilt bundle can keep showing its previous name.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$dest_dir"/*.app >/dev/null 2>&1 || true

echo "built $built session app(s) in $dest_dir"
