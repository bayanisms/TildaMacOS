#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/tilda-dmg.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/image" "$root/dist"
bash "$root/scripts/build.sh" "$work/image/Tilda.app"
ln -s /Applications "$work/image/Applications"
xattr -cr "$work/image/Tilda.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/image/Tilda.app/Contents/Info.plist")"
architecture="$(lipo -archs "$work/image/Tilda.app/Contents/MacOS/Tilda" | tr ' ' '-')"
image="$root/dist/Tilda-$version-$architecture.dmg"
hdiutil create -srcfolder "$work/image" -volname Tilda -fs HFS+ -format UDZO -nospotlight -srcowners off -anyowners -ov "$image"
xattr -c "$image"
hdiutil verify "$image"
printf 'Created %s\n' "$image"
