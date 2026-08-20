#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="$project_root/Resources/Assets.xcassets/AppIcon.appiconset"
binary_path="$(mktemp -u /tmp/photo-curator-icon-generator.XXXXXX)"
trap 'rm -f "$binary_path"' EXIT

cd "$project_root"
xcrun swiftc -parse-as-library scripts/generate-app-icon.swift -o "$binary_path"
"$binary_path" "$output_directory"
