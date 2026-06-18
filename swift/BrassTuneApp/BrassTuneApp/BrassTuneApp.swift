import SwiftUI

@main
struct BrassTuneApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appModel)
        }
    }
}
