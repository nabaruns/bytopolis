import SwiftUI

/// A lightweight Markdown block renderer — enough for chat replies without pulling in a
/// Markdown package. Handles headings, ordered/unordered lists, fenced code blocks,
/// blockquotes, and paragraphs; inline **bold**, *italic*, `code`, and links are rendered
/// with `AttributedString`'s inline Markdown parser.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownParser.blocks(from: text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownParser.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level <= 1 ? .title3.bold() : (level == 2 ? .headline : .subheadline.bold()))
        case .paragraph(let text):
            inline(text)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        inline(item)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        inline(item)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(.secondary).frame(width: 3)
                inline(text).foregroundStyle(.secondary)
            }
        }
    }

    /// Render inline Markdown (bold/italic/code/links) with graceful fallback.
    private func inline(_ s: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(s)
    }
}

/// Pure Markdown-to-blocks parser (no SwiftUI) so it can be unit-tested.
enum MarkdownParser {
    enum Block: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case bullet([String])
        case ordered([String])
        case code(String)
        case quote(String)
    }

    static func blocks(from text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var i = 0
        var paragraph: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty { flushParagraph(); i += 1; continue }

            // Heading.
            if let hashes = headingLevel(trimmed) {
                flushParagraph()
                let content = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(hashes, content))
                i += 1; continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            }

            // Unordered list — consume items, hopping over blank-line gaps between them.
            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBullet(t) { items.append(bulletContent(t)); i += 1; continue }
                    if t.isEmpty, let j = nextItemIndex(lines, after: i, isBullet: true) { i = j; continue }
                    break
                }
                blocks.append(.bullet(items))
                continue
            }

            // Ordered list — same, so "1.\n\n1.\n\n1." renders as 1, 2, 3.
            if orderedContent(trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let c = orderedContent(t) { items.append(c); i += 1; continue }
                    if t.isEmpty, let j = nextItemIndex(lines, after: i, isBullet: false) { i = j; continue }
                    break
                }
                blocks.append(.ordered(items))
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Line classifiers

    private static func headingLevel(_ s: String) -> Int? {
        guard s.hasPrefix("#") else { return nil }
        let count = s.prefix(while: { $0 == "#" }).count
        guard count <= 6, s.dropFirst(count).first == " " else { return nil }
        return count
    }

    /// Index of the next list item of the given kind after `i`, if only blank lines
    /// intervene (used to keep a list going across blank-line gaps).
    private static func nextItemIndex(_ lines: [String], after i: Int, isBullet wantBullet: Bool) -> Int? {
        var j = i
        while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
        guard j < lines.count else { return nil }
        let t = lines[j].trimmingCharacters(in: .whitespaces)
        let matches = wantBullet ? isBullet(t) : (orderedContent(t) != nil)
        return matches ? j : nil
    }

    private static func isBullet(_ s: String) -> Bool {
        s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ")
    }
    private static func bulletContent(_ s: String) -> String {
        String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    /// Returns the content of an ordered-list line like "1. foo", else nil.
    private static func orderedContent(_ s: String) -> String? {
        let digits = s.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = s.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
}
