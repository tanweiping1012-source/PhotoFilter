#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  printf 'PC-41 检查失败：%s\n' "$1" >&2
  exit 1
}

weights="Sources/PhotoCurator/AestheticScoreWeights.swift"
contract="Sources/PhotoCurator/AestheticReviewContract.swift"
run="Sources/PhotoCurator/AIFinalSelectionRun.swift"
catalog_config="Sources/PhotoCurator/AIModelCatalog.swift"
planner="Sources/PhotoCurator/LocalAestheticCandidatePlanner.swift"
prompt="Sources/PhotoCurator/ArkAestheticReviewClient.swift"
content="Sources/PhotoCurator/ContentView.swift"
preview="Sources/PhotoCurator/PhotoPreviewView.swift"
view_model="Sources/PhotoCurator/PhotoLibraryViewModel.swift"
privacy="Sources/PhotoCurator/PrivacyInformationView.swift"
project="PhotoCurator.xcodeproj/project.pbxproj"
weight_tests="Tests/PhotoCuratorTests/AestheticScoreWeightsTests.swift"
run_tests="Tests/PhotoCuratorTests/AIFinalSelectionRunTests.swift"

# ---------------------------------------------------------------------------
# 一、总分由五维和用户权重在本地算出，模型不再返回总分
# ---------------------------------------------------------------------------

[[ -f "$weights" ]] || fail "缺少五维权重模型"
rg -q "$(basename "$weights")" "$project" ||
  fail "五维权重模型没有加入 Xcode target"

# 模型每多返回一个数字就多一个独立的随机变量。总分是用户唯一看得见的数字，
# 却是最不受约束的那个，因此必须从协议里彻底消失。
if rg -q 'let score: Int' "$contract"; then
  fail "评分契约仍然保存模型返回的总分"
fi
if rg -q '"score"' \
  Sources/PhotoCurator/AnthropicAestheticReviewClient.swift \
  Sources/PhotoCurator/ArkAestheticReviewClient.swift \
  Sources/PhotoCurator/MiniMaxAestheticReviewClient.swift \
  Sources/PhotoCurator/OpenAICompatibleAestheticReviewClient.swift; then
  fail "某个客户端的结构化输出 schema 仍要求 score"
fi
rg -q '不要返回总分、综合分、加权分或名次' "$prompt" ||
  fail "Prompt 没有明确禁止模型返回总分"
rg -q 'func total\(with weights: AestheticScoreWeights\) -> Int' "$contract" ||
  fail "评分记录没有提供按权重计算的总分"

# 总分必须是纯整数运算：一旦引入浮点，同样的输入在不同机器上可能得出不同的分数，
# 而"把总分收回本地"换来的正是确定性。
awk '/^enum AestheticScoreTotal \{/,/^\}/' "$weights" |
  rg -q '\(2 \* weightedSum \+ weightSum\) / \(2 \* weightSum\)' ||
  fail "加权总分没有使用整数四舍五入"
awk '/^enum AestheticScoreTotal \{/,/^\}/' "$weights" |
  rg -q 'Double|Float|rounded\(\)' &&
  fail "加权总分引入了浮点运算" || true

rg -q 'isDegenerate \? AestheticScoreWeights.balanced : weights' "$weights" ||
  fail "权重全为 0 时没有退回等权，存在除以 0 的风险"
rg -q 'static let balanced = AestheticScoreWeights' "$weights" ||
  fail "缺少等权默认值"
rg -q 'enum AestheticScoreWeightsStore' "$weights" ||
  fail "权重没有持久化"

# 排序必须和展示用同一套权重，否则会出现"分数更低的那张反而排在前面"。
rg -q 'weights: AestheticScoreWeights' "$run" ||
  fail "全局排序没有接收权重"
rg -q 'weights: aestheticScoreWeights' "$view_model" ||
  fail "运行结束时的排序没有使用当前权重"
rg -q '@Published var aestheticScoreWeights: AestheticScoreWeights' "$view_model" ||
  fail "权重不是可观察状态，界面不会随调整刷新"
rg -q 'AestheticScoreWeightsStore.save\(aestheticScoreWeights\)' "$view_model" ||
  fail "权重调整没有持久化"

# 权重是"看结果时的旋钮"：维度分已经买断，重新拖动不该再发一次请求。
rg -q 'ai\.weights' "$content" ||
  fail "缺少权重调节控件"
for dimension in moment composition subject lighting storytelling; do
  rg -Fq "ai.weight.\\(dimension.rawValue)" "$content" ||
    fail "权重控件缺少稳定无障碍标识"
done
rg -q '调整权重只重新计算总分和排序，不会重新评分，也不产生任何费用。' "$content" ||
  fail "权重控件没有说明调整不会重新评分或产生费用"

# 「评分权重」和保留目标里的人物/风景是同一个角色：都是带滑杆的偏好设定。
# 用 detail + secondary 会让它掉进相邻两行灰色明细里，既不像标题也不像控件。
awk '/^private struct AestheticScoreWeightsControl: View \{/,/^\}/' "$content" |
  rg -q 'Label\("评分权重", systemImage:' ||
  fail "权重控件的折叠行不是图标加标签的可交互行样式"
