//
//  WikiTemplateParser.swift
//  ArknightsToolBox
//
//  轻量 wikitext 模板解析器，对应 ArknightsResourceTool 中的 mwparserfromhell 用法。
//  只依赖 Foundation，便于单独编译测试。
//

import Foundation

// MARK: - 模板结构

struct WikiTemplate {
    struct Param {
        let key: String          // 命名参数为名称；位置参数为 "1"、"2"……
        let value: String        // 原始值，未 trim
        let isPositional: Bool
    }

    let name: String
    let params: [Param]

    /// 与 mwparserfromhell 的 get() 一致：同名参数取最后一个
    func param(_ key: String) -> Param? {
        params.last { $0.key == key }
    }

    func has(_ key: String) -> Bool { param(key) != nil }

    func trimmedValue(_ key: String) -> String? {
        param(key)?.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 解析器

enum WikiParser {
    private static let lbrace = UInt8(ascii: "{")
    private static let rbrace = UInt8(ascii: "}")
    private static let lbracket = UInt8(ascii: "[")
    private static let rbracket = UInt8(ascii: "]")
    private static let pipe = UInt8(ascii: "|")
    private static let equals = UInt8(ascii: "=")

    /// 返回文本中的全部模板（含嵌套），按出现位置排序
    static func templates(in text: String) -> [WikiTemplate] {
        let bytes = Array(removeComments(text).utf8)
        let n = bytes.count
        var stack: [Int] = []                       // -1 表示 {{{参数}}}
        var ranges: [(start: Int, end: Int)] = []
        var i = 0

        while i < n {
            if i + 1 < n, bytes[i] == lbrace, bytes[i + 1] == lbrace {
                if i + 2 < n, bytes[i + 2] == lbrace {
                    stack.append(-1)
                    i += 3
                } else {
                    stack.append(i)
                    i += 2
                }
            } else if i + 1 < n, bytes[i] == rbrace, bytes[i + 1] == rbrace {
                if stack.last == -1, i + 2 < n, bytes[i + 2] == rbrace {
                    stack.removeLast()
                    i += 3
                } else if let start = stack.last, start >= 0 {
                    stack.removeLast()
                    ranges.append((start, i + 2))
                    i += 2
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }

        ranges.sort { $0.start < $1.start }
        return ranges.map { parseTemplate(bytes: bytes, start: $0.start + 2, end: $0.end - 2) }
    }

    private static func parseTemplate(bytes: [UInt8], start: Int, end: Int) -> WikiTemplate {
        let parts = splitTopLevel(bytes, from: start, to: end, separator: pipe)
        let name = string(bytes, parts.first ?? (start, start)).trimmingCharacters(in: .whitespacesAndNewlines)
        var params: [WikiTemplate.Param] = []
        var positional = 0

        for part in parts.dropFirst() {
            if let eq = firstTopLevel(equals, in: bytes, from: part.0, to: part.1) {
                let key = string(bytes, (part.0, eq)).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = string(bytes, (eq + 1, part.1))
                params.append(.init(key: key, value: value, isPositional: false))
            } else {
                positional += 1
                params.append(.init(key: String(positional), value: string(bytes, part), isPositional: true))
            }
        }
        return WikiTemplate(name: name, params: params)
    }

    /// 在最外层（不在 {{ }} 或 [[ ]] 内）按 | 切分，返回各段 [from, to) 区间
    private static func splitTopLevel(_ bytes: [UInt8], from: Int, to: Int, separator: UInt8) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var segmentStart = from
        scan(bytes, from: from, to: to) { index, byte in
            if byte == separator {
                result.append((segmentStart, index))
                segmentStart = index + 1
            }
            return true
        }
        result.append((segmentStart, to))
        return result
    }

    /// 最外层第一个目标字节的位置
    private static func firstTopLevel(_ target: UInt8, in bytes: [UInt8], from: Int, to: Int) -> Int? {
        var found: Int?
        scan(bytes, from: from, to: to) { index, byte in
            if byte == target { found = index; return false }
            return true
        }
        return found
    }

    /// 跳过嵌套的 {{ }} 与 [[ ]]，对最外层的每个字节调用 visit；visit 返回 false 时停止
    private static func scan(_ bytes: [UInt8], from: Int, to: Int, visit: (Int, UInt8) -> Bool) {
        var braces = 0
        var brackets = 0
        var i = from
        while i < to {
            let b = bytes[i]
            let next: UInt8? = i + 1 < to ? bytes[i + 1] : nil
            if b == lbrace, next == lbrace { braces += 1; i += 2; continue }
            if b == rbrace, next == rbrace, braces > 0 { braces -= 1; i += 2; continue }
            if b == lbracket, next == lbracket { brackets += 1; i += 2; continue }
            if b == rbracket, next == rbracket, brackets > 0 { brackets -= 1; i += 2; continue }
            if braces == 0, brackets == 0, !visit(i, b) { return }
            i += 1
        }
    }

    private static func string(_ bytes: [UInt8], _ range: (Int, Int)) -> String {
        String(decoding: bytes[range.0..<range.1], as: UTF8.self)
    }

    private static func removeComments(_ text: String) -> String {
        guard text.contains("<!--") else { return text }
        return text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
    }
}

// MARK: - 文本清理

enum WikiText {
    /// 对应 mwparserfromhell 的 strip_code：去掉标签、模板，保留链接显示文字
    static func stripCode(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[\\[(?:[^|\\]]*\\|)?([^\\]]*)\\]\\]", with: "$1", options: .regularExpression)
        var previous = ""
        while previous != s {
            previous = s
            s = s.replacingOccurrences(of: "\\{\\{[^{}]*\\}\\}", with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "'{2,5}", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 对应 data.py 的 clean_markup
    static func cleanMarkup(_ text: String) -> String {
        let steps: [(String, String)] = [
            ("<br\\s*/?>", "\n"),
            ("</?span[^>]*>", ""),
            ("\\{\\{材料消耗\\|([^|}]+)\\|([^}]+)\\}\\}", "$1 x $2"),
            ("\\{\\{(?:color|术语)\\|[^|}]+\\|([^}]+)\\}\\}", "$1"),
            ("\\{\\{变动数值lite\\|[^|}]+\\|[^|}]+\\|([^}]+)\\}\\}", "$1"),
            ("\\[\\[([^|\\]]+\\|)?([^\\]]+)\\]\\]", "$2"),
            ("\\{\\{[^{}]*?\\|([^{}]*?)\\}\\}", "$1")
        ]
        var s = text
        for (pattern, template) in steps {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
