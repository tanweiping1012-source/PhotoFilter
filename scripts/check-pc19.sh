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

# 真正打包的是 Xcode target（GENERATE_INFOPLIST_FILE），不再存在手工维护的 Info.plist：
# 一份没人构建的副本只会和工程设置里的版本号、显示名互相矛盾。
rg -q 'INFOPLIST_KEY_CFBundleDisplayName = "旅行照片筛选器"' "$project_file" ||
  fail "Xcode Target 的显示名称不正确"
rg -q 'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.photography"' \
  "$project_file" ||
  fail "Xcode Target 缺少 App Store 类别"
rg -q 'ENABLE_HARDENED_RUNTIME = YES' "$project_file" ||
  fail "Release 未开启 Hardened Runtime"
[[ ! -e packaging ]] ||
  fail "packaging/ 已废弃：应只保留 Xcode 工程一处打包配置"
rg -q 'TravelPhotoFilter-\$\(date' scripts/archive-app.sh ||
  fail "Archive 默认文件名未使用新产品名"
rg -q 'TravelPhotoFilter-\$\{version\}-macOS-universal\.dmg' \
  scripts/package-dmg.sh ||
  fail "DMG 默认文件名未使用新产品名"

for source in \
  Sources/PhotoCurator \
  Resources \
  scripts/package-app.sh \
  scripts/package-dmg.sh \
  README.md \
  docs/privacy/PRIVACY_POLICY.md; do
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

# 侧栏五个入口必须共用同一套图标列宽与字号：SF Symbols 固有宽度不同，
# 直接用 Label 会让图标中心和文字起点各差几个点，竖排时非常显眼。
rg -q 'struct SidebarEntryLabelStyle: LabelStyle' Sources/PhotoCurator/ContentView.swift ||
  fail "缺少侧栏入口统一排版样式"
sidebar_entry_count="$(
  rg -c 'labelStyle\(SidebarEntryLabelStyle\(\)\)' Sources/PhotoCurator/ContentView.swift
)"
[[ "$sidebar_entry_count" == "5" ]] ||
  fail "侧栏入口有 $sidebar_entry_count 个应用了统一排版，应为 5 个"

# 全 App 字阶：同一角色在任何界面里都用同一级，配对的标签与数值必须同级。
#
# 这条断言的范围扩过两次，每次都是因为上一版盖得太窄：
#   一开始只卡侧栏 AI 区块——也就是当时已经合规的那一段；
#   然后扩到整个侧栏，主内容区依旧没有任何约定：状态行 subheadline、
#   可见张数 callout、回执标题 subheadline.semibold、回执正文 callout、
#   底栏文件名 caption.medium、摘要 caption2、任务条又是另一套……
#   同一屏上十来种字号。
# 现在覆盖整个 Sources：字阶定义文件自己除外，其余任何地方都不准裸写字号。
# 确实需要跳出字阶的地方（大图总分、场景首页、等宽 model ID、图标尺寸）
# 都在 Typography 里单独命名，例外因此是被声明出来的，而不是又一次裸写。
rg -q 'enum Typography' Sources/PhotoCurator/Typography.swift ||
  fail "缺少全 App 字阶定义"
if rg -q 'font\(\.' Sources/PhotoCurator -g '!Typography.swift'; then
  fail "仍有裸写字号，应改用 Typography"
fi

# 侧栏内部：面板标题只有顶部一处；区块标题恰好三处：项目 / 保留目标 / AI评分。
sidebar="$(
  awk '/private var projectSidebar/,/private var aiAccessibilityStatus/' \
    Sources/PhotoCurator/ContentView.swift
)"
pane_title_uses="$(printf '%s' "$sidebar" | rg -c 'Typography\.paneTitle' || true)"
[[ "${pane_title_uses:-0}" == "1" ]] ||
  fail "侧栏面板标题级被用了 ${pane_title_uses:-0} 次，整栏只应有 1 处"
section_title_uses="$(printf '%s' "$sidebar" | rg -c 'Typography\.sectionTitle' || true)"
[[ "${section_title_uses:-0}" == "3" ]] ||
  fail "区块标题有 ${section_title_uses:-0} 处，应为 3 处（项目 / 保留目标 / AI评分）"

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
