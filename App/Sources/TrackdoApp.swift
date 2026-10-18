import SwiftUI

@main
struct TrackdoApp: App {
    /// Opening fails only when the saved state cannot be read; it is kept,
    /// since it may hold unsent edits.
    @State private var model = Result { try AppModel() }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch model {
            case let .success(model):
                TaskListView(
                    model: model.tasks,
                    store: model.store,
                    settings: model.settings,
                    syncStatus: model.syncStatus
                )
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: Task { await model.enterForeground() }
                    case .background: Task { await model.enterBackground() }
                    default: break
                    }
                }
            case let .failure(error):
                StartupFailureView(error: error)
            }
        }
    }
}
