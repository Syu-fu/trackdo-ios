import SwiftUI
import TrackdoKit

/// What syncing is doing. Normal states are shown passively as text;
/// failures get a banner that says what is kept and what to do.
struct SyncStatusSection: View {
    let model: SyncStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .dadsFont(.std20B150)
                .foregroundStyle(DadsColor.gray900)
                .accessibilityAddTraits(.isHeader)
            if case let .failing(problem) = model.status {
                DadsNotificationBanner(kind: problem.bannerKind, title: problem.title) {
                    DadsBannerDescription(problem.description)
                    if model.status.canRetryNow {
                        HStack {
                            Spacer(minLength: 0)
                            Button("Retry Now") {
                                Task { await model.retryNow() }
                            }
                            .buttonStyle(.dads(.solidFill, size: .medium))
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.status.title)
                        .dadsFont(.std16B170)
                        .foregroundStyle(DadsColor.gray900)
                    Text(model.status.description)
                        .dadsFont(.std16N170)
                        .foregroundStyle(DadsColor.gray800)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: model.status) { _, status in
            if case let .failing(problem) = status {
                AccessibilityNotification.Announcement(String(localized: problem.title)).post()
            }
        }
    }
}

private extension SyncStatus {
    var title: LocalizedStringResource {
        switch self {
        case .off: "Not syncing"
        case .connecting: "Connecting…"
        case .live: "Up to date"
        case .paused: "Paused"
        case .failing: "Not syncing"
        }
    }

    var description: LocalizedStringResource {
        switch self {
        case .off: "Your tasks are kept on this device only."
        case .connecting: "Reaching the server and catching up with your other devices."
        case .live: "Changes sync with your other devices as you make them."
        case .paused: "Syncing resumes when you return to trackdo."
        case .failing: ""
        }
    }
}

private extension SyncProblem {
    var bannerKind: DadsBannerKind {
        switch self {
        case .unreachable, .unexpected, .serverInconsistent: .warning
        case .unauthorized, .unsupportedProtocol, .saveFailed: .error
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .unreachable: "The server can’t be reached"
        case .unauthorized: "The server refused the token"
        case .unsupportedProtocol: "The app and the server are not compatible"
        case .unexpected: "The server answered unexpectedly"
        case .serverInconsistent: "The server sent conflicting data"
        case .saveFailed: "Changes could not be saved on this device"
        }
    }

    var description: LocalizedStringResource {
        switch self {
        case .unreachable:
            "Your changes are kept on this device and sent when the connection is back."
        case .unauthorized:
            "Enter a token the server accepts below. Your changes are kept until then."
        case .unsupportedProtocol:
            "Update the app or the server so that both use the same sync protocol. Your changes are kept until then."
        case let .unexpected(detail):
            "trackdo keeps trying, and your changes are kept. (\(detail))"
        case let .serverInconsistent(detail):
            "trackdo keeps trying. If this keeps happening, report it to whoever runs the server. (\(detail))"
        case let .saveFailed(detail):
            "Free up storage on this device. trackdo saves again with your next change. (\(detail))"
        }
    }
}
