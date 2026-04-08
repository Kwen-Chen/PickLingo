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
        switch self {
        case .english: return String(localized: "English")
        case .chinese: return String(localized: "Chinese")
        case .japanese: return String(localized: "Japanese")
        case .korean: return String(localized: "Korean")
        case .french: return String(localized: "French")
        case .german: return String(localized: "German")
        case .spanish: return String(localized: "Spanish")
        case .russian: return String(localized: "Russian")
        case .portuguese: return String(localized: "Portuguese")
        case .arabic: return String(localized: "Arabic")
        }
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
}

struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguage: Language
    let targetLanguage: Language
}

