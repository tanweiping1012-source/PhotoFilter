import SwiftUI

enum FirstCurationGuidePointerSide {
    case leading
    case trailing
    case top
    /// 只画红框，不画手形指针。
    ///
    /// 手形指针的偏移是固定的 24pt，前提是目标周围留得出这段空间。侧栏里满宽的
    /// 一行两边都没有——右边紧贴面板边缘，左边只有 16pt padding，指针会压在
    /// 边界上甚至被裁掉。而且"手"表达的是"点这里"；自动执行的步骤要说的是
    /// "看这里等"，本来就不该出现手。
    case noPointer

    var alignment: Alignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        case .noPointer: .center
        }
    }

    var symbolName: String? {
        switch self {
        case .leading: "hand.point.right.fill"
        case .trailing: "hand.point.left.fill"
        case .top: "hand.point.down.fill"
        case .noPointer: nil
        }
    }

    var offset: CGSize {
        switch self {
        case .leading:
            CGSize(width: -24, height: 0)
        case .trailing:
            CGSize(width: 24, height: 0)
        case .top:
            CGSize(width: 0, height: -24)
        case .noPointer:
            .zero
        }
    }
}

private struct FirstCurationGuideTargetModifier: ViewModifier {
    let isActive: Bool
    let pointerSide: FirstCurationGuidePointerSide
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color.red,
                        lineWidth: 3
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: pointerSide.alignment) {
                if isActive, let symbolName = pointerSide.symbolName {
                    Image(systemName: symbolName)
                        .font(Typography.guidePointer)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.red, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.85), lineWidth: 1)
                        }
                        .shadow(
                            color: .black.opacity(0.22),
                            radius: 4,
                            y: 2
                        )
                        .offset(pointerSide.offset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .zIndex(isActive ? 20 : 0)
    }
}

extension View {
    func firstCurationGuideTarget(
        _ isActive: Bool,
        pointerSide: FirstCurationGuidePointerSide = .trailing,
        cornerRadius: CGFloat = 8
    ) -> some View {
        modifier(
            FirstCurationGuideTargetModifier(
                isActive: isActive,
                pointerSide: pointerSide,
                cornerRadius: cornerRadius
            )
        )
    }
}
