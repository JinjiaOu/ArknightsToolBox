//
//  WikiDataParser.swift
//  ArknightsToolBox
//
//  干员名单、模组、技能、公招等数据的解析规则。
//  对应 ArknightsResourceTool 的 data.py。
//

import Foundation

// MARK: - 数据模型（与云端 JSON 结构一致）

struct ModuleEntry: Codable, Equatable {
    let name: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case name = "名称"
        case type = "类型"
    }
}

struct RecruitEntry: Codable, Equatable {
    let name: String
    let rarity: Int
    let method: String
    let tags: [String]
}

struct MaterialEntry: Codable, Equatable {
    let name: String
    let rarity: Int
}

enum WikiParseError: LocalizedError {
    case incomplete(String)

    var errorDescription: String? {
        switch self {
        case .incomplete(let name): return "公招字段解析不完整：\(name)"
        }
    }
}

// MARK: - 解析规则

enum WikiDataParser {
    /// 不属于正式干员列表的页面（卫戍协议、预备干员等）
    static let excludedOperators: Set<String> = [
        "echanist(卫戍协议)", "Misery(卫戍协议)", "Pith", "Pith(卫戍协议)", "Raidian(卫戍协议)",
        "Sharp", "Sharp(卫戍协议)", "Stormeye", "Stormeye(卫戍协议)", "Touch", "Touch(卫戍协议)",
        "暮落(集成战略)", "郁金香", "郁金香(卫戍协议)", "预备干员-先锋(卫戍协议)",
        "预备干员-医疗(卫戍协议)", "预备干员-后勤", "预备干员-术师", "预备干员-术师(卫戍协议)",
        "预备干员-特种(卫戍协议)", "预备干员-狙击", "预备干员-狙击(卫戍协议)",
        "预备干员-辅助(卫戍协议)", "预备干员-近卫(卫戍协议)", "预备干员-近战", "预备干员-重装",
        "预备干员-重装(卫戍协议)", "Mechanist(卫戍协议)", "领主·Sharp", "盟约·辅助干员"
    ]

    /// 分类成员 → 干员名单
    static func operatorNames(fromCategory members: [String]) -> [String] {
        Set(members).subtracting(excludedOperators).sorted()
    }

    /// 模组类型名规范化，需与 App 取图时的 normalizeType 保持一致
    static func moduleType(_ value: String) -> String {
        // 注意：工程内有自定义的 Character 类型，这里不要显式写出标准库的 Character
        let map = ["α": "A", "β": "B", "γ": "G", "δ": "D", "Δ": "D", "τ": "T"]
        return value.map { map[String($0)] ?? String($0) }.joined()
    }

