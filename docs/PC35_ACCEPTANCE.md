# PC-35 第一次筛选动态聚焦与完成出口验收

## 交付结果

- 八步新手引导均使用统一红色固定边框和固定小指针，直接框选下一步需要操作的真实区域。
- 主红框使用严格贴合控件的固定内描边，不向外扩张、不缩放、没有光晕；小指针也不移动。
- 聚焦组件没有 `withAnimation`、无限循环或任何几何动画；同一步内坐标保持不变，只在进入下一步时瞬时切换目标。
- 聚焦层不拦截鼠标、键盘或无障碍操作。
- 离线 AI评分完成后自动关闭大图并返回照片网格，第 5 步直接聚焦顶部人物/风景选择器。
- “确认结果”步骤先恢复“全部照片”，再指向任务条中的“显示评分优先照片”主按钮；点击后转为“采纳评分结果”按钮。
- 导出成功后进入明确完成状态，并显示“结束新手引导”主按钮。
- 点击结束按钮会退出示例项目并恢复进入教学前的真实项目；没有历史项目时返回空白工作区。
- “开始整理我的照片”保留为次按钮，用于退出示例后直接选择真实照片文件夹。

## 聚焦目标

1. 顶部人物/风景选择器，用于先选择人物。
2. 当前选中的人物照片卡。
3. 大图底部“保留”按钮。
4. 任务条中的“演示 AI评分”按钮。
5. 自动返回照片网格后的顶部人物/风景选择器，用于切换到风景。
6. 已评分风景照片；打开大图后切换到“评分已查看，继续”主按钮，点击即返回网格。
7. 任务条中的“显示评分优先照片”主按钮；点击后转移到“采纳评分结果”按钮。
8. 底部分类导出按钮。
9. 完成状态中的“结束新手引导”主按钮。

## 验收结果

- `swift test`：130 项测试，0 失败。
- `scripts/check-pc35.sh`：八步聚焦、零动画固定坐标、条件目标切换、结束按钮、状态测试和视觉快照全部通过。
- `scripts/check.sh`：隐私、演示、PC-19 至 PC-37 门禁全部通过。
- String Catalog：457/457 英文完整，0 stale。
- Xcode Debug：`BUILD SUCCEEDED`。
- 中英文 920×640 网格与 960×680 大图快照无明显截断、重叠或目标错位。

## 界面快照

- 照片卡聚焦：`docs/interaction-screenshots/first-curation-spotlight-card-zh-Hans-920x640.png`
- 大图保留按钮聚焦：`docs/interaction-screenshots/first-curation-spotlight-keep-zh-Hans.png`
- 大图保留按钮另一动画相位：`docs/interaction-screenshots/first-curation-spotlight-keep-phase-b-zh-Hans.png`
- 评分详情明确继续按钮：`docs/interaction-screenshots/first-curation-score-continue-zh-Hans.png`
- 中文显示评分优先照片按钮：`docs/interaction-screenshots/first-curation-show-scoring-picks-zh-Hans-920x640.png`
- 英文显示评分优先照片按钮：`docs/interaction-screenshots/first-curation-show-scoring-picks-en-920x640.png`
- 中文完成状态：`docs/interaction-screenshots/first-curation-finish-zh-Hans-920x640.png`
- 英文完成状态：`docs/interaction-screenshots/first-curation-finish-en-920x640.png`
