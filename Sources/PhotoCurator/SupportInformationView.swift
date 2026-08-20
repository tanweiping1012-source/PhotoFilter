import AppKit
import SwiftUI

struct SupportInformationView: View {
    let isDemoModeActive: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var copiedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("帮助与支持")
                    .font(.title2.weight(.bold))
                Text("常见问题与非敏感诊断信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("使用帮助") {
                    SupportHelpRow(
                        icon: "folder.badge.questionmark",
                        title: "文件夹权限",
                        detail: "权限失效时，点按项目并重新选择对应文件夹；App 不会尝试绕过系统授权。"
                    )
                    SupportHelpRow(
                        icon: "wand.and.stars",
                        title: "AI评分",
                        detail: "未配置 API Key 时，本地筛选与导出仍可使用。配置后，AI评分也只在你确认之后才会开始。"
                    )
                    SupportHelpRow(
                        icon: "square.and.arrow.up",
                        title: "复制导出",
                        detail: "只要保留了至少一张照片就可以导出副本，导出多少由你决定；保留目标只用于显示进度。原照片不会被移动、删除或修改。"
                    )
                }

                // 这里只讲"怎么跑、跑多久、花多少钱"。发送什么数据、发给谁属于数据披露，
                // 只在「隐私与数据」写一次——两页各写一份迟早会漂移成互相矛盾的两种说法。
                Section("AI评分规则") {
                    SupportHelpRow(
                        icon: "list.number",
                        title: "评分与排序",
                        detail: "模型按固定绝对标尺对每张照片独立评分，不做组内比较，也不返回名次。全部完成后只在人物或风景内按统一分数排序，取该类型前 N 张作为推荐结果；是否保留由你用底部的“采纳”确认。"
                    )
                    SupportHelpRow(
                        icon: "clock.arrow.circlepath",
                        title: "节奏与重试",
                        detail: "请求之间保持自适应间隔；限流、服务端故障和网络中断会自动退避重试，每张最多 4 次并产生额外请求与费用，仍失败时停在当前照片范围供你重试或放弃。鉴权和模型 ID 错误不会重试。"
                    )
                    SupportHelpRow(
                        icon: "creditcard",
                        title: "费用",
                        detail: "AI评分使用你自己的供应商 API Key，费用以该供应商账单为准。更大的预览尺寸会增加上传量、等待时间和可能的费用。App 不销售或代充 API 额度。"
                    )
                }

                Section("诊断信息") {
                    Text("诊断信息仅包含 App 版本、macOS 版本和运行模式，不包含照片、文件路径或 API Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        copyDiagnostics()
                    } label: {
                        Label("复制诊断信息", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("support.copy-diagnostics")

                    if copiedDiagnostics {
                        Label("已复制不含照片、路径或 API Key 的诊断信息。", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("support.copy-status")
                    }
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
        .frame(width: 560, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("support.information")
    }

    private func copyDiagnostics() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let mode = isDemoModeActive
            ? String(localized: "示例筛选")
            : String(localized: "本地项目")
        let productName = String(localized: "旅行照片筛选器")
        let diagnostics = [
            "\(productName) \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "\(String(localized: "运行模式")): \(mode)",
        ].joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        copiedDiagnostics = true
    }
}

private struct SupportHelpRow: View {
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
