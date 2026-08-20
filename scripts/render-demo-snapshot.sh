#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-/tmp/photo-curator-demo.png}"
language="${2:-zh-Hans}"
width="${3:-1200}"
height="${4:-800}"
state="${5:-scored}"
temporary_directory="$(mktemp -d /tmp/photo-curator-demo-renderer.XXXXXX)"
binary_path="$temporary_directory/PhotoCuratorDemoRenderer"
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
  scripts/render-demo-snapshot.swift \
  -o "$binary_path"

if [[ "$language" == "en" ]]; then
  xcrun xcstringstool compile \
    "$project_root/Resources/Localizable.xcstrings" \
    --output-directory "$temporary_directory" \
    --language en \
    --serialization-format binary
fi

"$binary_path" \
  "$project_root/Resources/DemoPhotos" \
  "$output_path" \
  "$width" \
  "$height" \
  "$language" \
  "$state" \
  -AppleLanguages "($language)" \
  -AppleLocale "$language"
