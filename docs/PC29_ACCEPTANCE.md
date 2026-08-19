# PC-29 第一次筛选任务教学验收

## 交付结果

- 首次弹窗从四页功能轮播改为单页场景入口，说明旅行结束后整理同一天或同一段行程照片的用途。
- 用户可选择“体验一次完整筛选”“选择我的照片”或“稍后再说”。
- 完整体验在真实照片网格和大图预览中完成六项任务：
  1. 打开任意照片；
  2. 人工标记保留；
  3. 运行离线 AI评分；
  4. 查看评分解释；
  5. 采纳评分优先照片；
  6. 导出副本。
- 任务条是全宽界面带，不遮挡照片；网格与大图共享同一状态。
- 导出完成后提供“开始整理我的照片”，可直接进入真实文件夹选择。

## 离线评分

- 8 张内置照片初始没有评分，`aiFinalSelectionPhotoIDs` 为空。
- 用户主动点击“演示 AI评分”后，固定结果以 450ms 间隔逐步写入，界面按已评估照片数展示进度。
- 每次写入的照片继续使用通过正式 Validator 和 Applier 的评分详情。
- 演示路径不访问 URLSession、Keychain 或供应商配置，不消耗 API 额度。
- 用户实际打开并人工保留的照片在评分后继续保留；其余样例按独立分数全局排序并补足 3 张，采纳后恰好达到保留目标 4。
- 退出示例或切换真实项目时，任务、进度和固定结果状态全部清理。

## 自动验收

- `swift test`：97 项测试，0 失败。
- `scripts/check-pc26.sh`：通过。
- `scripts/check-pc29.sh`：通过。
- String Catalog：395/395 英文完整，0 stale。
- 未使用用户 API Key 发起任何请求。

## 界面原型

- 场景入口：`docs/interaction-screenshots/first-curation-entry-zh-Hans.png`
- 第一项任务：`docs/interaction-screenshots/first-curation-task-zh-Hans-920x640.png`
- 离线评分进度：`docs/interaction-screenshots/first-curation-ai-progress-zh-Hans-920x640.png`
- 查看评分任务：`docs/interaction-screenshots/first-curation-score-review-zh-Hans.png`
- 对应英文原型使用相同文件名并以 `-en` 标识。

中英文原型均无截断、重叠或不可见主操作。
