#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-38 检查失败：%s\n' "$1" >&2
  exit 1
}

classifier="Sources/PhotoCurator/PeopleSubjectClassifier.swift"
tests="Tests/PhotoCuratorTests/PeopleSubjectClassifierTests.swift"
spec="docs/product/PEOPLE_CLASSIFICATION.md"
classification="docs/product/PEOPLE_CLASSIFICATION.md"

rg -q 'minimumLandscapePersonArea: CGFloat = 0\.018' "$classifier" ||
  fail "人物风景最小绝对面积不是 1.8%"
rg -q 'minimumSalientRegionConcentration: CGFloat = 0\.10' \
  "$classifier" ||
  fail "人物在显著区域中的最小占比不是 10%"
rg -q 'testObservedStreetSceneFalsePositivesRemainScenery' "$tests" ||
  fail "缺少 9 张真实街景误判证据回归"
rg -q '约 1\.8%' "$spec" ||
  fail "人物主题规格未记录 1.8% 面积门槛"
rg -q '约 10%' "$spec" ||
  fail "人物主题规格未记录 10% 显著区域门槛"
rg -q '人物 0 张、风景 159 张、读取失败 0 张' "$classification" ||
  fail "验收记录缺少当前项目完整复扫结果"
rg -A2 '## PC-38 街景人物误判收紧' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-38 尚未标记完成"

printf 'PC-38 检查通过：街景背景路人按绝对面积和显著区域占比归为风景。\n'
