#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-37 检查失败：%s\n' "$1" >&2
  exit 1
}

classifier="Sources/PhotoCurator/PeopleSubjectClassifier.swift"
tests="Tests/PhotoCuratorTests/PeopleSubjectClassifierTests.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"

rg -q 'PeopleSubjectClassifier.swift in Sources' "$project" ||
  fail "人物主题分类器未加入 Xcode target"
rg -q 'struct PeopleSubjectEvidence' "$classifier" ||
  fail "分类器没有可测试的本地证据模型"
rg -q 'enum PeopleSubjectEvaluator' "$classifier" ||
  fail "人物主题规则没有与 Vision 采集层分离"

rg -q 'VNDetectHumanRectanglesRequest' "$classifier" ||
  fail "缺少完整人体检测"
rg -q 'upperBodyOnly = false' "$classifier" ||
  fail "人体检测仍只检测上半身"
rg -q 'VNDetectFaceCaptureQualityRequest' "$classifier" ||
  fail "缺少人脸捕获质量"
rg -q 'VNDetectFaceCaptureQualityRequestRevision3' "$classifier" ||
  fail "人脸质量没有使用 macOS 14 稳定版本"
rg -q 'VNGeneratePersonSegmentationRequest' "$classifier" ||
  fail "缺少剪影人物分割"
rg -q 'VNGeneratePersonInstanceMaskRequest' "$classifier" ||
  fail "缺少背景人群实例计数"
rg -q 'qualityLevel = \.fast' "$classifier" ||
  fail "边界分类没有使用快速人物分割"
rg -q 'VNGenerateAttentionBasedSaliencyImageRequest' "$classifier" ||
  fail "缺少人物风景显著性判断"
rg -q 'VNGenerateAttentionBasedSaliencyImageRequestRevision2' \
  "$classifier" ||
  fail "显著性没有使用 macOS 14 版本"

rg -q 'case clearPortrait' "$classifier" ||
  fail "缺少清晰人像路径"
rg -q 'case dominantPerson' "$classifier" ||
  fail "缺少大比例人物主体路径"
rg -q 'case personInLandscape' "$classifier" ||
  fail "缺少人物风景或剪影路径"
rg -q 'case incidentalPeople' "$classifier" ||
  fail "缺少背景路人排除结果"
rg -q 'minimumPersonSaliencyCoverage' "$classifier" ||
  fail "人物风景没有人物区域显著性阈值"
rg -q 'minimumSalientRegionConcentration' "$classifier" ||
  fail "人物风景没有显著区域集中度阈值"
rg -q 'maximumLandscapePeopleCount' "$classifier" ||
  fail "背景人群没有人数限制"
rg -q 'maskSupports' "$classifier" ||
  fail "无脸人物没有人物分割佐证"
rg -q 'minimumSilhouetteAspectRatio' "$classifier" ||
  fail "纯分割剪影没有人形几何约束"

for test_name in \
  testTinyBackgroundPersonRemainsScenery \
  testClearFrontFacingPortraitIsPeople \
  testClearSideFacingPortraitIsPeople \
  testLargeFacelessPersonIsStillSubject \
  testSalientPersonInLandscapeIsPeople \
  testSegmentationOnlySilhouetteCanBePeople \
  testSegmentationOnlyWithoutInstanceRemainsScenery \
  testHorizontalSegmentationOnlyMaskRemainsScenery \
  testDominantHumanWithoutMaskSupportRemainsScenery \
  testBroadSaliencyNeedsMeaningfulPersonConcentration \
  testSmallPersonWithoutSaliencyRemainsScenery \
  testBackgroundCrowdRemainsScenery \
  testMergedCrowdMaskUsesInstanceCountAndRemainsScenery \
  testExtremeEdgeSilhouetteRemainsScenery; do
  rg -q "$test_name" "$tests" ||
    fail "缺少人物主题回归测试：$test_name"
done

for document in \
  AGENTS.md \
  README.md \
  docs/PEOPLE_SUBJECT_CLASSIFICATION.md \
  docs/PC37_ACCEPTANCE.md \
  docs/PEOPLE_SCENERY_CURATION.md \
  docs/DATA_CONTRACTS.md \
  docs/PRIVACY_POLICY.md \
  docs/PRODUCT.md \
  docs/TASKS.md; do
  rg -q '人物主题|视觉主题' "$document" ||
    fail "$document 未记录人物主题语义"
done

rg -A2 '## PC-37 人物主题本地识别' docs/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-37 尚未标记完成"

printf 'PC-37 检查通过：人物主题语义、清晰人像、显著剪影和背景路人排除规则一致。\n'
