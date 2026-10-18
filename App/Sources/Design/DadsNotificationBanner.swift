import SwiftUI

/// DADS notification banner (components/notification-banner), standard
/// style at mobile size: icon and title, then optional details such as the
/// description and action buttons, which align to the trailing edge. It is
/// placed in the flow of the screen, so it has no close button.
struct DadsNotificationBanner<Details: View>: View {
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
    @ViewBuilder let details: () -> Details

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
            .accessibilityElement(children: .combine)
            details()
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(DadsColor.white, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(kind.color, lineWidth: 3)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The banner description's text style.
struct DadsBannerDescription: View {
    let text: Text

    init(_ resource: LocalizedStringResource) {
        text = Text(plain: resource)
    }

    init(verbatim: String) {
        text = Text(verbatim: verbatim)
    }

    var body: some View {
        text
            .dadsFont(.std16N170)
            .foregroundStyle(DadsColor.gray800)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DadsNotificationBanner where Details == DadsBannerDescription? {
    init(kind: Kind, title: LocalizedStringResource, description: LocalizedStringResource? = nil) {
        self.init(kind: kind, title: title) {
            description.map { DadsBannerDescription($0) }
        }
    }
}
