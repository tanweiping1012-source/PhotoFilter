#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-42 检查失败：%s\n' "$1" >&2
  exit 1
}

run="Sources/PhotoCurator/AIFinalSelectionRun.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
content="Sources/PhotoCurator/ContentView.swift"
resume_tests="Tests/PhotoCuratorTests/AIFinalSelectionResumeTests.swift"
scoring_doc="docs/ai/SCORING.md"

# ---------------------------------------------------------------------------
# 1. 待发送名单必须减去已评分照片
#
# 这是整条修复的核心。侧栏的"待评分"一直是减过的，而真正生成运行计划的那条路径没减，
# 于是停止后重新开始又把已经付过费的照片发了一遍。两条路径必须共用同一个减法。
# ---------------------------------------------------------------------------
rg -q 'func unscoredCandidatePhotoIDs\(' "$view_model" ||
  fail "缺少"候选池减去已评分"的单一入口"
awk '/func aiFinalSelectionRunPlan\(/,/^    }$/' "$view_model" |
  rg -q 'candidateLocalPhotoIDs: unscoredCandidatePhotoIDs\(' ||
  fail "运行计划没有按未评分候选生成"
awk '/func aiFinalSelectionRunPlan\(/,/^    }$/' "$view_model" |
  rg -q 'candidateLocalPhotoIDs: candidatePlan\.localPhotoIDs' &&
  fail "运行计划又用回了完整候选池，已付费照片会被重复发送"

rg -q 'func reusableAIFinalSelectionScores\(' "$view_model" ||
  fail "缺少可复用旧分数的查询入口"

# ---------------------------------------------------------------------------
# 2. 旧分数只有来源一致才复用
#
# 换过模型或预览尺寸的分数不能和新分数排进同一个名次里。来源必须与分数同一步写入，
# 只要还剩一条"能写分数但不记来源"的路径，这条规则就会被绕过。
# ---------------------------------------------------------------------------
rg -q 'struct AIFinalSelectionScoreOrigin' "$run" ||
  fail "缺少分数来源类型"
awk '/func applyAestheticReview\(/,/^    }$/' "$view_model" |
  rg -q 'aiFinalSelectionScoreOriginByCategory\[category\] = origin' ||
  fail "写入分数时没有同时记录它的来源"
origin_writes="$(rg -c 'aiFinalSelectionScoreOriginByCategory\[[a-zA-Z]+\] =' "$view_model" || true)"
[[ "${origin_writes:-0}" == "1" ]] ||
  fail "分数来源有 ${origin_writes} 处写入；它只能跟着分数一起写"
awk '/func reusableAIFinalSelectionScores\(/,/^    }$/' "$view_model" |
  rg -q 'modelID: selectedAIModelID' ||
  fail "复用旧分数时没有比对模型"
awk '/func reusableAIFinalSelectionScores\(/,/^    }$/' "$view_model" |
  rg -q 'previewSize: selectedAIPreviewSize' ||
  fail "复用旧分数时没有比对预览尺寸"

# 分数来源按类型存，而项目之间共用"人物/风景"这两个键：不跟着项目走的话，
# 在另一个项目里换模型评一轮，切回来就会把旧分数当成新模型的结果复用。
rg -q 'aiFinalSelectionScoreOriginByCategory:$' "$view_model" ||
  fail "项目快照没有携带分数来源"
rg -q 'aiFinalSelectionScoreOriginByCategory =\s*$' "$view_model" ||
  rg -q 'aiFinalSelectionScoreOriginByCategory =' "$view_model" ||
  fail "恢复项目快照时没有恢复它自己的分数来源"

# ---------------------------------------------------------------------------
# 3. 排序覆盖整个候选池
#
# 继续之后只用本轮新分数排名次，等于用半个池子决定谁被保留。
# ---------------------------------------------------------------------------
complete_body="$(awk '/private func completeAIFinalSelectionRun\(/,/^    }$/' "$view_model")"
printf '%s' "$complete_body" | rg -q 'scores: context\.allScores' ||
  fail "最终排序没有合并停止前已评过的分数"
printf '%s' "$complete_body" | rg -q 'candidatePhotoIDs: context\.rankedPhotoIDs' ||
  fail "最终排序的全集不是整个候选池"
printf '%s' "$complete_body" | rg -q 'context\.plan\.coveredPhotoIDs' &&
  fail "最终排序又退回只看本轮计划覆盖的照片"
rg -q 'var allScores: \[AIFinalSelectionScore\]' "$view_model" ||
  fail "运行上下文没有合并两段分数的入口"
rg -q 'var rankedPhotoIDs: Set<String>' "$view_model" ||
  fail "运行上下文没有给出参与排序的全集"

# ---------------------------------------------------------------------------
# 4. 界面上的数字就是会被计费的数字
# ---------------------------------------------------------------------------
rg -q 'let alreadyScoredPhotoCount: Int' "$view_model" ||
  fail "入口状态没有暴露"已评过分、不再发送"的张数"
rg -Fq '继续\(category.title) AI评分（还剩 \(availability.candidatePhotoCount) 张）' "$content" ||
  fail "继续评分时按钮仍说"开始"，或没有只数剩余张数"
rg -Fq '已经评过分的 \(resumedCount) 张不会重新发送，也不会再次计费。' "$content" ||
  fail "发送确认框没有说明哪些照片不会被重复计费"
rg -q 'var pendingAIFinalSelectionResumedScoreCount: Int' "$view_model" ||
  fail "确认框读不到锁定时的复用张数快照"

# ---------------------------------------------------------------------------
# 5. 候选全部评完后入口不得再花一次钱
# ---------------------------------------------------------------------------
awk '/func aiFinalSelectionAvailability\(/,/^    }$/' "$view_model" |
  rg -q 'guard !unscoredPhotoIDs.isEmpty else' ||
  fail "候选全部评完后仍允许再发送一遍"

# ---------------------------------------------------------------------------
# 6. 回归测试与文档
# ---------------------------------------------------------------------------
[[ -f "$resume_tests" ]] || fail "缺少停止后继续的回归测试"
for test_name in \
  testResumingOnlyPlansUnscoredCandidates \
  testStartControlCountsOnlyWhatWillBeSent \
  testFullyScoredPoolCannotBeChargedAgain \
  testScoresFromAnotherModelAreNotReused \
  testMergedScoresRankAcrossTheWholeCandidatePool; do
  rg -q "$test_name" "$resume_tests" || fail "缺少回归测试 $test_name"
done

rg -q '## 停止之后继续' "$scoring_doc" ||
  fail "$scoring_doc 未记录停止后继续的规则"
rg -q '不得再次发送' "$scoring_doc" ||
  fail "$scoring_doc 未写明已付费照片不得重发"

rg -A2 '## PC-42 停止后继续评分不重复计费' docs/engineering/TASKS.md |
  rg -q '\*\*状态：已完成\*\*' ||
  fail "PC-42 尚未标记完成"

printf 'PC-42 检查通过：停止后继续只发送剩余照片，排序仍覆盖整个候选池。\n'
