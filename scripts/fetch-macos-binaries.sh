#!/usr/bin/env bash

# Fetch the architecture-matched EasyTier binaries used by the macOS desktop build.
# Both the archive and extracted files are pinned by SHA-256 so a replaced upstream
# asset cannot silently enter a release.

set -euo pipefail

EASYTIER_VERSION="v2.6.4"
REQUESTED_ARCH="${1:-$(uname -m)}"

case "$REQUESTED_ARCH" in
  arm64|aarch64)
    EASYTIER_ARCH="aarch64"
    TARGET_TRIPLE="aarch64-apple-darwin"
    ARCHIVE_SHA256="4BE1882D1AA36D31C1D6BA0596F2CF8A097E371F8DA124212324B2E0F8DF7E4B"
    CORE_SHA256="6478A522B8637E2BD2AD3ADAD66ED04A71B35F832BD9889BFFAF1863262F6DDF"
    CLI_SHA256="C700C4FEE1A7F35FCC1A048520D40CEA477B6CF7BF6D75F423FE1642C1EBC75D"
    ;;
  x86_64|amd64)
    EASYTIER_ARCH="x86_64"
    TARGET_TRIPLE="x86_64-apple-darwin"
    ARCHIVE_SHA256="89FC28A6E6995259D76CE3F11775220E8A21C760E94DF91A6A9DB30A69B6982E"
    CORE_SHA256="DDF95A012599E424A632105FC3DC87D15C0A2DAAF30A20B71AA95C8F896F9A2F"
    CLI_SHA256="1E3353FAB30614BFB0277B05C8FF5F478394448E678E5A868AC09AF3EF9CCF8B"
    ;;
  *)
    echo "Unsupported macOS architecture: $REQUESTED_ARCH" >&2
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/src-tauri/resources/binaries"

# Tauri signs and bundles the target-suffixed copies as nested executables.
# Keep the pinned originals intact for cache validation and development builds.
stage_sidecars() {
  for name in easytier-core easytier-cli; do
    install -m 755 "$TARGET_DIR/$name" "$TARGET_DIR/$name-$TARGET_TRIPLE"
  done
}

# A successful actions/cache restore already contains the exact pinned files.
# Verify both files before skipping the network download; an incomplete or
# tampered cache falls through to the normal archive verification path.
cached_ok=true
for name in easytier-core easytier-cli; do
  if [[ ! -f "$TARGET_DIR/$name" ]]; then
    cached_ok=false
    continue
  fi
  if [[ "$name" == "easytier-core" ]]; then
    expected="$CORE_SHA256"
  else
    expected="$CLI_SHA256"
  fi
  if ! printf '%s  %s\n' "$expected" "$TARGET_DIR/$name" | shasum -a 256 --check >/dev/null; then
    cached_ok=false
  fi
done
if [[ "$cached_ok" == "true" ]]; then
  chmod 755 "$TARGET_DIR/easytier-core" "$TARGET_DIR/easytier-cli"
  stage_sidecars
  echo "Pinned EasyTier macOS binaries already verified; skipping download."
  exit 0
fi

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

stage_sidecars
echo "EasyTier macOS binaries are ready in $TARGET_DIR"
