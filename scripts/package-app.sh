#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${1:-$project_root/dist}"
app_root="$output_root/旅行照片筛选器.app"

cd "$project_root"
xcodebuild \
  -project PhotoCurator.xcodeproj \
  -scheme PhotoCurator \
  -configuration Release \
  -destination "generic/platform=macOS" \
  build

target_build_dir="$(
  xcodebuild \
    -project PhotoCurator.xcodeproj \
    -scheme PhotoCurator \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -showBuildSettings |
    awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
)"
app_source="$target_build_dir/PhotoCurator.app"

mkdir -p "$output_root"
rm -rf "$app_root"
ditto "$app_source" "$app_root"
codesign --verify --deep --strict "$app_root"

echo "$app_root"
