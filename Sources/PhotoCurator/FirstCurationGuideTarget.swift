import SwiftUI

enum FirstCurationGuidePointerSide {
    case leading
    case trailing
    case top

    var alignment: Alignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        }
    }

    var symbolName: String {
        switch self {
        case .leading: "hand.point.right.fill"
        case .trailing: "hand.point.left.fill"
        case .top: "hand.point.down.fill"
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
                if isActive {
                    Image(systemName: pointerSide.symbolName)
                        .font(.system(size: 20, weight: .bold))
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
