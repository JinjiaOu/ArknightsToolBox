//
//  MaterialParser.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation

// MARK: - 提取模板块（如 {{精英化材料}}, {{技能升级材料}}）
func extractFullTemplateBlock(from text: String, templateName: String) -> String? {
    // 使用 (?m) 多行模式，确保跨行匹配
    let pattern = "\\{\\{\(templateName)([\\s\\S]*?)\\n\\}\\}"
    let regex = try! NSRegularExpression(pattern: pattern)
    if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
       let range = Range(match.range(at: 0), in: text) {
        let block = String(text[range])
        print(" 找到模板 [\(templateName)]，长度：\(block.count) 字符")
        return block
    } else {
        print(" 未找到模板 [\(templateName)]")
        return nil
    }
}


// MARK: - 提取精英化 / 技能升级材料

func extractMaterialList(from template: String) -> [String: [(String, String)]] {
    let lines = template.split(separator: "\n")
    print(" 解析材料列表，共 \(lines.count) 行")

    var result: [String: [(String, String)]] = [:]

    for line in lines {
        guard let sepIndex = line.firstIndex(of: "=") else { continue }

        let rawKey = String(line.prefix(upTo: sepIndex)).trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.replacingOccurrences(of: "|", with: "") // 清除起始 `|` 符号
        let value = String(line.suffix(from: line.index(after: sepIndex)))

        let materialRegex = try! NSRegularExpression(pattern: "\\{\\{材料消耗\\|(.*?)\\|(.*?)\\}\\}")
        let matches = materialRegex.matches(in: value, range: NSRange(value.startIndex..., in: value))

        var materials: [(String, String)] = []

        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: value),
               let countRange = Range(match.range(at: 2), in: value) {
                let name = String(value[nameRange])
                let count = String(value[countRange])
                materials.append((name, count))
            }
        }

        if !materials.isEmpty {
            result[key] = materials
            let preview = materials.map { "\($0.0)×\($0.1)" }.joined(separator: "、")
            print(" [\(key)] 提取到 \(materials.count) 项：\(preview)")
        }
    }

    if result.isEmpty {
        print(" 没有解析到任何材料条目")
    }else if result.count <= 1 {
        print(" 提示：材料可能使用了嵌套模板（如 {{精英1材料片段}}），建议查看 PRTS Wiki 页面获取完整信息")
    }

    return result
}

// MARK: - 模组材料字段提取

func extractModuleMaterialList(from template: String) -> [String: [(String, String)]] {
    var result: [String: [(String, String)]] = [:]

    let pattern = "\\|\\s*(材料消耗(?:\\d*)?)\\s*=([\\s\\S]*?)(?=\\n\\|\\s*\\w+\\s*=|\\n\\}\\}|$)"
    let regex = try! NSRegularExpression(pattern: pattern)
    let nsrange = NSRange(template.startIndex..., in: template)

    for match in regex.matches(in: template, range: nsrange) {
        guard let keyRange = Range(match.range(at: 1), in: template),
              let valueRange = Range(match.range(at: 2), in: template) else { continue }

        let key = String(template[keyRange])
        let rawValue = String(template[valueRange])

        let materialRegex = try! NSRegularExpression(pattern: "\\{\\{材料消耗\\|([^|}]+)\\|([^}]+)\\}\\}")
        let matches = materialRegex.matches(in: rawValue, range: NSRange(rawValue.startIndex..., in: rawValue))

        var materials: [(String, String)] = []

        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: rawValue),
               let countRange = Range(match.range(at: 2), in: rawValue) {
                let name = rawValue[nameRange].trimmingCharacters(in: .whitespaces)
                let count = rawValue[countRange].trimmingCharacters(in: .whitespaces)
                materials.append((name, count))
            }
        }

        if !materials.isEmpty {
            result[key] = materials
            print(" 模组阶段 [\(key)] 提取 \(materials.count) 项")
        }
    }

    return result
}

// MARK: - 模组模板整体提取

func extractModuleMaterials(from content: String) -> [(String, [String: [(String, String)]])] {
    var result: [(String, [String: [(String, String)]])] = []
    let blocks = content.components(separatedBy: "{{模组").dropFirst()

    for (index, block) in blocks.enumerated() {
        let template = "{{模组" + block
        guard let endIndex = template.range(of: "\n}}")?.upperBound else {
            print(" 模组块 \(index + 1) 未找到结束符 }}")
            continue
        }

        let cropped = String(template.prefix(upTo: endIndex))

        // 模组名称提取
        let nameRegex = try! NSRegularExpression(pattern: "\\|\\s*名称\\s*=\\s*([^|\\n]+)")
        let nameMatch = nameRegex.firstMatch(in: cropped, range: NSRange(cropped.startIndex..., in: cropped))
        let moduleName = nameMatch.flatMap {
            Range($0.range(at: 1), in: cropped).map { String(cropped[$0]).trimmingCharacters(in: .whitespaces) }
        } ?? "模组 \(index + 1)"

        print(" 解析模组 [\(moduleName)]")

        let materialDict = extractModuleMaterialList(from: cropped)
        if materialDict.isEmpty {
            print(" 模组 [\(moduleName)] 无材料数据")
        }
        result.append((moduleName, materialDict))
    }

    if result.isEmpty {
        print(" 页面未提取到任何模组模板")
    }

    return result
}
