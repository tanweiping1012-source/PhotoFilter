#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

launch_mode="${1:-}"
if [[ "$launch_mode" == "--verification" ]]; then
  shift
else
  launch_mode=""
fi
app_arguments=("$@")
architecture="$(uname -m)"
build_overrides=()
build_arguments=(
  -project PhotoCurator.xcodeproj
  -scheme PhotoCurator
  -configuration Debug
  -destination "platform=macOS,arch=$architecture"
)
if [[ "$launch_mode" == "--verification" ]]; then
  verification_stamp="$(date +%s)"
  derived_data="$HOME/Library/Developer/Xcode/DerivedData/PhotoCurator-Verification-$verification_stamp"
  bundle_identifier="com.photocurator.local.verification.$verification_stamp"
  build_arguments+=(-derivedDataPath "$derived_data")
  build_overrides+=("PRODUCT_BUNDLE_IDENTIFIER=$bundle_identifier")
else
  bundle_identifier="com.photocurator.local"
fi

if [[ "$launch_mode" == "--verification" ]]; then
  xcodebuild "${build_arguments[@]}" "${build_overrides[@]}" build
else
  xcodebuild "${build_arguments[@]}" build
fi

if [[ "$launch_mode" == "--verification" ]]; then
  target_build_dir="$(
    xcodebuild "${build_arguments[@]}" "${build_overrides[@]}" -showBuildSettings |
      awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
  )"
else
  target_build_dir="$(
    xcodebuild "${build_arguments[@]}" -showBuildSettings |
      awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }'
  )"
fi
app_root="$target_build_dir/PhotoCurator.app"
if [[ "${#app_arguments[@]}" -gt 0 ]]; then
  open -n "$app_root" --args "${app_arguments[@]}"
else
  open -n "$app_root"
fi

if [[ "$launch_mode" == "--verification" ]]; then
  echo "验证 App 已启动：$bundle_identifier"
fi
