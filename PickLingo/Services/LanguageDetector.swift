import Foundation
import NaturalLanguage

enum LanguageDetector {
    static func detect(_ text: String) -> Language? {
        // NLLanguageRecognizer is unreliable for very short text (single words,
        // a few characters) — it frequently returns nil or the wrong language.
        // For selection-translation the input is often a single word, so we
        // first do a fast, deterministic script-based check that reliably
        // separates the major writing systems. Getting the SOURCE wrong is the
        // most damaging failure: e.g. a short Chinese word misdetected as
        // English makes the model "translate" Chinese→Chinese and just echo it.
        if let scriptLanguage = detectByScript(text) {
            return scriptLanguage
        }

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

    /// Deterministic detection based on Unicode script of the text's characters.
    /// Returns a language only when a script is unambiguous enough to decide
    /// (CJK/Kana/Hangul/Cyrillic/Arabic). Returns nil for Latin-script text so
    /// the statistical recognizer can distinguish English/French/German/etc.
    private static func detectByScript(_ text: String) -> Language? {
        var hasHan = false
        var hasHiraganaOrKatakana = false
        var hasHangul = false
        var hasCyrillic = false
        var hasArabic = false

        for scalar in text.unicodeScalars {
            let value = scalar.value
            switch value {
            // CJK Unified Ideographs (+ Extension A) and compatibility.
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
                hasHan = true
            // Hiragana + Katakana (incl. phonetic extensions & half-width kana).
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
                hasHiraganaOrKatakana = true
            // Hangul syllables and Jamo.
            case 0x1100...0x11FF, 0xAC00...0xD7AF, 0x3130...0x318F:
                hasHangul = true
            // Cyrillic.
            case 0x0400...0x04FF, 0x0500...0x052F:
                hasCyrillic = true
            // Arabic.
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
                hasArabic = true
            default:
                break
            }
        }

        // Japanese kana is a strong, unambiguous signal (kanji alone is not,
        // since Chinese and Japanese share Han characters).
        if hasHiraganaOrKatakana { return .japanese }
        if hasHangul { return .korean }
        if hasHan { return .chinese }
        if hasArabic { return .arabic }
        if hasCyrillic { return .russian }
        return nil
    }

    static func targetLanguage(for source: Language) -> Language {
        let settings = AppSettings.shared
        if source == settings.defaultTargetLanguage {
            return source == .english ? .chinese : .english
        }
        return settings.defaultTargetLanguage
    }
}
