import SwiftUI
import AppKit

// MARK: - Block model

private enum MBlock: Identifiable {
    case heading(Int, String)
    case codeBlock(String, String)          // language, code
    case unorderedList([String])
    case orderedList([String])
    case paragraph(String)
    case rule

    var id: String {
        switch self {
        case .heading(let l, let t):      return "h\(l)\(t.prefix(30))"
        case .codeBlock(let lang, let c): return "cb\(lang)\(c.prefix(20))"
        case .unorderedList(let i):       return "ul\(i.first?.prefix(20) ?? "")"
        case .orderedList(let i):         return "ol\(i.first?.prefix(20) ?? "")"
        case .paragraph(let t):           return "p\(t.prefix(30))"
        case .rule:                       return "hr\(Int.random(in: 0...99999))"
        }
    }
}

// MARK: - Main view

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parse(text)) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MBlock) -> some View {
        switch block {
        case .heading(let level, let raw):
            Text(inline(raw))
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 4 : 2)

        case .codeBlock(let lang, let code):
            CodeBlockView(language: lang, code: code)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundColor(.secondary)
                        Text(inline(item))
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Text(inline(item))
                    }
                }
            }

        case .paragraph(let raw):
            Text(inline(raw))
                .fixedSize(horizontal: false, vertical: true)

        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    private func inline(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: raw, options: opts)) ?? AttributedString(raw)
    }
}

// MARK: - Code block

private struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption)
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
                Button(action: copyCode) {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.15, green: 0.15, blue: 0.18))

            Divider().background(Color.white.opacity(0.08))

            // Code body
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.11, green: 0.11, blue: 0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private var highlighted: AttributedString {
        SyntaxHighlighter.highlight(code: code, language: language)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Markdown parser

private func parse(_ text: String) -> [MBlock] {
    var blocks: [MBlock] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // Fenced code block
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            let fence = line.hasPrefix("```") ? "```" : "~~~"
            let lang  = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            i += 1
            var codeLines: [String] = []
            while i < lines.count && !lines[i].hasPrefix(fence) {
                codeLines.append(lines[i])
                i += 1
            }
            if i < lines.count { i += 1 }
            blocks.append(.codeBlock(lang, codeLines.joined(separator: "\n")))
            continue
        }

        // Headings
        if let (level, text) = parseHeading(line) {
            blocks.append(.heading(level, text))
            i += 1; continue
        }

        // Horizontal rule
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "***" || trimmed == "___"
            || trimmed == "- - -" || trimmed == "* * *" {
            blocks.append(.rule)
            i += 1; continue
        }

        // Unordered list
        if isListItem(line) {
            var items: [String] = []
            while i < lines.count && isListItem(lines[i]) {
                items.append(String(lines[i].dropFirst(2)).trimmingCharacters(in: .whitespaces))
                i += 1
            }
            blocks.append(.unorderedList(items))
            continue
        }

        // Ordered list
        if let rest = parseOrderedItem(line) {
            var items: [String] = [rest]
            i += 1
            while i < lines.count, let r = parseOrderedItem(lines[i]) {
                items.append(r); i += 1
            }
            blocks.append(.orderedList(items))
            continue
        }

        // Empty line
        if trimmed.isEmpty { i += 1; continue }

        // Paragraph — collect consecutive non-special lines
        var paraLines: [String] = []
        while i < lines.count {
            let l  = lines[i]
            let t  = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { break }
            if l.hasPrefix("```") || l.hasPrefix("~~~") { break }
            if parseHeading(l) != nil { break }
            if isListItem(l) || parseOrderedItem(l) != nil { break }
            if t == "---" || t == "***" || t == "___" { break }
            paraLines.append(l)
            i += 1
        }
        if !paraLines.isEmpty {
            blocks.append(.paragraph(paraLines.joined(separator: "\n")))
        }
    }
    return blocks
}

private func parseHeading(_ line: String) -> (Int, String)? {
    for level in stride(from: 6, through: 1, by: -1) {
        let prefix = String(repeating: "#", count: level) + " "
        if line.hasPrefix(prefix) {
            return (level, String(line.dropFirst(prefix.count)))
        }
    }
    return nil
}

