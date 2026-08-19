# PC-19 验收记录

## 完成范围

- App Icon：`AppIcon.appiconset` 包含 16、32、64、128、256、512、1024px PNG，Xcode Target 使用 `AppIcon`。
- 本地化：当前 `Localizable.xcstrings` 的 353 个运行时键均有英文；`InfoPlist.xcstrings` 提供简体中文和英文 App 名称。
- 无障碍：项目、状态、筛选器、AI 状态、照片卡和底部命令均提供稳定 identifier；照片卡读出决定、分组、风险和 AI评分结果。
- 键盘：照片卡可聚焦并使用方向键移动；`P`、`X`、`U` 和 `Command-Z` 通过“选片”菜单执行共享命令。
- 窗口：默认 1200×800，最小 920×640；底部命令在窄窗口自动切换为带 tooltip 和无障碍标签的图标。
- 支持入口：侧栏提供“帮助与支持”，覆盖权限、AI、导出问题，并可复制不含照片、路径或 API Key 的诊断信息。

## 实机验收

- 简体中文与英文真实 Xcode App 均显示完整侧栏、8 张内置样例、AI 标签、状态和底部命令。
- VoiceOver 辅助功能树可读取项目状态、8 张照片的决定与 AI 标签、筛选器值及底部命令。
- 从第一张照片按右方向键后，焦点和业务选中项移动到第二张；按 `P` 后第二张标记为保留，计数和状态同步更新。
- 窗口缩至 920×640 后，底栏切换为紧凑图标模式，没有文字截断或控件重叠。
- 英文 920×640 与 1280×800 下，长状态、AI 理由和侧栏说明未发生遮挡。

## 商店截图候选

- `store-screenshots/photo-curator-zh-Hans-2560x1600.png`
- `store-screenshots/photo-curator-en-2560x1600.png`

截图只使用 `Resources/DemoPhotos` 中由仓库生成器创建的固定样例，不包含真实用户照片、文件路径、账号信息或 API Key。

## 自动门禁

运行：

```bash
bash scripts/check-pc19.sh
```

该脚本检查图标尺寸、双语完整性、格式占位符、InfoPlist 名称、支持入口、核心无障碍标识、键盘/窗口适配和截图尺寸。正式公开的 App 支持 URL 仍需在拥有 App Store Connect 后配置。
