import Foundation

enum Language: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"
    case portuguese = "pt"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        UIString(localizationKey)
    }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .portuguese: return "Português"
        case .arabic: return "العربية"
        }
    }

    var uiName: String {
        UIString(localizationKey)
    }

    private var localizationKey: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .russian: return "Russian"
        case .portuguese: return "Portuguese"
        case .arabic: return "Arabic"
        }
    }
}

struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguage: Language
    let targetLanguage: Language
}
