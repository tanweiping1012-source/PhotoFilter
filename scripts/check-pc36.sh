#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-36 检查失败：%s\n' "$1" >&2
  exit 1
}

photo_item="Sources/PhotoCurator/PhotoItem.swift"
subject_classifier="Sources/PhotoCurator/PeopleSubjectClassifier.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
contract="Sources/PhotoCurator/AestheticReviewContract.swift"
prompt="Sources/PhotoCurator/ArkAestheticReviewClient.swift"
export_service="Sources/PhotoCurator/ExportService.swift"
onboarding="Sources/PhotoCurator/OnboardingView.swift"
demo="Sources/PhotoCurator/DemoModeLibrary.swift"

for category in people scenery; do
  rg -q "case $category" "$photo_item" ||
    fail "照片类型缺少 $category"
done
rg -q 'VNDetectHumanRectanglesRequest' "$subject_classifier" ||
  fail "本地分类没有检测人物"
rg -q 'VNDetectFaceCaptureQualityRequest' "$subject_classifier" ||
  fail "本地分类没有人脸质量判断"
rg -q 'isCurationCategoryUserAssigned' \
  "$photo_item" Sources/PhotoCurator/PhotoAnalysisMerger.swift ||
  fail "后台分析可能覆盖人工分类"

rg -Uq 'Picker\([[:space:]\n]*"照片类型"' "$content" ||
  fail "主界面缺少照片类型选择"
rg -q 'pickerStyle\(\.segmented\)' "$content" ||
  fail "照片类型不是三段选择"
for identifier in \
  photo.curation-scope \
  photo-preview.curation-category; do
  rg -Fq "\"$identifier\"" "$content" "$preview" ||
    fail "缺少无障碍标识：$identifier"
done
rg -Fq '"selection.target.\(category.rawValue)"' "$content" ||
  fail "分类目标缺少稳定动态无障碍标识"

rg -q 'PhotoSelectionTargets\(people: 6, scenery: 6\)' \
  "$photo_item" ||
  fail "默认人物/风景目标不是 6/6"
rg -q 'selectionTargets: PhotoSelectionTargets\?' \
  Sources/PhotoCurator/ProjectPersistence.swift ||
  fail "分类目标没有项目迁移字段"
rg -q 'categoryOverridesByRelativePath' \
  Sources/PhotoCurator/ProjectPersistence.swift "$view_model" ||
  fail "人工分类纠正没有按相对路径持久化"

rg -q 'static let version = "v3"' "$contract" ||
  fail "评分契约没有升级到 v3"
rg -q 'let category: PhotoCurationCategory\?' "$contract" ||
  fail "评分 scope 缺少照片类型"
rg -q '表情、姿态、互动' "$prompt" "$photo_item" ||
  fail "人物评分重点缺失"
rg -q '空间层次、构图、光线' "$prompt" "$photo_item" ||
  fail "风景评分重点缺失"
rg -q 'category: category' Sources/PhotoCurator/AIFinalSelectionRun.swift ||
  fail "传输窗口没有锁定照片类型"
rg -q 'aiFinalSelectionPhotoIDsByCategory' "$view_model" ||
  fail "人物与风景没有独立最终集合"
rg -q 'aiFinalSelectionRunProgressByCategory' "$view_model" ||
  fail "人物与风景没有独立运行状态"

rg -q 'func copyCategorized' "$export_service" ||
  fail "缺少分类导出"
rg -q 'CategorizedExportManifest' "$export_service" ||
  fail "分类导出缺少根清单"
rg -q 'PhotoCurationCategory\.allCases' "$export_service" ||
  fail "导出没有分别创建人物和风景目录"

rg -q 'case choosePeople' "$onboarding" ||
  fail "新手引导缺少选择人物步骤"
rg -q 'case switchToScenery' "$onboarding" ||
  fail "新手引导缺少切换风景步骤"
rg -q 'static let taskCount = 8' "$onboarding" ||
  fail "新手引导不是八步"
rg -Uq 'PhotoSelectionTargets\([[:space:]\n]*people: 2' \
  "$demo" ||
  fail "教学人物目标不是 2 张"
rg -q 'curationCategory: index < 4 \? \.people : \.scenery' \
  "$demo" ||
  fail "教学样例不是 4 张人物和 4 张风景"

for test_name in \
  testPlannerCarriesOneCategoryAcrossEveryTransferWindow \
  testPeopleAndSceneryUseDifferentScoringInstructions \
  testAnalysisDoesNotOverwriteUserAssignedCategory \
  testCategorizedExportCreatesPeopleAndSceneryFolders \
  testViewModelRestoresTargetAndRelativeDecisionsAcrossLaunches; do
  rg -q "$test_name" Tests/PhotoCuratorTests ||
    fail "缺少回归测试：$test_name"
done

for document in \
  AGENTS.md \
  README.md \
  docs/product/CURATION_SCOPES.md \
  docs/engineering/DATA_CONTRACTS.md \
  docs/product/ONBOARDING.md \
  docs/product/OVERVIEW.md \
  docs/engineering/TASKS.md; do
  rg -q '人物' "$document" ||
    fail "$document 未记录人物筛选"
  rg -q '风景' "$document" ||
    fail "$document 未记录风景筛选"
done

rg -A2 '## PC-36 人物与风景分开筛选' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-36 尚未标记完成"

for screenshot in \
  docs/interaction-screenshots/people-scenery-guide-en-920x640.png \
  docs/interaction-screenshots/people-scenery-results-zh-Hans-920x640.png \
  docs/interaction-screenshots/people-scenery-results-en-920x640.png; do
  [[ -s "$screenshot" ]] ||
    fail "缺少人物/风景视觉验收快照：$screenshot"
  file "$screenshot" |
    rg -Fq 'PNG image data, 1840 x 1280' ||
    fail "人物/风景快照尺寸不正确：$screenshot"
done

printf 'PC-36 检查通过：本地分类、双目标、分类评分、人工纠正、双目录导出和八步教学一致。\n'
