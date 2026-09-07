#!/usr/bin/env bash
# Gate the final Release job on the complete, versioned artifact set.
#
# Usage:
#   collect-release-artifacts.sh <version> [artifact-directory]
#
# The download-artifact step merges each matrix artifact into one directory;
# this script rejects missing, duplicated, stale, or unexpected files before
# GitHub Release is allowed to mutate repository state.

set -Eeuo pipefail

version="${1:-}"
artifact_dir="${2:-release-assets}"

if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "invalid release version: $version" >&2
  exit 2
fi
[[ -d "$artifact_dir" ]] || { echo "artifact directory does not exist: $artifact_dir" >&2; exit 1; }

expected=(
  "MCTier-${version}-windows-x86_64-unsigned.exe"
  "MCTier-${version}-linux-x86_64.AppImage"
  "MCTier-${version}-linux-x86_64.deb"
  "MCTier-${version}-macos-x86_64-adhoc.dmg"
  "MCTier-${version}-macos-arm64-adhoc.dmg"
  "MCTier-${version}-android-arm64-debug-signed.apk"
)

fail() {
  echo "release artifact gate failed: $*" >&2
  exit 1
}

sha256_command() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' shasum
  else
    fail "sha256sum or shasum is required"
  fi
}

for name in "${expected[@]}"; do
  file="$artifact_dir/$name"
  [[ -f "$file" && ! -L "$file" ]] || fail "missing or symlinked artifact: $name"
  [[ -s "$file" ]] || fail "empty artifact: $name"
  if LC_ALL=C grep -a -q 'MCTIER-CI-PLACEHOLDER-NOT-A-REAL-BINARY' "$file"; then
    fail "compile-only placeholder detected in $name"
  fi
done

# Every matrix job contributes exactly the file names above. This protects
# against accidentally publishing an old package left by download-artifact or
# an action that changed its output layout.
while IFS= read -r -d '' file; do
  name="${file##*/}"
  [[ "$name" == "SHA256SUMS" ]] && continue
  found=false
  for expected_name in "${expected[@]}"; do
    if [[ "$name" == "$expected_name" ]]; then
      found=true
      break
    fi
  done
  [[ "$found" == true ]] || fail "unexpected file in release-assets: $name"
done < <(find "$artifact_dir" -maxdepth 1 -type f -print0)

read_magic() {
  local file="$1" count="$2"
  dd if="$file" bs=1 count="$count" 2>/dev/null
}

windows_file="$artifact_dir/${expected[0]}"
[[ "$(read_magic "$windows_file" 2)" == MZ ]] || fail "Windows asset is not a PE executable"

appimage_file="$artifact_dir/${expected[1]}"
[[ "$(od -An -t x1 -N 4 "$appimage_file" | tr -d ' \n')" == 7f454c46 ]] \
  || fail "Linux AppImage is not an ELF executable"

deb_file="$artifact_dir/${expected[2]}"
[[ "$(read_magic "$deb_file" 7)" == '!<arch>' ]] || fail "Linux asset is not a Debian archive"

for name in "${expected[3]}" "${expected[4]}"; do
  dmg="$artifact_dir/$name"
  # A compressed DMG ends in a koly trailer. hdiutil verification already ran
  # on each macOS runner; this cheap cross-platform check catches HTML/error
  # responses and truncated downloads in the aggregation job.
  tail -c 512 "$dmg" | LC_ALL=C grep -a -q 'koly' || fail "macOS asset has no DMG koly trailer: $name"
done

apk_file="$artifact_dir/${expected[5]}"
[[ "$(read_magic "$apk_file" 2)" == PK ]] || fail "Android asset is not a ZIP/APK archive"

checksum_tool="$(sha256_command)"
echo "All ${#expected[@]} release artifacts are present and structurally valid:"
for name in "${expected[@]}"; do
  file="$artifact_dir/$name"
  if [[ "$checksum_tool" == sha256sum ]]; then
    digest="$(sha256sum -- "$file" | cut -d' ' -f1)"
  else
    digest="$(shasum -a 256 -- "$file" | cut -d' ' -f1)"
  fi
  printf '  %s  %s\n' "$digest" "$name"
done
