# PC-21 多供应商视觉模型验收

## 用户可见效果

- 全局入口升级为“AI评分设置”。
- 模型 Picker 只展示两个已真实接入且支持图片的模型：
  - 火山方舟 · Doubao-Seed-2.0 Lite
  - MiniMax · MiniMax-M3
- 切换模型后显示对应 API model ID、供应商和独立 Key 状态。
- 方舟与 MiniMax Key 可分别保存和删除；切换供应商不会显示另一个供应商的 Key。
- 侧栏 AI 状态和发送确认均显示本次使用的供应商与模型。

## 实现边界

- 模型选择以稳定 model ID 存入 UserDefaults，不进入照片项目状态。
- 方舟沿用既有 `ark-api-key` Keychain service；MiniMax 使用独立 `ai-api-key.minimax` service。
- 单组复核和整轮精选都在确认时锁定 model ID；运行中设置页禁止切换模型。
- 两个适配器复用相同匿名 `photo_001` ID、无元数据内存 JPEG、完整排名与本地 Validator；当时默认固定 512px，PC-23 后可由用户选择 512/1024/1536px。
- MiniMax-M3 使用中国区 `https://api.minimaxi.com/v1/chat/completions`，关闭思考，支持解析工具调用参数或纯 JSON。
- 非 2xx 或 MiniMax `base_resp` 错误只展示短机器码，不回显 `message`、`status_msg` 或响应正文。

## 自动验收

- 当前完整套件 92 项 Swift 测试，0 失败。
- MiniMax 测试覆盖：
  - API endpoint、model ID、Bearer header；
  - base64 JPEG 与匿名 photo ID；
  - 关闭思考；
  - 工具调用与 fenced JSON 两类响应；
  - token 用量；
  - provider 状态码、非法排名和安全错误码。
- 模型目录测试覆盖默认选择、偏好持久化、供应商 Keychain service 隔离和 ViewModel 供应商探针。
- Demo 回归继续证明启动时不读取任何供应商 Key、不联网、不持久化演示项目。
- `scripts/check.sh`、`check-privacy.sh`、`check-demo.sh`、`check-pc19.sh`、`check-pc21.sh` 全部通过。

## 视觉与交付

- 真实 `AISettingsView` 简中/英文离屏快照显示 MiniMax-M3、模型 ID、Key 状态与发送边界，无截断或重叠。
- 通用 Archive：`dist/PhotoCurator-PC21-final.xcarchive`
- 非公证 DMG：`dist/PhotoCurator-0.2.0-macOS-universal.dmg`
- DMG SHA-256：`43af55451bd5453d493f9a3dff88a3a01b3eb1e6ee11dac195743281ca11b316`

本次没有执行真实 MiniMax 计费请求，因为未使用用户 MiniMax API Key。真实账号联调需由用户在 App 中自行保存 Key，并在发送弹窗确认后进行。
