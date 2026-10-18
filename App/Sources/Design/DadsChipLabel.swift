import SwiftUI

/// DADS chip label (components/chip-label), filled-1 style: a status keyword
/// with a lead icon. The text, not the color, carries the meaning.
struct DadsChipLabel: View {
    enum Tone {
        case gray
        case blue
        case red

        /// Border and icon.
        var nonText: Color {
            switch self {
            case .gray: DadsColor.gray700
            case .blue: DadsColor.blue700
            case .red: DadsColor.red900
            }
        }

        var background: Color {
            switch self {
            case .gray: DadsColor.gray50
            case .blue: DadsColor.key50
            case .red: DadsColor.red50
            }
        }

        var text: Color {
            switch self {
            case .gray: DadsColor.gray800
            case .blue: DadsColor.blue800
            case .red: DadsColor.red1000
            }
        }
    }

    let title: LocalizedStringResource
    let symbol: String
    let tone: Tone

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 32

    var body: some View {
        Label {
            Text(plain: title)
                .dadsFont(.dns16N130)
                .foregroundStyle(tone.text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tone.nonText)
                .accessibilityHidden(true)
        }
        .labelStyle(DadsChipLabelStyle())
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .frame(minHeight: minHeight)
        .background(tone.background, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(tone.nonText, lineWidth: 1)
        }
    }
}

private struct DadsChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