private func isListItem(_ line: String) -> Bool {
    (line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ "))
}

private func parseOrderedItem(_ line: String) -> String? {
    guard let dot = line.firstIndex(of: "."),
          let numStr = line[line.startIndex..<dot].components(separatedBy: " ").first,
          Int(numStr) != nil,
          line.count > line.distance(from: line.startIndex, to: dot) + 2
    else { return nil }
    let afterDot = line.index(dot, offsetBy: 2)
    return String(line[afterDot...])
}

// MARK: - Syntax highlighter

private enum SyntaxHighlighter {

    static func highlight(code: String, language: String) -> AttributedString {
        let ns   = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: (code as NSString).length)
        let lang = language.lowercased()

        let defaultColor = NSColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1)
        let strColor     = NSColor(red: 0.89, green: 0.67, blue: 0.44, alpha: 1) // orange
        let commentColor = NSColor(red: 0.52, green: 0.69, blue: 0.49, alpha: 1) // green
        let numColor     = NSColor(red: 0.68, green: 0.74, blue: 1.00, alpha: 1) // blue
        let kwColor      = NSColor(red: 0.90, green: 0.55, blue: 0.76, alpha: 1) // pink
        let typeColor    = NSColor(red: 0.50, green: 0.85, blue: 0.85, alpha: 1) // teal
        let fnColor      = NSColor(red: 0.60, green: 0.76, blue: 1.00, alpha: 1) // light blue

        ns.addAttribute(.foregroundColor, value: defaultColor, range: full)

        func apply(_ pattern: String, _ color: NSColor, opts: NSRegularExpression.Options = []) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
            re.enumerateMatches(in: code, range: full) { m, _, _ in
                guard let r = m?.range else { return }
                ns.addAttribute(.foregroundColor, value: color, range: r)
            }
        }

        // Order matters — later calls win for overlapping ranges
        // 1. Strings
        apply(#"("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"#, strColor)
        // Triple-quoted (Swift/Python)
        apply(#""{3}[\s\S]*?"{3}"#, strColor, opts: [.dotMatchesLineSeparators])

        // 2. Comments (override strings in comments)
        apply(#"//[^\n]*"#, commentColor)
        apply(#"#[^\n]*"#, commentColor)   // Python / bash
        apply(#"/\*[\s\S]*?\*/"#, commentColor, opts: [.dotMatchesLineSeparators])

        // 3. Numbers
        apply(#"\b0x[0-9a-fA-F]+\b|\b\d+\.?\d*([eE][+-]?\d+)?\b"#, numColor)

        // 4. Function calls (before keywords so kw wins)
        apply(#"\b([a-z_][a-zA-Z0-9_]*)\s*\("#, fnColor)

        // 5. Type names (uppercase first char)
        if ["swift", "kotlin", "java", "typescript", "ts", "cs", "rust", "rs"].contains(lang) {
            apply(#"\b[A-Z][a-zA-Z0-9_]*\b"#, typeColor)
        }

        // 6. Keywords
        let kws = keywords(for: lang)
        if !kws.isEmpty {
            let kwPattern = #"\b("# + kws.joined(separator: "|") + #")\b"#
            apply(kwPattern, kwColor)
        }

        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(code)
    }

    // swiftlint:disable function_body_length
    private static func keywords(for lang: String) -> [String] {
        switch lang {
        case "swift":
            return ["func","var","let","class","struct","enum","protocol","extension",
                    "import","return","if","else","guard","for","while","in","do",
                    "try","catch","throw","throws","async","await","actor","final",
                    "public","private","internal","fileprivate","open","static","override",
                    "init","deinit","self","Self","super","true","false","nil","switch",
                    "case","default","break","continue","where","typealias","@MainActor",
                    "nonisolated","some","any","lazy","weak","unowned","mutating","inout"]
        case "python","py":
            return ["def","class","import","from","return","if","elif","else","for",
                    "while","in","not","and","or","is","lambda","with","as","try",
                    "except","finally","raise","pass","break","continue","True","False",
                    "None","async","await","yield","global","nonlocal","del","assert"]
        case "javascript","js","typescript","ts":
            return ["function","var","let","const","class","import","export","return",
                    "if","else","for","while","do","switch","case","break","continue",
                    "new","delete","typeof","instanceof","in","of","try","catch","finally",
                    "throw","async","await","yield","from","default","true","false","null",
                    "undefined","this","super","extends","interface","type","enum",
                    "abstract","public","private","protected","readonly","static","override"]
        case "go","golang":
            return ["func","var","const","type","struct","interface","import","package",
                    "return","if","else","for","range","switch","case","break","continue",
                    "go","chan","select","defer","map","make","new","delete","append",
                    "true","false","nil","error","string","int","bool","byte","rune"]
        case "rust","rs":
            return ["fn","let","mut","const","struct","enum","impl","trait","use","mod",
                    "pub","crate","super","self","Self","return","if","else","for","while",
                    "loop","match","in","where","type","async","await","move","ref","box",
                    "dyn","true","false","Some","None","Ok","Err"]
        case "kotlin","kt":
            return ["fun","val","var","class","object","interface","import","package",
                    "return","if","else","when","for","while","do","in","is","as","try",
                    "catch","finally","throw","override","abstract","open","final",
                    "companion","data","sealed","inner","lateinit","by","true","false","null"]
        case "java":
            return ["public","private","protected","class","interface","extends","implements",
                    "import","package","return","void","static","final","abstract","if","else",
                    "for","while","do","switch","case","break","continue","new","this","super",
                    "instanceof","try","catch","finally","throw","throws","true","false","null"]
        case "c","cpp","c++","cc","cxx","h","hpp":
            return ["auto","break","case","char","const","continue","default","do","double",
                    "else","enum","extern","float","for","goto","if","inline","int","long",
                    "register","return","short","signed","sizeof","static","struct","switch",
                    "typedef","union","unsigned","void","volatile","while","true","false",
                    "nullptr","class","template","namespace","using","public","private","protected"]
        case "bash","sh","shell","zsh":
            return ["if","fi","then","else","elif","for","do","done","while","case","esac",
                    "in","function","return","export","local","readonly","echo","exit","source",
                    "true","false","test","select","until"]
        case "ruby","rb":
            return ["def","class","module","end","do","if","unless","else","elsif","then",
                    "while","until","for","begin","rescue","ensure","raise","return","yield",
                    "include","extend","require","require_relative","true","false","nil",
                    "self","super","attr_reader","attr_writer","attr_accessor"]
        case "csharp","cs":
            return ["abstract","as","base","bool","break","byte","case","catch","char","checked",
                    "class","const","continue","decimal","default","delegate","do","double","else",
                    "enum","event","explicit","extern","false","finally","fixed","float","for",
                    "foreach","goto","if","implicit","in","int","interface","internal","is","lock",
                    "long","namespace","new","null","object","operator","out","override","params",
                    "private","protected","public","readonly","ref","return","sbyte","sealed",
                    "short","sizeof","stackalloc","static","string","struct","switch","this",
                    "throw","true","try","typeof","uint","ulong","unchecked","unsafe","ushort",
                    "using","virtual","void","volatile","while","async","await","var","yield"]
        default:
            return []
        }
    }
}
