#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

swift build
swift test
bash scripts/check-privacy.sh
bash scripts/check-demo.sh
bash scripts/check-pc19.sh
bash scripts/check-pc21.sh
bash scripts/check-pc22.sh
bash scripts/check-pc23.sh
bash scripts/check-pc24.sh
bash scripts/check-pc25.sh
bash scripts/check-pc26.sh
bash scripts/check-pc27.sh
bash scripts/check-pc28.sh
bash scripts/check-pc29.sh
bash scripts/check-pc30.sh
bash scripts/check-pc31.sh
bash scripts/check-pc32.sh
bash scripts/check-pc33.sh
bash scripts/check-pc34.sh
bash scripts/check-pc35.sh
bash scripts/check-pc36.sh
bash scripts/check-pc37.sh
bash scripts/check-pc38.sh
bash scripts/check-pc39.sh

xcodebuild \
  -project PhotoCurator.xcodeproj \
  -scheme PhotoCurator \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  CODE_SIGNING_ALLOWED=NO \
  build
