#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-/tmp/photo-curator-privacy.png}"
binary_path="$(mktemp -u /tmp/photo-curator-privacy-renderer.XXXXXX)"
trap 'rm -f "$binary_path"' EXIT

cd "$project_root"

xcrun swiftc \
  -parse-as-library \
  Sources/PhotoCurator/PrivacyInformationView.swift \
  scripts/render-privacy-snapshot.swift \
  -o "$binary_path"

"$binary_path" "$output_path"
