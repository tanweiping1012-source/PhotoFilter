import SwiftUI

struct PrivacyInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("隐私与数据")
                    .font(.title2.weight(.bold))
                Text("最后更新：2026 年 8 月 18 日")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("本地处理") {
                    PrivacyDisclosureRow(
                        icon: "folder.badge.plus",
                        title: "你选择的照片文件夹",
                        detail: "原照片只读。缩略图、人物主题判断、相似度指纹与技术质量分析都在本机完成，不会写回原文件。"
                    )
                    PrivacyDisclosureRow(
                        icon: "externaldrive",
                        title: "项目状态",
                        detail: "本机仅保存安全书签、项目名、照片数量、人物/风景目标、相对路径人工决定、用户分类纠正和当前选中项。"
                    )
                    PrivacyDisclosureRow(
                        icon: "key",
                        title: "AI 供应商 API Key",
                        detail: "每个供应商的 Key 独立保存在此 Mac 的 Keychain，不写入项目状态、日志或导出文件；发起 AI 请求时只用于所选供应商的鉴权请求头。"
                    )
                }

                Section("可选 AI评分") {
                    PrivacyDisclosureRow(
                        icon: "hand.raised",
                        title: "每次发送前确认",
                        detail: "只有你在确认弹窗中点击发送，App 才会发送评分照片。弹窗说明模型、张数和照片类型；当前供应商、模型与预览尺寸常驻侧栏 AI评分区。"
                    )
                    PrivacyDisclosureRow(
                        icon: "photo",
                        title: "发送的数据",
                        detail: "每次请求发送 2–5 张同类型照片的匿名 JPEG 预览；最长边由你选择为小 512px、中 1024px 或大 1536px。始终不发送原图、文件名、本地路径或 EXIF/GPS。"
                    )
                    PrivacyDisclosureRow(
                        icon: "network",
                        title: "第三方处理方",
                        detail: "评分图片只发送给本次选择的火山方舟、MiniMax、OpenAI、Anthropic、Google、阿里云百炼、xAI、Kimi、智谱、腾讯混元或自定义兼容接口。供应商可通过你的 API Key 将调用关联到对应账号；同一组照片不会同时发送给多个服务。"
                    )
                    PrivacyDisclosureRow(
                        icon: "checkmark.shield",
                        title: "其他会联网的操作",
                        detail: "“验证并保存”和“验证已保存的 Key”会向所选模型发送 1 张内置测试图，测试图不来自你的照片；“刷新账号模型”只读取 OpenAI / Anthropic 账号可见的模型 ID，不发送图片，也不保存模型列表。两者都只在你点击时发生。"
                    )
                }

                Section("不跟踪") {
                    PrivacyDisclosureRow(
                        icon: "eye.slash",
                        title: "无广告与分析 SDK",
                        detail: "App 不建立用户账号，不收集位置、联系人或设备广告标识，不做跨 App 或网站跟踪。"
                    )
                }

                Section("你的控制") {
                    PrivacyDisclosureRow(
                        icon: "trash",
                        title: "删除项目",
                        detail: "删除项目会移除 App 内的项目状态并释放缩略图缓存，不会删除、移动或修改原照片。"
                    )
                    PrivacyDisclosureRow(
                        icon: "square.and.arrow.up",
                        title: "导出副本",
                        detail: "导出目录由你选择；人物和风景照片分别复制到两个子目录，并生成 selection.json、selection.csv。"
                    )
                    PrivacyDisclosureRow(
                        icon: "gearshape",
                        title: "删除 API Key",
                        detail: "可随时在 AI评分设置中分别删除各供应商保存在此 Mac Keychain 中的 Key。"
                    )
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PrivacyDisclosureRow: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
