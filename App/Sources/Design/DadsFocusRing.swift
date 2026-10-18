import SwiftUI

/// The DADS focus indicator (foundations/color): a 4 pt black outline 2 pt
/// outside the control, with a 2 pt Yellow-300 ring between them. It must
/// not be changed.
private struct DadsFocusRing: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius + 2)
                        .strokeBorder(DadsColor.yellow300, lineWidth: 2)
                        .padding(-2)
                    RoundedRectangle(cornerRadius: cornerRadius + 6)
                        .strokeBorder(DadsColor.black, lineWidth: 4)
                        .padding(-6)
                }
            }
    }
}

extension View {
    func dadsFocusRing(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        modifier(DadsFocusRing(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
