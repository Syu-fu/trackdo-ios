import SwiftUI

/// DADS text styles (foundations/typography), named like the tokens:
/// `std17B170` is Std-17B-170. Sizes follow Dynamic Type from the DADS size
/// at the default setting. The system font stands in for Noto Sans JP.
enum DadsTextStyle {
    case std24B150
    case std20B150
    case std17B170
    case std16B170
    case std16N170
    case dns16B130
    case dns16N130
    case dns14N130
    case oln16B100

    fileprivate var size: CGFloat {
        switch self {
        case .std24B150: 24
        case .std20B150: 20
        case .std17B170: 17
        case .std16B170, .std16N170, .dns16B130, .dns16N130, .oln16B100: 16
        case .dns14N130: 14
        }
    }

    fileprivate var isBold: Bool {
        switch self {
        case .std16N170, .dns16N130, .dns14N130: false
        default: true
        }
    }

    fileprivate var lineHeight: CGFloat {
        switch self {
        case .std24B150, .std20B150: 1.5
        case .std17B170, .std16B170, .std16N170: 1.7
        case .dns16B130, .dns16N130, .dns14N130: 1.3
        case .oln16B100: 1.0
        }
    }

    fileprivate var letterSpacing: CGFloat {
        switch self {
        case .dns16B130, .dns16N130, .dns14N130: 0
        default: 0.02
        }
    }

    fileprivate var dynamicTypeStyle: Font.TextStyle {
        switch self {
        case .std24B150: .title2
        case .std20B150: .title3
        case .std17B170: .headline
        case .std16B170, .std16N170, .dns16B130, .dns16N130, .oln16B100: .body
        case .dns14N130: .subheadline
        }
    }
}

private struct DadsFont: ViewModifier {
    let style: DadsTextStyle
    @ScaledMetric private var size: CGFloat

    init(style: DadsTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.dynamicTypeStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.isBold ? .bold : .regular))
            .tracking(size * style.letterSpacing)
            .lineSpacing(size * (style.lineHeight - 1))
    }
}

extension View {
    func dadsFont(_ style: DadsTextStyle) -> some View {
        modifier(DadsFont(style: style))
    }
}
