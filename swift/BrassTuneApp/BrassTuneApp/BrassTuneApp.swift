import SwiftUI

@main
struct BrassTuneApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            BTThemeHost(manager: themeManager) {
                AppRootView()
                    .environmentObject(appModel)
            }
        }
    }
}
