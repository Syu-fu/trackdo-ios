import SwiftUI

/// DADS notification banner (components/notification-banner), standard
/// style at mobile size: icon and title, then an optional description. It
/// has no link, so it is not interactive.
struct DadsNotificationBanner: View {
    enum Kind {
        case success
        case error
        case warning
        case info

        var color: Color {
            switch self {
            case .success: DadsColor.success2
            case .error: DadsColor.error1
            case .warning: DadsColor.warningYellow2
            case .info: DadsColor.key900
            }
        }

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "xmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        /// Spoken before the title, since the icon alone tells the kind.
        var name: LocalizedStringResource {
            switch self {
            case .success: "Success"
            case .error: "Error"
            case .warning: "Warning"
            case .info: "Information"
            }
        }
    }

    let kind: Kind
    let title: LocalizedStringResource
    var description: LocalizedStringResource?

    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: kind.symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .padding(.top, 3)
                    .foregroundStyle(kind.color)
                    .accessibilityLabel(Text(kind.name))
                Text(plain: title)
                    .dadsFont(.std17B170)
                    .foregroundStyle(DadsColor.gray900)
                    .padding(.top, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            if let description {
                Text(plain: description)
                    .dadsFont(.std16N170)
                    .foregroundStyle(DadsColor.gray800)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(DadsColor.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(kind.color, lineWidth: 3)
        }
        .accessibilityElement(children: .combine)
    }
}
