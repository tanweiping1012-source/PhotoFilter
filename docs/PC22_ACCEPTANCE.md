# PC-22 连续选片交互验收

## 解决的问题

- AI评分只保留完整候选池入口，避免局部评分与最终评分重复。
- 解决只能凭 130pt 缩略图判断照片的问题。
- AI评分设置不再依赖活动项目，也不再只用小齿轮表达。
- 顶部长风险与 AI 理由移入照片详情，避免挤压筛选器。
- 撤销按钮和菜单现在反映真实撤销栈状态。

完整审计与设计依据见 `INTERACTION_AUDIT.md`。

## 用户可见效果

### 全局 AI 设置

- 侧栏项目创建区提供唯一“AI评分设置”入口。
- 没有照片项目时也可选择模型和保存供应商 Key。
- 活动项目 AI 区只展示当前模型和任务状态，不再显示重复齿轮。
- 样例练习隐藏设置入口，继续保证练习模式不读取 Keychain。

### 完整 AI评分

- 侧栏只提供当前人物或风景候选池的完整 AI评分入口。
- 相似照片局部评分入口已移除，避免产生两套评分结果和两套发送确认。
- 完整评分继续显示实际供应商、模型、照片数、尺寸和 AI 预览隐私边界。

### 大图预览

- 双击照片卡、按空格或点击“预览”打开。
- 预览使用 `ThumbnailCache` 在后台生成最长边 1600px 的本地只读图像。
- 左右按钮和方向键只遍历打开时的当前筛选结果。
- 右侧集中展示决定、拍摄时间、相似照片位置、技术风险和完整 AI评分结果。
- 底部可保留、淘汰、恢复待定；决定与主网格和快捷键共享 ViewModel。

### 响应式顶栏

- 完整宽度显示文件名、短摘要、AI评分、预览和决定。
- 窄窗口通过 `ViewThatFits` 将 AI评分、预览和决定切换为图标；英文决定不会再显示截断的 `Undecid…`。
- 完整风险与理由不再占用顶栏。

## 验收证据

- `interaction-screenshots/photo-preview-zh-Hans.png`
- `interaction-screenshots/photo-preview-en.png`
- `interaction-screenshots/main-window-en-920x640.png`

所有图像只使用 App 内置程序化 Demo 素材。

## 自动验证

- 当前完整套件 92 项 Swift 测试，0 失败。
- 新增预览导航测试：当前筛选顺序、首尾边界、选中项不在筛选内的回退。
- Demo 测试新增撤销状态：空栈禁用、做决定后启用、撤销后再次禁用。
- `scripts/check-pc22.sh` 检查全局设置、完整 AI评分、双击/空格预览、1600px 解码、无障碍标识、撤销状态和隐私边界。
- `scripts/check.sh`、隐私、Demo、PC-19、PC-21、PC-22 门禁和 Xcode Debug 构建全部通过。

## 交付

- 通用 Archive：`dist/PhotoCurator-PC22-final.xcarchive`
- 非公证 DMG：`dist/PhotoCurator-0.3.0-macOS-universal.dmg`
- 架构：`arm64 + x86_64`
- DMG SHA-256：`86f5a5a8e40651cd78062c7aafc4cc2aa6bcdc4af6c829ebb7230a0ae3d81405`
