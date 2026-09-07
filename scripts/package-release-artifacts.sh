#!/usr/bin/env bash
# Normalize one platform's native build output into a versioned release asset.
#
# Usage:
#   package-release-artifacts.sh <platform> <arch> <version> <source-dir> <output-dir>
#
# The source directory is deliberately searched with an exact cardinality
# check. A successful compiler invocation with zero or multiple bundles must
# never become an apparently valid release asset.

set -Eeuo pipefail

platform="${1:-}"
arch="${2:-}"
version="${3:-}"
source_dir="${4:-}"
output_dir="${5:-}"

usage() {
  echo "usage: $0 <windows|linux|macos|android> <architecture> <version> <source-dir> <output-dir>" >&2
  exit 2
}

[[ -n "$platform" && -n "$arch" && -n "$version" && -n "$source_dir" && -n "$output_dir" ]] || usage

# Keep this in sync with validate-release-version.sh. This script receives the
# version from the metadata job, but it is also useful as a standalone local
# guard and therefore must not accept arbitrary path metacharacters.
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
  echo "invalid release version: $version" >&2
  exit 1
fi

fail() {
  echo "release artifact error: $*" >&2
  exit 1
}

[[ -d "$source_dir" ]] || fail "source directory does not exist: $source_dir"
mkdir -p -- "$output_dir"

single_file() {
  local label="$1"
  local pattern="$2"
  local -a files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  # Tauri places Linux bundles one directory below `bundle/` (appimage/ and
  # deb/), while the other platforms normally put their file directly in the
  # supplied directory. Keep the bounded search so stale deep build output is
  # not accidentally collected.
  done < <(find "$source_dir" -maxdepth 2 -type f -name "$pattern" -print0)
  if (( ${#files[@]} != 1 )); then
    fail "$label: expected exactly one $pattern in $source_dir, found ${#files[@]}"
  fi
  printf '%s\n' "${files[0]}"
}

assert_not_placeholder() {
  local file="$1"
  if LC_ALL=C grep -a -q 'MCTIER-CI-PLACEHOLDER-NOT-A-REAL-BINARY' "$file"; then
    fail "placeholder content detected in $file"
  fi
}

assert_magic() {
  local file="$1"
  local kind="$2"
  case "$kind" in
    pe)
      [[ "$(dd if="$file" bs=1 count=2 2>/dev/null)" == "MZ" ]] || fail "not a PE executable: $file"
      ;;
    elf)
      [[ "$(od -An -t x1 -N 4 "$file" | tr -d ' \n')" == "7f454c46" ]] || fail "not an ELF executable: $file"
      ;;
    deb)
      [[ "$(dd if="$file" bs=1 count=7 2>/dev/null)" == '!<arch>' ]] || fail "not a Debian archive: $file"
      ;;
    zip)
      [[ "$(dd if="$file" bs=1 count=2 2>/dev/null)" == "PK" ]] || fail "not a ZIP/APK archive: $file"
      ;;
    dmg)
      command -v hdiutil >/dev/null 2>&1 || fail "hdiutil is required to verify a macOS disk image"
      hdiutil verify "$file" >/dev/null || fail "DMG verification failed: $file"
      ;;
    *)
      fail "unknown artifact kind: $kind"
      ;;
  esac
}

copy_checked() {
  local source="$1"
  local destination="$2"
  local kind="$3"
  [[ ! -e "$destination" ]] || fail "refusing to overwrite existing artifact: $destination"
  [[ -s "$source" ]] || fail "empty artifact: $source"
  assert_not_placeholder "$source"
  assert_magic "$source" "$kind"
  install -m 0644 -- "$source" "$destination"
  printf 'packaged %s\n' "$(basename -- "$destination")"
}

case "$platform:$arch" in
  windows:x86_64)
    source="$(single_file 'Windows NSIS bundle' '*.exe')"
    copy_checked "$source" "$output_dir/MCTier-${version}-windows-x86_64-unsigned.exe" pe
    ;;
  linux:x86_64)
    appimage="$(single_file 'Linux AppImage bundle' '*.AppImage')"
    deb="$(single_file 'Linux Debian bundle' '*.deb')"
    copy_checked "$appimage" "$output_dir/MCTier-${version}-linux-x86_64.AppImage" elf
    copy_checked "$deb" "$output_dir/MCTier-${version}-linux-x86_64.deb" deb
    ;;
  macos:x86_64|macos:arm64)
    dmg="$(single_file 'macOS disk image' '*.dmg')"
    copy_checked "$dmg" "$output_dir/MCTier-${version}-macos-${arch}-adhoc.dmg" dmg
    ;;
  android:arm64)
    apk="$(single_file 'Android debug APK' '*debug*.apk')"
    copy_checked "$apk" "$output_dir/MCTier-${version}-android-arm64-debug-signed.apk" zip
    ;;
  *)
    fail "unsupported platform/architecture: $platform/$arch"
    ;;
esac
