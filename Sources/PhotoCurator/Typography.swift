import SwiftUI

/// 全 App 的字阶。
///
/// 规则只有两条，但必须守住：同一角色在任何区块里都用同一级；一行内配对的
/// 标签与数值也必须同级。
///
/// 这套字阶原来只管侧栏（`SidebarTypography`），主内容区没有任何约定：状态行
/// subheadline、可见张数 callout、回执标题 subheadline.semibold、回执正文
/// callout、底栏文件名 caption.medium、摘要 caption2、任务条又是另一套……
/// 同一屏上十来种字号，看上去就像每处都是随手挑的。
///
/// 少数确实需要跳出字阶的地方单独命名（`scoreDisplay` / `entryLabel` /
/// `guideIcon` / `bulletDot`），这样"例外"是被声明出来的，而不是又一次裸写。
enum Typography {
    /// 面板标题：侧栏顶部"照片筛选项目"及其副标题，整个 App 只此一处
    static let paneTitle = Font.title2.weight(.bold)
    static let paneSubtitle = Font.caption

    /// 区块标题：项目 / 保留目标 / AI评分 / 大图页标题
    static let sectionTitle = Font.headline

    /// 行主体：类别名、项目名、文件名、状态行，以及一行内配对的数值
    static let rowLabel = Font.subheadline.weight(.medium)
    static let rowLabelActive = Font.subheadline.weight(.semibold)
    static let rowValue = Font.subheadline.monospacedDigit()

    /// 明细：计数、进度、运行状态、回执正文、教学说明
    static let detail = Font.caption
    static let detailNumeric = Font.caption.monospacedDigit()
    /// 明细里的小标题，例如"第一次筛选""五维评分"
    static let detailEmphasis = Font.caption.weight(.semibold)

    /// 脚注：不可用原因、当前模型档位、token 用量
    static let footnote = Font.caption2
    /// 照片卡角标：相似 1/3、严重过曝、AI 92 分
    static let badge = Font.caption2.weight(.semibold)

    /// 侧栏入口按钮：`.borderedProminent` 会把标题加粗，必须显式固定，
    /// 否则它和相邻的 `.bordered` 不一致。
    static let entryLabel = Font.body

    /// 大图里的总分：全 App 唯一的展示级数字，故意比正文大一档。
    static let scoreDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    /// 任务条的步骤图标。
    static let guideIcon = Font.system(size: 20, weight: .semibold)
    /// 分隔用的小圆点，不是文字。
    static let bulletDot = Font.system(size: 5)
    /// 教学指针的手形图标。
    static let guidePointer = Font.system(size: 20, weight: .bold)

    /// 等宽正文：endpoint、model ID 这类必须逐字符看清、不能连字的内容。
    static let code = Font.caption.monospaced()

    /// 场景首页：整个 App 只有"第一次筛选"这一屏用，它要立住一句主张。
    static let heroIcon = Font.system(size: 48, weight: .regular)
    static let heroTitle = Font.title.weight(.semibold)
    static let heroBody = Font.body
    static let heroStepIcon = Font.system(size: 18, weight: .medium)
}
