import SwiftUI

/// DADS buttons (components/button): solid fill for the screen's primary
/// action, outline for secondary ones and text for tertiary ones. Sizes keep
/// at least the 44 pt target.
struct DadsButtonStyle: ButtonStyle {
    enum Kind {
        case solidFill
        case outline
        case text
    }

    enum Size {
        /// At least 136 × 56.
        case large
        /// At least 96 × 48.
        case medium
        /// 44 × 44, just the target size, for a button labeled by an icon
        /// alone. Give it an accessibility label.
        case icon

        var minWidth: CGFloat {
            switch self {
            case .large: 136
            case .medium: 96
            case .icon: 44
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .large: 56
            case .medium: 48
            case .icon: 44
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .large: 12
            case .medium: 8
            case .icon: 0
            }
        }

        var horizontalPadding: CGFloat { self == .icon ? 0 : 16 }
    }

    let kind: Kind
    var size: Size = .large

    func makeBody(configuration: Configuration) -> some View {
        DadsButton(configuration: configuration, kind: kind, size: size)
    }
}

private struct DadsButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: DadsButtonStyle.Kind
    let size: DadsButtonStyle.Size
    @Environment(\.isFocused) private var isFocused

    private static let radius: CGFloat = 8

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .dadsFont(.oln16B100)
            .multilineTextAlignment(.center)
            .underline(kind == .text || pressed)
            .foregroundStyle(foreground(pressed: pressed))
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minWidth: size.minWidth, minHeight: size.minHeight)
            .background(background(pressed: pressed), in: .rect(cornerRadius: Self.radius))
            .overlay {
                if kind == .outline {
                    RoundedRectangle(cornerRadius: Self.radius)
                        .strokeBorder(foreground(pressed: pressed), lineWidth: 1)
                }
            }
            .contentShape(.rect(cornerRadius: Self.radius))
            .dadsFocusRing(isFocused, cornerRadius: Self.radius)
    }

    private func foreground(pressed: Bool) -> Color {
        switch kind {
        case .solidFill: DadsColor.white
        case .outline, .text: pressed ? DadsColor.key1200 : DadsColor.key900
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .solidFill: pressed ? DadsColor.key1200 : DadsColor.key900
        case .outline: pressed ? DadsColor.key300 : DadsColor.white
        case .text: pressed ? DadsColor.key100 : .clear
        }
    }
}

extension ButtonStyle where Self == DadsButtonStyle {
    static func dads(_ kind: DadsButtonStyle.Kind, size: DadsButtonStyle.Size = .large) -> DadsButtonStyle {
        DadsButtonStyle(kind: kind, size: size)
    }
}
