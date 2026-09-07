#!/usr/bin/env bash
set -euo pipefail

target="${1:?Usage: check-macos-bundle.sh <Rust target>}"
case "$target" in
  aarch64-apple-darwin) arch=arm64 ;;
  x86_64-apple-darwin) arch=x86_64 ;;
  *) echo "Unsupported macOS target: $target" >&2; exit 1 ;;
esac

bundle_root="src-tauri/target/$target/release/bundle"
dmg="$(find "$bundle_root/dmg" -maxdepth 1 -name '*.dmg' -type f -print -quit)"
test -n "$dmg"
hdiutil verify "$dmg"
mount_point="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mctier-smoke.XXXXXX")"
attached=false
cleanup() {
  if [[ "$attached" == true ]]; then hdiutil detach "$mount_point"; fi
  rmdir "$mount_point"
}
trap cleanup EXIT
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point"
attached=true
app="$(find "$mount_point" -maxdepth 1 -name '*.app' -type d -print -quit)"
test -n "$app"
plist="$app/Contents/Info.plist"
plutil -lint "$plist"
for key in NSMicrophoneUsageDescription NSCameraUsageDescription NSLocalNetworkUsageDescription; do
  test -n "$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")"
done
binary="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
for name in "$binary" easytier-core easytier-cli; do
  executable="$app/Contents/MacOS/$name"
  test -x "$executable"
  lipo "$executable" -verify_arch "$arch"
  codesign --verify --strict --verbose=2 "$executable"
done
codesign --verify --deep --strict --verbose=2 "$app"
entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null)"
grep -q 'com.apple.security.device.audio-input' <<<"$entitlements"

# Exercise the packaged sidecars without opening a tunnel or asking for root.
# This catches wrong architectures, missing dylibs and invalid executable modes.
"$app/Contents/MacOS/easytier-core" --version
"$app/Contents/MacOS/easytier-cli" --version
if [[ "${REQUIRE_NOTARIZATION:-false}" == true ]]; then
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi
