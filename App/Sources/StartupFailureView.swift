import SwiftUI

/// Shown instead of the app when the saved state cannot be opened.
struct StartupFailureView: View {
    let error: any Error

    var body: some View {
        ScrollView {
            DadsNotificationBanner(
                kind: .error,
                title: "trackdo could not open your data",
                description: "Your data was left as it is. Restart the app; if this keeps happening, report it with this detail: \(String(describing: error))"
            )
            .padding(16)
        }
        .background(DadsColor.white)
    }
}
