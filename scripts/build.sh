#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$root/dist/Tilda.app}"
case "$output" in /*.app) ;; *) echo 'Output must be an absolute .app path.' >&2; exit 64 ;; esac
work="$(mktemp -d "${TMPDIR:-/tmp}/tilda-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
export CLANG_MODULE_CACHE_PATH="$work/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$work/modules"
cd "$root"
options=(
  -c release --build-system native --disable-sandbox
  --scratch-path "$work/build" --cache-path "$work/cache"
  --config-path "$work/config" --security-path "$work/security"
  -Xswiftc -gnone
  -Xswiftc -file-prefix-map -Xswiftc "$root=/src/Tilda"
  -Xswiftc -file-prefix-map -Xswiftc "$work=/build"
  -Xcc "-ffile-prefix-map=$root=/src/Tilda"
  -Xcc "-ffile-prefix-map=$work=/build"
)
swift build "${options[@]}"
binaries="$(swift build "${options[@]}" --show-bin-path)"
app="$work/Tilda.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$binaries/Tilda" "$app/Contents/MacOS/Tilda"
cp Resources/Info.plist "$app/Contents/Info.plist"
for resource in "$binaries"/*.bundle; do
  if [ -d "$resource" ]; then
    ditto --norsrc --noextattr --noqtn "$resource" "$app/Contents/Resources/$(basename "$resource")"
  fi
done
swift scripts/make-icon.swift "$work/icon.iconset" "$app/Contents/Resources/Tilda.icns"
cp LICENSE "$app/Contents/Resources/Licenses/Tilda-LICENSE.txt"
cp Resources/Licenses/SwiftTerm-LICENSE.txt "$app/Contents/Resources/Licenses/SwiftTerm-LICENSE.txt"
strip -S -x "$app/Contents/MacOS/Tilda"
chmod -R u+w "$app"
xattr -cr "$app"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
if [ -e "$output" ]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$identifier" != 'com.tildamac.Tilda' ]; then
    echo 'The output contains a different app; it has not been replaced.' >&2
    exit 1
  fi
  chmod -R u+w "$output"
  rm -rf "$output"
fi
mkdir -p "$(dirname "$output")"
ditto --norsrc --noextattr --noqtn "$app" "$output"
codesign --verify --deep --strict "$output"
printf 'Built %s\n' "$output"
