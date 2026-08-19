#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-19 检查失败：%s\n' "$1" >&2
  exit 1
}

catalog="Resources/Localizable.xcstrings"
info_catalog="Resources/InfoPlist.xcstrings"
translations="scripts/localization-en.json"
icon_directory="Resources/Assets.xcassets/AppIcon.appiconset"
project_file="PhotoCurator.xcodeproj/project.pbxproj"
compile_directory="$(mktemp -d /tmp/photo-curator-pc19.XXXXXX)"
trap 'rm -rf "$compile_directory"' EXIT

for size in 16 32 64 128 256 512 1024; do
  icon="$icon_directory/app-icon-$size.png"
  [[ -f "$icon" ]] || fail "缺少 ${size}px App Icon"
  width="$(sips -g pixelWidth "$icon" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$icon" | awk '/pixelHeight/ {print $2}')"
  [[ "$width" == "$size" && "$height" == "$size" ]] ||
    fail "$icon 尺寸为 ${width}x${height}，应为 ${size}x${size}"
done

jq empty "$catalog" "$info_catalog" "$translations" ||
  fail "String Catalog 或翻译映射不是有效 JSON"

missing_english="$(
  jq '[.strings | to_entries[] | select(.value.localizations.en.stringUnit.value == null) | .key] | length' \
    "$catalog"
)"
[[ "$missing_english" == "0" ]] ||
  fail "Localizable.xcstrings 仍有 $missing_english 个键缺少英文"

stale_count="$(
  jq '[.strings | to_entries[] | select(.value.extractionState == "stale")] | length' \
    "$catalog"
)"
[[ "$stale_count" == "0" ]] ||
  fail "Localizable.xcstrings 仍有 $stale_count 个 stale 键"

ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0]))
  placeholders = ->(text) {
    text.scan(/%(?:\d+\$)?(?:lld|ld|@|d|f)/).map { |item|
      item.sub(/%\d+\$/, "%")
    }
  }
  invalid = data.fetch("strings").each_with_object([]) do |(source, entry), result|
    target = entry.dig("localizations", "en", "stringUnit", "value")
    result << source if target && placeholders.call(source) != placeholders.call(target)
  end
  abort invalid.join("\n") unless invalid.empty?
' "$catalog" || fail "中英文格式占位符不一致"

xcrun xcstringstool compile \
  "$catalog" \
  --output-directory "$compile_directory/localizable" \
  --language en \
  --language zh-Hans \
  --serialization-format text
xcrun xcstringstool compile \
  "$info_catalog" \
  --output-directory "$compile_directory/info" \
  --language en \
  --language zh-Hans \
  --serialization-format text

jq -e '
  .strings.CFBundleDisplayName.localizations.en.stringUnit.value == "Travel Photo Filter"
  and .strings.CFBundleDisplayName.localizations["zh-Hans"].stringUnit.value == "旅行照片筛选器"
  and .strings.CFBundleName.localizations.en.stringUnit.value == "Travel Photo Filter"
  and .strings.CFBundleName.localizations["zh-Hans"].stringUnit.value == "旅行照片筛选器"
' "$info_catalog" >/dev/null || fail "InfoPlist 显示名称未完整本地化"

[[ "$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' packaging/Info.plist
)" == "旅行照片筛选器" ]] ||
  fail "手工打包配置的显示名称不正确"
[[ "$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleName' packaging/Info.plist
)" == "旅行照片筛选器" ]] ||
  fail "手工打包配置仍暴露内部工程名"
rg -q 'TravelPhotoFilter-\$\(date' scripts/archive-app.sh ||
  fail "Archive 默认文件名未使用新产品名"
rg -q 'TravelPhotoFilter-\$\{version\}-macOS-universal\.dmg' \
  scripts/package-dmg.sh ||
  fail "DMG 默认文件名未使用新产品名"

for source in \
  Sources/PhotoCurator \
  Resources \
  packaging \
  scripts/package-app.sh \
  scripts/package-dmg.sh \
  README.md \
  docs/PRIVACY_POLICY.md; do
  if rg -n '旅行照片策展器|Photo Curator' "$source"; then
    fail "$source 仍包含旧产品名"
  fi
done

rg -q 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon' "$project_file" ||
  fail "Xcode Target 未配置 AppIcon"
rg -q 'SupportInformationView\.swift in Sources' "$project_file" ||
  fail "帮助与支持页未加入 Xcode Sources"
rg -q 'String\(localized: "旅行照片筛选器"\)' \
  Sources/PhotoCurator/SupportInformationView.swift ||
  fail "诊断信息未使用本地化产品名"
rg -q 'accessibilityIdentifier\("sidebar\.support"\)' Sources/PhotoCurator/ContentView.swift ||
  fail "缺少支持入口 accessibility identifier"

for identifier in \
  photo-curator.main \
  photo.filter \
  photo.status \
  photo.visible-count \
  ai.status \
  decision.actions \
  decision.keep \
  decision.reject \
  decision.undecided \
  decision.export; do
  rg -Fq "accessibilityIdentifier(\"$identifier\")" Sources/PhotoCurator/ContentView.swift ||
    fail "缺少 accessibility identifier: $identifier"
done

rg -q '\.focusable\(\)' Sources/PhotoCurator/ContentView.swift ||
  fail "照片卡未加入键盘焦点系统"
rg -q '\.onKeyPress\(\.rightArrow\)' Sources/PhotoCurator/ContentView.swift ||
  fail "照片卡缺少方向键导航"
rg -q 'ViewThatFits\(in: \.horizontal\)' Sources/PhotoCurator/ContentView.swift ||
  fail "底部操作栏缺少窄窗口自适应"
rg -q '\.defaultSize\(width: 1200, height: 800\)' Sources/PhotoCurator/PhotoCuratorApp.swift ||
  fail "主窗口缺少稳定默认尺寸"

for language in zh-Hans en; do
  screenshot="docs/store-screenshots/photo-curator-${language}-2560x1600.png"
  [[ -f "$screenshot" ]] || fail "缺少 $language 商店截图候选"
  width="$(sips -g pixelWidth "$screenshot" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$screenshot" | awk '/pixelHeight/ {print $2}')"
  [[ "$width" == "2560" && "$height" == "1600" ]] ||
    fail "$screenshot 尺寸为 ${width}x${height}"
done

printf 'PC-19 检查通过：App Icon、双语、支持入口、无障碍、键盘与商店截图均已接线。\n'
