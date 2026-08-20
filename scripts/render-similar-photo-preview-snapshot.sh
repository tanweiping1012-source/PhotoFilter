#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-/tmp/photo-curator-similar-preview.png}"
temporary_directory="$(mktemp -d /tmp/photo-curator-similar-preview.XXXXXX)"
binary_path="$temporary_directory/SimilarPhotoPreviewSnapshotRenderer"
trap 'rm -rf "$temporary_directory"' EXIT

cd "$project_root"

sources=()
while IFS= read -r source; do
  [[ "$source" == "Sources/PhotoCurator/PhotoCuratorApp.swift" ]] && continue
  sources+=("$source")
done < <(find Sources/PhotoCurator -maxdepth 1 -type f -name '*.swift' | sort)

xcrun swiftc \
  -parse-as-library \
  "${sources[@]}" \
  scripts/render-similar-photo-preview-snapshot.swift \
  -o "$binary_path"

"$binary_path" \
  "$project_root/Resources/DemoPhotos" \
  "$output_path" \
  -AppleLanguages "(zh-Hans)" \
  -AppleLocale "zh-Hans"
