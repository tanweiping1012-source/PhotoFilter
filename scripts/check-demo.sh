#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

assets_directory="Resources/DemoPhotos"
project_file="PhotoCurator.xcodeproj/project.pbxproj"

fail() {
  printf '演示检查失败：%s\n' "$1" >&2
  exit 1
}

mapfile_supported=false
if type mapfile >/dev/null 2>&1; then
  mapfile_supported=true
fi

if [[ "$mapfile_supported" == true ]]; then
  mapfile -t photos < <(find "$assets_directory" -maxdepth 1 -type f -name '*.jpg' | sort)
else
  photos=()
  while IFS= read -r photo; do
    photos+=("$photo")
  done < <(find "$assets_directory" -maxdepth 1 -type f -name '*.jpg' | sort)
fi

[[ "${#photos[@]}" -eq 8 ]] ||
  fail "必须恰好包含 8 张内置 JPEG，当前为 ${#photos[@]} 张"

(
  cd "$assets_directory"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "内置样例 SHA-256 与清单不一致"

for photo in "${photos[@]}"; do
  width="$(sips -g pixelWidth "$photo" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$photo" | awk '/pixelHeight/ {print $2}')"
  [[ "$width" == "2400" && "$height" == "1800" ]] ||
    fail "$photo 尺寸必须为 2400x1800，当前为 ${width}x${height}"
done

rg -q 'DemoPhotos in Resources' "$project_file" ||
  fail "DemoPhotos 未加入 Xcode Copy Bundle Resources"
rg -q 'DemoModeLibrary\.swift in Sources' "$project_file" ||
  fail "DemoModeLibrary 未加入 Xcode Sources"

if rg -n 'URLSession|AIProviderKeyStore|ArkAPIKeyStore|SecItem|responsesURL|https?://' \
  Sources/PhotoCurator/DemoModeLibrary.swift; then
  fail "DemoModeLibrary 不得访问网络或 Keychain"
fi

demo_methods="$(
  sed -n \
    '/func startDemoMode/,/func chooseFolder/p' \
    Sources/PhotoCurator/PhotoLibraryViewModel.swift
)"
if printf '%s\n' "$demo_methods" |
  rg -n 'URLSession|AIProviderKeyStore|ArkAPIKeyStore|SecItem|responsesURL|https?://'; then
  fail "演示启动/退出路径不得访问网络或 Keychain"
fi

if rg -n '@Published private\\(set\\) var isAIModelKeyConfigured = AIProviderKeyStore' \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift; then
  fail "ViewModel 不得在属性初始化阶段读取 Keychain"
fi

# 每一类都是独立的一轮，进度的分子和分母都必须属于当前类型。
#
# 分子有行为测试守着（testDemoAIScoringRunsOfflineRequestWindows 会持续采样，
# 分子越过分母就失败）。分母守不住：内置样例恰好是人物 4 张、风景 4 张，
# 沿用上一类留下的分母和正确取值完全一样，任何基于这份样例的测试都分辨不出来。
# 所以这里用结构断言补上——两类张数一旦不同，缺了这一行就是错的。
awk '/func startDemoAIScoring\(/,/^    }/' \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift |
  rg -q 'aiFinalSelectionRunProgress.candidatePhotoCount =' ||
  fail "演示每一轮开跑时没有把进度分母换成本类型的候选数"
awk '/private func applyDemoAIScoringBatch\(/,/^    }/' \
  Sources/PhotoCurator/PhotoLibraryViewModel.swift |
  rg -q 'aiFinalSelectionRunProgress.completedPhotoCount = scoredInCategory' ||
  fail "演示把全局已评张数塞进了按类型的进度分子"
rg -q 'testDemoLaunchSkipsKeychainAndPersistence' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少演示零 Keychain/零持久化单测"

printf '演示检查通过：8 张固定样例、资源接线、离线边界与单测入口一致。\n'
