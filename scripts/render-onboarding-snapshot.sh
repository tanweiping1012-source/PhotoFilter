#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:-/tmp/photo-curator-onboarding.png}"
language="${2:-zh-Hans}"
temporary_directory="$(mktemp -d /tmp/photo-curator-onboarding.XXXXXX)"
binary_path="$temporary_directory/OnboardingSnapshotRenderer"
trap 'rm -rf "$temporary_directory"' EXIT

cd "$project_root"

xcrun swiftc \
  -parse-as-library \
  Sources/PhotoCurator/OnboardingView.swift \
  scripts/render-onboarding-snapshot.swift \
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
  -AppleLanguages "($language)" \
  -AppleLocale "$language"
