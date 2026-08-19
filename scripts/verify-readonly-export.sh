#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "用法：$0 <源照片目录> <导出前生成的哈希清单>" >&2
  exit 2
fi

source_dir="$1"
baseline="$2"
current="$(mktemp)"
trap 'rm -f "$current"' EXIT

find "$source_dir" -type f -print0 | sort -z | xargs -0 shasum -a 256 > "$current"
diff -u "$baseline" "$current"
echo "验证通过：源照片目录的文件内容未改变。"
