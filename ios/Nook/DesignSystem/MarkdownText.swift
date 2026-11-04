import SwiftUI

/// Renders the Markdown that chat models usually reply with: headings, bullet and numbered
/// lists, quotes, code blocks, rules, and inline bold, italics, code and links.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownBlock.inline(text))
                .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 2)
        case .paragraph(let text):
            Text(MarkdownBlock.inline(text))
        case .bullet(let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: depth == 0 ? "•" : "◦")
                    .foregroundStyle(Theme.accent)
                Text(MarkdownBlock.inline(text))
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .numbered(let depth, let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(number).")
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                Text(MarkdownBlock.inline(text))
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: 3)
                Text(MarkdownBlock.inline(text))
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            Text(verbatim: text)
                .font(.callout.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .rule:
            Hairline()
        }
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(depth: Int, text: String)
    case numbered(depth: Int, number: Int, text: String)
    case quote(String)
    case code(String)
    case rule

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }
            if line.isEmpty {
                flush()
                continue
            }
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let depth = min(indent / 2, 3)
            if let heading = headingParts(line) {
                flush()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if line == "---" || line == "***" || line == "___" {
                flush()
                blocks.append(.rule)
            } else if let text = bulletText(line) {
                flush()
                blocks.append(.bullet(depth: depth, text: text))
            } else if let item = numberedParts(line) {
                flush()
                blocks.append(.numbered(depth: depth, number: item.number, text: item.text))
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code {
            blocks.append(.code(lines.joined(separator: "\n")))
        }
        flush()
        return blocks
    }

    /// Inline formatting. Bold is matched by hand because CommonMark's rules miss `**…**`
    /// next to Chinese punctuation; the rest goes through Foundation's Markdown parser.
    static func inline(_ text: String) -> AttributedString {
        let parts = text.components(separatedBy: "**")
        let balanced = parts.count >= 3 && parts.count % 2 == 1
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            var piece = (try? AttributedString(
                markdown: part,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(part)
            if balanced && index % 2 == 1 {
                piece.inlinePresentationIntent = .stronglyEmphasized
            } else if !balanced && index > 0 {
                result += AttributedString("**")
            }
            result += piece
        }
        return result
    }

    private static func headingParts(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• ", "· "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedParts(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")" || marker == "、" else { return nil }
        let text = rest.dropFirst()
        guard marker == "、" || text.first == " " else { return nil }
        return (number, text.trimmingCharacters(in: .whitespaces))
    }
}
