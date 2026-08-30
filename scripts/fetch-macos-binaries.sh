#!/usr/bin/env bash

# Fetch the architecture-matched EasyTier binaries used by the macOS desktop build.
# Both the archive and extracted files are pinned by SHA-256 so a replaced upstream
# asset cannot silently enter a release.

set -euo pipefail

EASYTIER_VERSION="v2.5.0"
REQUESTED_ARCH="${1:-$(uname -m)}"

case "$REQUESTED_ARCH" in
  arm64|aarch64)
    EASYTIER_ARCH="aarch64"
    ARCHIVE_SHA256="CE3744470E41675358728AB0A8DA798436EC763F561D8B698D8D06A7FFA21895"
    CORE_SHA256="DD386E3F10FB63C58D03DA6C0E16F67177DF4E37EC1986BC07D8FD2E1D057F1F"
    CLI_SHA256="733BFFE9F34CB22048D24260E75FC55840A16BA366CB57AE2273E792844F2780"
    ;;
  x86_64|amd64)
    EASYTIER_ARCH="x86_64"
    ARCHIVE_SHA256="9BC12142F8808F0DE02575064E39901AC6804D82EF27C1D08ECF0BCED3E79C47"
    CORE_SHA256="249AC5B755D66834C43FFE7F65B8210090AE771FBA354D4240277CDE7E7FD9C5"
    CLI_SHA256="6BC26FCBF36EDB3AF4358C906B6B9AB12FC1BBD67090E859F63155032A96ACB6"
    ;;
  *)
    echo "Unsupported macOS architecture: $REQUESTED_ARCH" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/src-tauri/resources/binaries"
TEMP_PARENT="${TMPDIR:-/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
WORK_DIR="$(mktemp -d "$TEMP_PARENT/mctier-fetch.XXXXXX")"

cleanup() {
  case "$WORK_DIR" in
    "$TEMP_PARENT"/mctier-fetch.*) rm -rf -- "$WORK_DIR" ;;
    *) echo "Refusing to remove unexpected temporary path: $WORK_DIR" >&2 ;;
  esac
}
trap cleanup EXIT

ASSET="easytier-macos-${EASYTIER_ARCH}-${EASYTIER_VERSION}.zip"
URL="https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/${ASSET}"
ARCHIVE="$WORK_DIR/$ASSET"
EXTRACT_DIR="$WORK_DIR/extracted"

mkdir -p "$TARGET_DIR" "$EXTRACT_DIR"
echo "Downloading EasyTier ${EASYTIER_VERSION} for macOS ${EASYTIER_ARCH}..."
curl --fail --location --retry 3 --retry-all-errors --silent --show-error \
  --user-agent "MCTier-fetch-binaries" \
  "$URL" \
  --output "$ARCHIVE"

printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE" | shasum -a 256 --check
unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"

SOURCE_ROOT="$EXTRACT_DIR/easytier-macos-${EASYTIER_ARCH}"
for name in easytier-core easytier-cli; do
  source_path="$SOURCE_ROOT/$name"
  if [[ ! -f "$source_path" ]]; then
    echo "Required file is missing from $ASSET: $name" >&2
    exit 1
  fi

  if [[ "$name" == "easytier-core" ]]; then
    expected="$CORE_SHA256"
  else
    expected="$CLI_SHA256"
  fi

  printf '%s  %s\n' "$expected" "$source_path" | shasum -a 256 --check
  install -m 755 "$source_path" "$TARGET_DIR/$name"
done

echo "EasyTier macOS binaries are ready in $TARGET_DIR"
