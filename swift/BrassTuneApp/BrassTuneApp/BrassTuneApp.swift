import SwiftUI

@main
struct BrassTuneApp: App {
    @StateObject private var appModel = AppModel()

    private var effectiveLanguage: AppLanguage {
        AppLanguage.launchOverride ?? appModel.appLanguage
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appModel)
                // Inject the engine so views that show live pitch (the Tuner)
                // observe it directly and re-render per frame, without churning
                // the whole AppModel at frame rate.
                .environmentObject(appModel.audioEngine)
                .environment(\.locale, effectiveLanguage.locale)
                .environment(\.layoutDirection, effectiveLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }
}
