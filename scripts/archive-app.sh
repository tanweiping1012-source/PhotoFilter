#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_archive="$project_root/dist/TravelPhotoFilter-$(date +%Y%m%d-%H%M%S).xcarchive"
archive_path="${1:-$default_archive}"

cd "$project_root"
mkdir -p "$(dirname "$archive_path")"

xcodebuild \
  -project PhotoCurator.xcodeproj \
  -scheme PhotoCurator \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  archive

echo "$archive_path"
