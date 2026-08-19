#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-/tmp/photo-curator-ai-settings.png}"
language="${2:-zh-Hans}"
mode="${3:-builtin}"
temporary_directory="$(mktemp -d /tmp/photo-curator-ai-settings.XXXXXX)"
binary_path="$temporary_directory/AISettingsSnapshotRenderer"
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
  scripts/render-ai-settings-snapshot.swift \
  -o "$binary_path"

if [[ "$language" == "en" ]]; then
  xcrun xcstringstool compile \
    "$project_root/Resources/Localizable.xcstrings" \
    --output-directory "$temporary_directory" \
    --language en \
    --serialization-format binary
fi

"$binary_path" \
  "$output_path" \
  "$language" \
  "$mode" \
  -AppleLanguages "($language)" \
  -AppleLocale "$language"
