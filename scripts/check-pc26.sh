#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-26 检查失败：%s\n' "$1" >&2
  exit 1
}

onboarding="Sources/PhotoCurator/OnboardingView.swift"
content="Sources/PhotoCurator/ContentView.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"

rg -q 'OnboardingView\.swift in Sources' "$project" ||
  fail "OnboardingView 未加入 Xcode Sources"
rg -q 'completed-onboarding-version-v3' "$onboarding" ||
  fail "首次引导缺少版本化偏好键"
rg -q 'static let currentVersion = 3' "$onboarding" ||
  fail "首次引导缺少当前版本"
rg -q 'func shouldPresent' "$onboarding" ||
  fail "首次展示条件不可测试"
rg -q '!isDemoModeActive' "$onboarding" ||
  fail "自动审核样例没有旁路首次引导"
rg -q 'func markCompleted' "$onboarding" ||
  fail "完成后没有记录引导版本"

rg -q 'Label\("新手引导", systemImage: "graduationcap"\)' "$content" ||
  fail "侧栏入口未改为新手引导"
rg -q 'accessibilityIdentifier\("sidebar\.onboarding"\)' "$content" ||
  fail "新手引导入口缺少稳定无障碍标识"
rg -q 'OnboardingPreferenceStore\.shouldPresent' "$content" ||
  fail "首次启动没有接入展示条件"
rg -q 'OnboardingPreferenceStore\.markCompleted' "$content" ||
  fail "关闭引导没有记录完成版本"

for identifier in \
  onboarding.dismiss \
  onboarding.start-sample \
  onboarding.choose-folder; do
  rg -Fq "accessibilityIdentifier(\"$identifier\")" "$onboarding" ||
    fail "新手引导缺少操作：$identifier"
done
rg -q 'library\.startDemoMode\(\)' "$content" ||
  fail "完整示例筛选没有复用离线 Demo"
rg -q 'library\.chooseFolder\(\)' "$content" ||
  fail "选择自己的照片没有接入系统文件夹选择器"
rg -q -- '--review-demo' Sources/PhotoCurator/PhotoLibraryViewModel.swift ||
  fail "自动审核启动参数被移除"

rg -q 'testOnboardingPreferenceShowsOnceAndSkipsReviewDemo' \
  Tests/PhotoCuratorTests/DemoModeLibraryTests.swift ||
  fail "缺少首次/后续启动和审核旁路测试"
rg -q '# 新手引导规格' docs/product/ONBOARDING.md ||
  fail "缺少新手引导规格"
rg -q '## PC-26 首次启动新手引导' docs/engineering/TASKS.md ||
  fail "任务卡缺少 PC-26"

if rg -n 'URLSession|AIProviderKeyStore|SecItem|https?://' "$onboarding"; then
  fail "新手引导视图不得访问网络或 Keychain"
fi
if rg -n '审核演示|Review Demo|离线演示结果' \
  Sources Resources/Localizable.xcstrings scripts/localization-en.json; then
  fail "用户界面仍存在旧审核演示名称"
fi

catalog="Resources/Localizable.xcstrings"
key_count="$(jq '.strings | length' "$catalog")"
english_count="$(
  jq '[.strings[] | select(.localizations.en.stringUnit.value != null)] | length' \
    "$catalog"
)"
[[ "$key_count" == "$english_count" ]] ||
  fail "String Catalog 有 $((key_count - english_count)) 个键缺少英文"

printf 'PC-26 检查通过：首次展示、持久入口、三种分支、审核旁路和离线边界一致。\n'
