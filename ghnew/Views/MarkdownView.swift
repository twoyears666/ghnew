import SwiftUI

/// A Markdown-rendering view used for release changelogs. Supports headings,
/// bold/italic, inline & fenced code, links, lists, blockquotes, and paragraphs.
struct MarkdownView: View {
    let markdown: String
    var fontSize: CGFloat = 13

    var body: some View {
        Text(MarkdownRenderer.render(markdown, fontSize: fontSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum MarkdownRenderer {

    struct InlineToken {
        enum Style { case plain, bold, italic, boldItalic, code, link(String) }
        let text: String
        let style: Style
    }

    // MARK: - Public

    static func render(_ md: String, fontSize: CGFloat) -> AttributedString {
        var out = AttributedString()
        let lines = md.components(separatedBy: "\n")
        var inFence = false
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                i += 1
                continue
            }

            if inFence {
                var attrs = AttributeContainer()
                attrs.font = .system(size: fontSize, design: .monospaced)
                attrs.backgroundColor = Theme.codeBackground
                attrs.foregroundColor = Theme.codeText
                out += style(AttributedString(raw + "\n"), attrs)
                i += 1
                continue
            }

            guard !trimmed.isEmpty else {
                out += AttributedString("\n")
                i += 1
                continue
            }

            // Heading
            let hashes = trimmed.prefix(while: { $0 == "#" })
            if !hashes.isEmpty && hashes.count <= 6 {
                let level = hashes.count
                let core = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                let size = fontSize + 5 - CGFloat(max(0, level - 1) * 2)
                var attrs = AttributeContainer()
                attrs.font = .system(size: max(12, size), weight: .bold)
                attrs.foregroundColor = Theme.textPrimary
                out += style(inline(core), attrs) + AttributedString("\n\n")
                i += 1
                continue
            }

            // Thematic break
            if Set(trimmed).isSubset(of: ["-", "*", "_"]), trimmed.count >= 3 {
                var attrs = AttributeContainer()
                attrs.foregroundColor = Theme.textMuted
                out += style(AttributedString("———\n\n"), attrs)
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix(" ") { rest.removeFirst() }
                var attrs = AttributeContainer()
                attrs.font = .system(size: fontSize).italic()
                attrs.foregroundColor = Theme.textSecondary
                out += style(inline(rest), attrs) + AttributedString("\n")
                i += 1
                continue
            }

            // List items
            if let listText = stripListMarker(trimmed) {
                var attrs = AttributeContainer()
                attrs.font = .system(size: fontSize)
                attrs.foregroundColor = Theme.textPrimary
                let indent = AttributedString("     ")
                out += indent + style(AttributedString("•  "), attrs) + style(inline(listText), attrs) + AttributedString("\n")
                i += 1
                continue
            }

            // Plain paragraph
            var attrs = AttributeContainer()
            attrs.font = .system(size: fontSize)
            attrs.foregroundColor = Theme.textPrimary
            out += style(inline(trimmed), attrs) + AttributedString("\n")
            i += 1
        }
        return out
    }

    // MARK: - Inline parsing

    private static func inline(_ text: String) -> AttributedString {
        var result = AttributedString()
        for token in inlineTokens(text) {
            var attr: AttributedString
            var attrs = AttributeContainer()
            attrs.font = .system(size: 13)
            switch token.style {
            case .plain:
                attrs.foregroundColor = Theme.textPrimary
            case .bold:
                attrs.font = .system(size: 13, weight: .bold)
                attrs.foregroundColor = Theme.textPrimary
            case .italic:
                attrs.font = .system(size: 13).italic()
                attrs.foregroundColor = Theme.textPrimary
            case .boldItalic:
                attrs.font = .system(size: 13, weight: .bold).italic()
                attrs.foregroundColor = Theme.textPrimary
            case .code:
                attrs.font = .system(size: 12, design: .monospaced)
                attrs.foregroundColor = Theme.codeText
                attrs.backgroundColor = Theme.codeBackground
                attr = AttributedString(token.text)
                attr.mergeAttributes(attrs)
                result += attr
                continue
            case .link(let urlText):
                attrs.foregroundColor = Theme.branchBlueText
                attrs.underlineStyle = .single
                attr = AttributedString(token.text)
                attr.link = URL(string: urlText)
                attr.mergeAttributes(attrs)
                result += attr
                continue
            }
            attr = AttributedString(token.text)
            attr.mergeAttributes(attrs)
            result += attr
        }
        return result
    }

    private static func inlineTokens(_ text: String) -> [InlineToken] {
        var tokens: [InlineToken] = []
        var buffer = ""
        var s = text.startIndex
        let e = text.endIndex

        func flush() {
            if !buffer.isEmpty {
                tokens.append(InlineToken(text: buffer, style: .plain))
                buffer = ""
            }
        }

        func advance(_ idx: String.Index) -> String.Index {
            idx == e ? e : text.index(after: idx)
        }

        while s < e {
            let ch = text[s]

            if ch == "[" {
                let afterBracket = advance(s)
                let src = text[afterBracket..<e]
                if let open = src.firstIndex(of: "("), let close = src.firstIndex(of: ")") {
                    let label = String(src[..<open])
                    let url = String(src[src.index(after: open) ..< close])
                    if !label.isEmpty {
                        flush()
                        tokens.append(InlineToken(text: label, style: .link(url)))
                        s = advance(close)
                        continue
                    }
                }
            }

            if ch == "`" {
                let after = advance(s)
                let rest = text[after..<e]
                if let ci = rest.firstIndex(of: "`") {
                    flush()
                    tokens.append(InlineToken(text: String(rest[..<ci]), style: .code))
                    s = advance(ci)
                    continue
                }
            }

            if ch == "*" || ch == "_" {
                let nb = advance(s)
                let double = nb < e && (text[nb] == "*" || text[nb] == "_")
                let afterDelim = advance(nb)
                if double {
                    if afterDelim < e, let close = text.range(of: "**", options: .literal, range: afterDelim..<e) {
                        flush()
                        tokens.append(InlineToken(text: String(text[afterDelim..<close.lowerBound]), style: .bold))
                        s = advance(close.upperBound)
                        continue
                    }
                } else {
                    if afterDelim < e, let close = text.range(of: "*", options: .literal, range: afterDelim..<e) {
                        flush()
                        tokens.append(InlineToken(text: String(text[afterDelim..<close.lowerBound]), style: .italic))
                        s = advance(close.upperBound)
                        continue
                    }
                }
                // unclosed → literal
                buffer.append(ch)
                s = nb
                continue
            }

            buffer.append(ch)
            s = advance(s)
        }
        flush()
        return tokens
    }

    // MARK: - Helpers

    private static func stripListMarker(_ line: String) -> String? {
        let markers = ["- ", "* ", "+ ", "• "]
        for m in markers where line.hasPrefix(m) {
            return String(line.dropFirst(m.count)).trimmingCharacters(in: .whitespaces)
        }
        // numbered "1. "
        if line.first?.isNumber == true {
            let parts = line.split(separator: ".", maxSplits: 1)
            if parts.count == 2, let restHead = parts[1].first, restHead == " " {
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func style(_ str: AttributedString, _ attrs: AttributeContainer) -> AttributedString {
        var s = str
        s.mergeAttributes(attrs, mergePolicy: .keepNew)
        return s
    }
}