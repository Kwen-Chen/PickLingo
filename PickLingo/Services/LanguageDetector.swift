import Foundation
import NaturalLanguage

enum LanguageDetector {
    static func detect(_ text: String) -> Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominant = recognizer.dominantLanguage else { return nil }

        switch dominant {
        case .english: return .english
        case .simplifiedChinese, .traditionalChinese: return .chinese
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        case .russian: return .russian
        case .portuguese: return .portuguese
        case .arabic: return .arabic
        default: return nil
        }
    }

    static func targetLanguage(for source: Language) -> Language {
        let settings = AppSettings.shared
        if source == settings.defaultTargetLanguage {
            return source == .english ? .chinese : .english
        }
        return settings.defaultTargetLanguage
    }
}
