#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -ge 1 ]]; then
  archive_path="$1"
else
  archive_path="$(
    find "$project_root/dist" \
      -maxdepth 1 \
      -type d \
      -name 'TravelPhotoFilter-*.xcarchive' \
      -print 2>/dev/null |
      sort |
      tail -n 1
  )"
  [[ -n "$archive_path" ]] || {
    printf '找不到旅行照片筛选器归档，请先运行 scripts/archive-app.sh。\n' >&2
    exit 1
  }
fi
source_app="$archive_path/Products/Applications/PhotoCurator.app"
staging_directory="$(mktemp -d /tmp/photo-curator-dmg.XXXXXX)"
volume_directory="$staging_directory/Travel Photo Filter"

cleanup() {
  rm -rf "$staging_directory"
}
trap cleanup EXIT

[[ -d "$source_app" ]] || {
  printf '找不到已归档的 App：%s\n' "$source_app" >&2
  exit 1
}

version="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$source_app/Contents/Info.plist"
)"
output_path="${2:-$project_root/dist/TravelPhotoFilter-${version}-macOS-universal.dmg}"

architectures="$(lipo -archs "$source_app/Contents/MacOS/PhotoCurator")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
  printf 'App 不是 arm64 + x86_64 通用构建：%s\n' "$architectures" >&2
  exit 1
}

codesign --verify --deep --strict "$source_app"

mkdir -p "$volume_directory" "$(dirname "$output_path")"
ditto "$source_app" "$volume_directory/旅行照片筛选器.app"
ln -s /Applications "$volume_directory/应用程序"

cat > "$volume_directory/安装说明.txt" <<EOF
旅行照片筛选器 $version

安装：
1. 将“旅行照片筛选器.app”拖到“应用程序”。
2. 在“应用程序”文件夹中打开旅行照片筛选器。

由于此版本没有购买 Apple Developer Program，也没有经过 Apple 公证，
从 GitHub 下载后 macOS 可能阻止首次启动。

首次启动方法：
1. 在 Finder 中按住 Control 点按 App，选择“打开”。
2. 如果仍被阻止，打开“系统设置 > 隐私与安全性”，找到拦截提示，
   确认 App 来源是你下载的 GitHub Release 后，选择“仍要打开”。

安全边界：
- 原照片只读，导出仅复制。
- AI 功能可选；仅在确认后发送用户选择的 512/1024/1536px 无元数据预览。
- API Key 只保存在本机 Keychain。

系统要求：macOS 14 或更高版本。
支持架构：Apple Silicon (arm64) 与 Intel (x86_64)。
EOF

rm -f "$output_path"
# hdiutil 会往 stdout 打进度和 "created: ..."；本脚本的 stdout 契约是
# "只有最终 DMG 路径一行"，调用方（CI）要直接拿它当变量用，所以把噪声转到 stderr。
hdiutil create \
  -volname "旅行照片筛选器" \
  -srcfolder "$volume_directory" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$output_path" >&2

printf '%s\n' "$output_path"
