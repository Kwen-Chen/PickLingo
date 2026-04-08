import SwiftUI

// MARK: - Markdown Block Parser

/// Represents a parsed block-level Markdown element.
enum MarkdownBlock: Identifiable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case blockquote(String)
    case unorderedList(items: [String])
    case orderedList(items: [(index: Int, text: String)])
    case horizontalRule
    case table(headers: [String], rows: [[String]])

    var id: String {
        switch self {
        case .paragraph(let t): return "p-\(t.hashValue)"
        case .heading(let l, let t): return "h\(l)-\(t.hashValue)"
        case .codeBlock(_, let c): return "code-\(c.hashValue)"
        case .blockquote(let t): return "bq-\(t.hashValue)"
        case .unorderedList(let items): return "ul-\(items.hashValue)"
        case .orderedList(let items): return "ol-\(items.map(\.text).hashValue)"
        case .horizontalRule: return "hr-\(UUID().uuidString)"
        case .table(let h, _): return "table-\(h.hashValue)"
        }
    }
}

/// Splits raw Markdown text into block-level elements.
struct MarkdownBlockParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Horizontal rule: --- or *** or ___
            if trimmed.count >= 3 {
                let chars = Set(trimmed)
                if chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_")) {
                    blocks.append(.horizontalRule)
                    i += 1
                    continue
                }
            }

            // Heading: # ... (1-6 levels)
            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            // Fenced code block: ``` or ~~~
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let langPart = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                let language = langPart.isEmpty ? nil : langPart
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Table: starts with | and next line is a separator like |---|---|
            if trimmed.hasPrefix("|") && i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-") {
                    let headers = parseTableRow(trimmed)
                    var rows: [[String]] = []
                    i += 2 // skip header + separator
                    while i < lines.count {
                        let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                        guard rowLine.hasPrefix("|") else { break }
                        rows.append(parseTableRow(rowLine))
                        i += 1
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }

            // Blockquote: > ...
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    let content = String(l.dropFirst(1)).trimmingCharacters(in: .init(charactersIn: " "))
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered list: - item or * item or + item
            if isUnorderedListItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isUnorderedListItem(l) else { break }
                    let content = stripUnorderedListPrefix(l)
                    items.append(content)
                    i += 1
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // Ordered list: 1. item, 2. item, etc.
            if let _ = parseOrderedListItem(trimmed) {
                var items: [(index: Int, text: String)] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let item = parseOrderedListItem(l) else { break }
                    items.append(item)
                    i += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Default: paragraph — gather contiguous non-blank, non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)
                if lt.isEmpty { break }
                if lt.hasPrefix("#") || lt.hasPrefix("```") || lt.hasPrefix("~~~") || lt.hasPrefix(">") || lt.hasPrefix("|") { break }
                if isUnorderedListItem(lt) { break }
                if parseOrderedListItem(lt) != nil { break }
                // Check horizontal rule
                if lt.count >= 3 {
                    let chars = Set(lt)
                    if chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_")) { break }
                }
                paraLines.append(l)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            } else {
                // Fallback: if current line doesn't match any supported block type,
                // advance one line to avoid getting stuck in an infinite loop.
                i += 1
            }
        }

        return blocks
    }

    // MARK: - Heading helper

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        let chars = Array(line)
        while level < chars.count && level < 6 && chars[level] == "#" {
            level += 1
        }
        guard level > 0, level < chars.count, chars[level] == " " else { return nil }
        let text = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level: level, text: text)
    }

    // MARK: - List helpers

    private static func isUnorderedListItem(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        let first = line.first!
        return (first == "-" || first == "*" || first == "+") && line.dropFirst().first == " "
    }

    private static func stripUnorderedListPrefix(_ line: String) -> String {
        guard line.count >= 2 else { return line }
        return String(line.dropFirst(2))
    }

    private static func parseOrderedListItem(_ line: String) -> (index: Int, text: String)? {
        // Match: digits followed by ". " then text
        var digitEnd = line.startIndex
        while digitEnd < line.endIndex && line[digitEnd].isNumber {
            digitEnd = line.index(after: digitEnd)
        }
        guard digitEnd > line.startIndex else { return nil }
        guard digitEnd < line.endIndex && line[digitEnd] == "." else { return nil }
        let afterDot = line.index(after: digitEnd)
        guard afterDot < line.endIndex && line[afterDot] == " " else { return nil }
        let idx = Int(line[line.startIndex..<digitEnd]) ?? 1
        let text = String(line[line.index(after: afterDot)...])
        return (index: idx, text: text)
    }

    // MARK: - Table helper

    private static func parseTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Inline Markdown -> AttributedString

/// Parses inline Markdown (bold, italic, code, links, strikethrough) into an AttributedString.
struct InlineMarkdownParser {
    static func parse(_ text: String, baseSize: CGFloat = 13) -> AttributedString {
        do {
            var attrStr = try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            // Apply base font to the whole string
            attrStr.font = .system(size: baseSize)

            // Style inline code spans: the markdown parser applies .code presentation intent
            for run in attrStr.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    let range = run.range
                    attrStr[range].font = .system(size: baseSize - 1, design: .monospaced)
                    attrStr[range].backgroundColor = Color.primary.opacity(0.06)
                }
            }

            return attrStr
        } catch {
            var plain = AttributedString(text)
            plain.font = .system(size: baseSize)
            return plain
        }
    }
}

// MARK: - Markdown Content View

/// Renders a Markdown string as a series of styled SwiftUI views.
struct MarkdownContentView: View {
    let text: String
    @Environment(\.colorScheme) var colorScheme

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(InlineMarkdownParser.parse(text))
                .foregroundStyle(.primary)

        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)

        case .blockquote(let text):
            blockquoteView(text: text)

        case .unorderedList(let items):
            unorderedListView(items: items)

        case .orderedList(let items):
            orderedListView(items: items)

        case .horizontalRule:
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        }
    }

    // MARK: - Heading

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let fontSize: CGFloat = {
            switch level {
            case 1: return 20
            case 2: return 17
            case 3: return 15
            case 4: return 14
            default: return 13
            }
        }()
        let weight: Font.Weight = level <= 3 ? .bold : .semibold

        Text(InlineMarkdownParser.parse(text, baseSize: fontSize))
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(.primary)
            .padding(.top, level <= 2 ? 4 : 2)
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String) -> some View {
        let hasLang = language != nil && !(language?.isEmpty ?? true)
        return VStack(alignment: .leading, spacing: 0) {
            if let lang = language, !lang.isEmpty {
                Text(lang)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, hasLang ? 6 : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    // MARK: - Blockquote

    private func blockquoteView(text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 3)

            Text(InlineMarkdownParser.parse(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Lists

    private func unorderedListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\u{2022}")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .center)
                    Text(InlineMarkdownParser.parse(item))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private func orderedListView(items: [(index: Int, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(item.index).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, alignment: .trailing)
                    Text(InlineMarkdownParser.parse(item.text))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Table

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columnCount = headers.count

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(0..<columnCount, id: \.self) { col in
                    Text(InlineMarkdownParser.parse(headers[col], baseSize: 12))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                }
            }
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))

            // Separator
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { col in
                        let cellText = col < row.count ? row[col] : ""
                        Text(InlineMarkdownParser.parse(cellText, baseSize: 12))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                if rowIdx < rows.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 1)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
