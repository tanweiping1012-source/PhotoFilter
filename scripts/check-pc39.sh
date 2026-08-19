#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-39 检查失败：%s\n' "$1" >&2
  exit 1
}

content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"

rg -q 'library\.prepareAIFinalSelectionRun\(\)' "$content" ||
  fail "缺少统一的完整 AI评分入口"

if rg -n \
  'AI评分相似照片|prepareAestheticReviewForSelectedPhoto|submitConfirmedAestheticReview|showAestheticReviewConfirmation|isReviewingAesthetics' \
  "$content" "$preview" "$view_model" Resources/Localizable.xcstrings; then
  fail "局部相似照片评分入口或状态仍然存在"
fi

if rg -n 'AestheticReviewGroupPlanner|AestheticReviewRunPlanner' \
  Sources Tests "$project"; then
  fail "旧局部评分规划器仍然存在"
fi

[[ ! -e Sources/PhotoCurator/AestheticReviewGroupPlanner.swift ]] ||
  fail "局部评分规划器文件未删除"
[[ ! -e Sources/PhotoCurator/AestheticReviewRunPlanner.swift ]] ||
  fail "首轮局部评分规划器文件未删除"

printf 'PC-39 检查通过：AI评分只保留统一的完整候选池入口。\n'
