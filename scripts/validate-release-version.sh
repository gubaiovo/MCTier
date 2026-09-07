#!/usr/bin/env bash
# Validate a release tag against the versions that are embedded in the project.
#
# The check is intentionally kept outside the workflow YAML so that local
# dry-runs and CI use exactly the same SemVer/version policy.

set -Eeuo pipefail

tag="${1:-}"
repo_root="${2:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

if [[ -z "$tag" ]]; then
  echo "usage: $0 v<semver> [repository-root]" >&2
  exit 2
fi

RELEASE_TAG="$tag" REPOSITORY_ROOT="$repo_root" node --input-type=module <<'NODE'
import fs from 'node:fs';
import path from 'node:path';

const root = process.env.REPOSITORY_ROOT;
const tag = process.env.RELEASE_TAG;

// SemVer 2.0.0, including a pre-release and/or build-metadata suffix. The
// version fields are compared literally after removing only the leading `v`;
// this prevents a tag such as v3.0.0+local from silently producing a 3.0.0
// package.
const tagPattern = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/;
const match = tagPattern.exec(tag);
if (!match) {
  throw new Error(`Release tag must be v<SemVer> (for example v3.0.0 or v3.0.0-rc.1): ${tag}`);
}

const expected = tag.slice(1);
const readJson = (relative) => JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8'));
const packageVersion = readJson('package.json').version;
const tauriVersion = readJson('src-tauri/tauri.conf.json').version;
const cargoText = fs.readFileSync(path.join(root, 'src-tauri/Cargo.toml'), 'utf8');
const cargoVersion = /^version\s*=\s*"([^"]+)"/m.exec(cargoText)?.[1];

const versions = { package: packageVersion, cargo: cargoVersion, tauri: tauriVersion };
for (const [source, actual] of Object.entries(versions)) {
  if (actual !== expected) {
    throw new Error(`${source} version is ${actual ?? '<missing>'}; tag ${tag} requires ${expected}`);
  }
}

// Android intentionally carries the existing `-android` product suffix. It
// is still checked for tagged builds so a desktop tag cannot pair with an APK
// from a different release.
const androidPath = path.join(root, 'MCTier-Android/app/build.gradle.kts');
if (fs.existsSync(androidPath)) {
  const androidText = fs.readFileSync(androidPath, 'utf8');
  const androidVersion = /versionName\s*=\s*"([^"]+)"/.exec(androidText)?.[1];
  const expectedAndroid = `${expected}-android`;
  if (androidVersion !== expectedAndroid) {
    throw new Error(`Android version is ${androidVersion ?? '<missing>'}; tag ${tag} requires ${expectedAndroid}`);
  }
}

const prerelease = match[4] !== undefined;
console.log(`Release tag ${tag} is valid.`);
console.log(`Version: ${expected}`);
console.log(`Channel: ${prerelease ? 'prerelease' : 'stable'}`);
NODE
