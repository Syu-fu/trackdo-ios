import SwiftUI

@main
struct TrackdoApp: App {
    /// Opening fails only when the saved state cannot be read; it is kept,
    /// since it may hold unsent edits.
    @State private var model = Result { try AppModel() }

    var body: some Scene {
        WindowGroup {
            switch model {
            case let .success(model):
                NavigationStack {
                    SettingsView(editor: model.settings)
                }
                .task { await model.start() }
            case let .failure(error):
                StartupFailureView(error: error)
            }
        }
    }
}