# 标签和字阶分在相邻两行，正则跨不过换行；用 awk 在标签之后寻找字阶。
awk '/Label\("评分权重", systemImage:/{found = 1; next}
     found && /\.font\(Typography\.rowLabel\)/{ok = 1}
     END{exit ok ? 0 : 1}' "$content" ||
  fail "权重控件没有使用可交互行的字阶 rowLabel"
awk '/^private struct AestheticScoreWeightsControl: View \{/,/^\}/' "$content" |
  rg -q 'Text\("评分权重"\)' &&
  fail "权重控件仍在用纯文本标签" || true
rg -q 'private var isCustomized: Bool' "$content" ||
  fail "折叠状态下看不出权重是否被改过"

# 只读明细必须排在可交互内容之后，否则控件会被当成第三行说明文字。
awk '/AestheticScoreWeightsControl\(\)/{weights=NR}
     /library.selectedAIModel.providerAndModelDisplayName/{model=NR}
     /library.latestAIUsageMessage/{usage=NR}
     END{exit (weights && model && usage && weights < model && weights < usage) ? 0 : 1}'   "$content" ||
  fail "权重控件仍夹在模型档位与 token 用量两行明细之间"

# 大图评分面板只放路标，不放第二个控件——同一功能不得有两个入口。
rg -q 'photo-preview\.score\.weights-hint' "$preview" ||
  fail "大图评分面板缺少指向权重控件的说明"
if rg -q 'Slider\(' "$preview"; then
  fail "大图评分面板出现了第二个权重控件"
fi
rg -q 'ai\.weight\.degenerate' "$content" ||
  fail "权重全为 0 时没有给出提示"
rg -q 'recommendation\.total\(with: weights\)' "$content" ||
  fail "网格徽章没有按权重显示总分"
rg -q 'let aestheticScoreWeights: AestheticScoreWeights' "$content" ||
  fail "照片卡片应显式接收权重，不应订阅整个 view model"
rg -q 'weight == 0' "$preview" ||
  fail "评分详情没有标出未计入总分的维度"

# ---------------------------------------------------------------------------
# 二、每次请求只送一张照片
# ---------------------------------------------------------------------------

rg -q 'static let maximumPhotosPerReview = 1' "$catalog_config" ||
  fail "每次请求不是只送一张照片"
rg -q 'static let candidatePoolMultiplier = 5' "$catalog_config" ||
  fail "候选池倍数没有独立于传输窗口容量"
rg -q 'remainingSelectionCount \* AIReviewConfiguration.candidatePoolMultiplier' "$planner" ||
  fail "候选池规模仍复用传输窗口容量，窗口改小会让 AI 失去挑选空间"

# 窗口容量为 1 时，"避免最后落单一张"会算出 windowSize = 0，游标不前进，规划死循环。
awk '/static func makePlan\(/,/^    }/' "$run" |
  rg -q 'let avoidsTrailingSinglePhoto = windowCapacity >= 2' ||
  fail "窗口容量为 1 时没有关闭落单尾部规则，规划会死循环"
awk '/static func makePlan\(/,/^    }/' "$run" |
  rg -q 'let windowCapacity = max\(1, maximumPhotosPerReview\)' ||
  fail "窗口容量没有下限保护"

rg -q '每次请求只发送 1 张' "$privacy" ||
  fail "隐私说明没有按每次一张更新发送边界"

rg -q 'testEveryCandidateBecomesItsOwnRequest' "$run_tests" ||
  fail "缺少每张照片单独成为一次请求的测试"
rg -q 'testSinglePhotoWindowTerminatesForEveryCandidateCount' "$run_tests" ||
  fail "缺少单张窗口不死循环的测试"

# ---------------------------------------------------------------------------
# 三、回归测试
# ---------------------------------------------------------------------------

[[ -f "$weight_tests" ]] || fail "缺少权重回归测试"
for test_case in \
  testTotalIsDeterministicForTheSameInput \
  testUniformDimensionsGiveTheSameTotalUnderAnyWeights \
  testWeightsChangeWhichPhotoRanksFirst \
  testAllZeroWeightsFallBackToEqualWeighting \
  testHalfValuesRoundUp \
  testWeightsAreClampedOnInitAndOnDecode \
  testWeightsSurviveAStoreRoundTrip \
  testChangingWeightsDoesNotMutateStoredDimensions; do
  rg -q "$test_case" "$weight_tests" ||
    fail "缺少测试：$test_case"
done
rg -q 'testModelSuppliedTotalScoreIsIgnored' \
  Tests/PhotoCuratorTests/AestheticReviewContractTests.swift ||
  fail "缺少模型自行返回总分必须被丢弃的测试"

for key in \
  评分权重 \
  恢复等权; do
  rg -q "\"$key\"" scripts/localization-pc41-en.json ||
    fail "缺少英文翻译：$key"
  rg -q "\"$key\"" Resources/Localizable.xcstrings ||
    fail "String Catalog 缺少：$key"
done

printf 'PC-41 检查通过：总分由五维与用户权重在本地算出，每次请求只送一张照片。\n'
