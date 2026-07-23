import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case arabic = "ar"
    case french = "fr"
    case german = "de"
    case russian = "ru"
    case brazilianPortuguese = "pt-BR"
    case japanese = "ja"
    case korean = "ko"
    case vietnamese = "vi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return NativeLocalization.string("System Default")
        case .english: return "English"
        case .spanish: return "Español"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .arabic: return "العربية"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .russian: return "Русский"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    var isRightToLeft: Bool {
        if self == .arabic { return true }
        guard self == .system else { return false }
        return Locale.Language(identifier: locale.identifier).characterDirection == .rightToLeft
    }

    func localized(_ key: String) -> String {
        guard self != .system,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func practiceSessionCountLabel(_ count: Int) -> String {
        String(localized: "\(count) practice sessions", locale: locale)
    }

    static var launchOverride: AppLanguage? {
        ProcessInfo.processInfo.arguments.contains("UITEST_RTL") ? .arabic : nil
    }
}

/// Resolves non-SwiftUI copy through the same language the user selected in-app.
/// SwiftUI's locale environment localizes `Text` and `Label`, but it does not
/// change the default locale used by `String(localized:)` in models/services.
enum NativeLocalization {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var selectedLanguage = AppLanguage.launchOverride ?? .system

    static var language: AppLanguage {
        get { lock.withLock { selectedLanguage } }
        set { lock.withLock { selectedLanguage = newValue } }
    }

    static func string(_ key: String) -> String {
        language.localized(key)
    }

    static func format(_ key: String, _ arguments: String...) -> String {
        String(
            format: language.localized(key),
            locale: language.locale,
            arguments: language.isRightToLeft ? arguments.map(isolate) : arguments
        )
    }

    static func pageCountLabel(_ count: Int) -> String {
        String(localized: "\(count) pages", locale: language.locale)
    }

    /// Unicode FSI/PDI keeps notes, numbers, emails, file types, and user text
    /// readable when embedded in Arabic or another right-to-left sentence.
    static func isolate(_ value: String) -> String {
        "\u{2068}\(value)\u{2069}"
    }

    static func preserve(_ value: String) -> String {
        language.isRightToLeft ? isolate(value) : value
    }
}
