# PC-31 AI评分照片进度验收

## 交付结果

- 侧栏运行状态从“第 N / M 批”改为“已评估 X / Y 张”。
- 进度条使用已通过校验的照片数计算，不再使用已完成请求次数。
- 当前请求显示“正在评估第 A–B 张，共 Y 张”。
- 失败恢复显示“重试第 A–B 张”。
- 开始操作显示“开始 AI评分（Y 张）”。
- 离线教学显示“离线演示 X / 8 张”。
- 发送确认不展示总请求次数，改为说明每次请求发送 2–5 张、请求间隔和预计耗时。

## 正确性

- `AIFinalSelectionRunProgress` 新增 `completedPhotoCount`。
- 一组结果完整通过 Validator 后，进度增加该组实际照片数。
- 自动重试不会重复增加照片进度。
- 不均匀分组通过 `photoRange(forGroupAt:)` 映射为连续照片范围。
- 完整运行结束时，`completedPhotoCount == candidatePhotoCount`。
- 内部请求分组、60 秒间隔、暂停、重试和费用逻辑保持不变。

## 用户表达

- 主界面、大图教学、隐私说明、无障碍文案和 String Catalog 不再包含“批”。
- 评分详情阶段标题由“AI评分批次”改为“AI评分”。
- 公开 README、隐私政策、新手教学和审核说明均按照片数量表达。

## 自动与视觉验收

- `swift test`：101 项测试，0 失败。
- 照片范围覆盖均匀与不均匀分组。
- 进度比例验证为 `completedPhotoCount / candidatePhotoCount`。
- String Catalog：394/394 英文完整，0 stale，0 个“批”键。
- 原型：
  - `docs/interaction-screenshots/first-curation-ai-progress-zh-Hans-920x640.png`
  - `docs/interaction-screenshots/first-curation-ai-progress-en-920x640.png`
