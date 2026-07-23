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
        case .system: return String(localized: "System Default")
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