    /// "道具一览"页面 → 材料目录（材料、技巧概要、芯片、芯片组、双芯片、作战记录，以及龙门币）
    static func materialCatalog(fromHTML html: String) -> [MaterialEntry] {
        let allowed: Set<String> = ["材料", "技巧概要", "芯片", "芯片组", "双芯片", "作战记录"]
        guard let tagPattern = try? NSRegularExpression(pattern: "<[^<>]*\\sdata-name=\"[^\"]*\"[^<>]*>"),
              let attrPattern = try? NSRegularExpression(pattern: "(data-[a-z0-9-]+)=\"([^\"]*)\"") else { return [] }

        var result: [String: MaterialEntry] = [:]
        let range = NSRange(html.startIndex..., in: html)
        for match in tagPattern.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])

            var attrs: [String: String] = [:]
            for attr in attrPattern.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                if let key = Range(attr.range(at: 1), in: tag), let value = Range(attr.range(at: 2), in: tag) {
                    attrs[String(tag[key])] = unescapeHTML(String(tag[value]))
                }
            }
            guard let name = attrs["data-name"]?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let rarityText = attrs["data-rarity"]?.trimmingCharacters(in: .whitespaces),
                  let rarity = Int(rarityText) else { continue }

            var categories = Set(["data-category1", "data-category2", "data-category3"]
                .compactMap { attrs[$0]?.trimmingCharacters(in: .whitespaces) })
            // 旧版页面：data-category 里写着 "分类:材料" 之类
            if let legacy = attrs["data-category"] {
                for part in legacy.components(separatedBy: CharacterSet(charactersIn: " ,，;；|")) {
                    for prefix in ["分类:", "Category:"] where part.hasPrefix(prefix) {
                        categories.insert(String(part.dropFirst(prefix.count)))
                    }
                }
            }
            if name == "龙门币" || !categories.isDisjoint(with: allowed) {
                result[name] = MaterialEntry(name: name, rarity: rarity)
            }
        }
        return result.values.sorted { Array($0.name.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.name.unicodeScalars.map(\.value)) }
    }

    /// 还原 HTML 实体：&amp; &lt; &gt; &quot; &#39; 以及 &#95; &#x5f; 这类数字实体
    static func unescapeHTML(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&quot;": "\"", "&lt;": "<", "&gt;": ">", "&apos;": "'"]
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        if let numeric = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            let matches = numeric.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let whole = Range(match.range, in: result), let codeRange = Range(match.range(at: 1), in: result) else { continue }
                let code = String(result[codeRange])
                let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                if let value, let scalar = Unicode.Scalar(value) { result.replaceSubrange(whole, with: String(scalar)) }
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")      // 最后处理，避免二次还原
    }

    /// 页面源码 → 模组列表（类型保持页面原值，忽略没有类型的证章）
    static func modules(from text: String) -> [ModuleEntry] {
        var result: [ModuleEntry] = []
        for template in WikiParser.templates(in: text)
        where template.name.hasSuffix("模组") && template.has("名称") {
            let name = WikiText.stripCode(template.param("名称")?.value ?? "")
            let type = WikiText.stripCode(template.param("类型")?.value ?? "")
            // 没有类型的是干员证章，不是真正的模组，也无法对应类型图标
            if !name.isEmpty, !type.isEmpty { result.append(ModuleEntry(name: name, type: type)) }
        }
        return result
    }

    /// 页面源码 → 技能名列表（技能模板里的"技能名"字段，与 App 查询页取技能名的方式一致）
    static func skillNames(fromWikitext text: String) -> [String] {
        WikiParser.templates(in: text).compactMap { template -> String? in
            guard template.name.range(of: "^技能\\d*$", options: .regularExpression) != nil,
                  let name = template.trimmedValue("技能名"), !name.isEmpty else { return nil }
            return name
        }
    }

    /// 模组：先看"(升级)"页面，没有解析出内容再看主页面（与 ResourceTool 一致）
    static func modules(upgradeText: String?, mainText: String) -> [ModuleEntry] {
        if let upgradeText {
            let parsed = modules(from: upgradeText)
            if !parsed.isEmpty { return parsed }
        }
        return modules(from: mainText)
    }

    /// 页面图片列表 → (Wiki 文件名, 技能名)
    static func skillImages(fromImages images: [String]) -> [(file: String, name: String)] {
        images.compactMap { source in
            let normal = source.replacingOccurrences(of: " ", with: "_")
            guard normal.hasPrefix("技能_"), normal.hasSuffix(".png") else { return nil }
            return (source, String(normal.dropFirst("技能_".count).dropLast(".png".count)))
        }
    }

    /// 页面图片列表 → 技能名列表
    static func skillNames(fromImages images: [String]) -> [String] {
        skillImages(fromImages: images).map(\.name)
    }

    /// 页面源码 → 公招条目；非公招干员返回 nil
    static func recruitment(name: String, text: String) throws -> RecruitEntry? {
        var method = ""
        var tags = Set<String>()
        var rarity: Int?

        for template in WikiParser.templates(in: text) {
            if template.name == "干员获得方式", let value = template.trimmedValue("获得方式") {
                method = value
            }
            guard template.name.hasPrefix("CharinfoV2") else { continue }

            for key in ["tag", "标签"] where template.has(key) {
                let cleaned = WikiText.cleanMarkup(template.param(key)?.value ?? "")
                tags.formUnion(cleaned.components(separatedBy: CharacterSet(charactersIn: "、,，").union(.whitespacesAndNewlines))
                    .filter { !$0.isEmpty })
            }
            for key in ["职业", "位置"] where template.has(key) {
                let value = WikiText.cleanMarkup(template.param(key)?.value ?? "")
                if !value.isEmpty { tags.insert(key == "职业" ? value + "干员" : value) }
            }
            if let raw = template.trimmedValue("稀有度") {
                guard let value = Int(raw) else { throw WikiParseError.incomplete(name) }
                rarity = value
                if value == 4 { tags.insert("资深干员") }
                if value == 5 { tags.insert("高级资深干员") }
            }
        }

        guard !method.isEmpty, let rarity else { throw WikiParseError.incomplete(name) }
        guard method.contains("公开招募") else { return nil }
        let sorted = tags.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
        return RecruitEntry(name: name, rarity: rarity, method: method, tags: sorted)
    }
}
