import SwiftUI

@main
struct BrassTuneApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appModel)
                // Inject the engine so views that show live pitch (the Tuner)
                // observe it directly and re-render per frame, without churning
                // the whole AppModel at frame rate.
                .environmentObject(appModel.audioEngine)
        }
    }
}
