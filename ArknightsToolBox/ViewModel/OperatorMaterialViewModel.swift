//
//  OperatorMaterial.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation
import Combine
import SwiftUI

class OperatorMaterialViewModel: ObservableObject {
    @Published var operatorName: String = ""
    @Published var suggestions: [String] = []
    @Published var eliteMaterials: [String: [(String, String)]] = [:]
    @Published var skillMaterials: [String: [(String, String)]] = [:]
    @Published var moduleMaterials: [(String, [String: [(String, String)]])] = []
    @Published var autoSuggestEnabled: Bool = true
    @Published var selectedOperatorName: String? = nil
    @Published var skillNames: [String] = []

    private var allOperators: [String] = []
    @Published private var materialRarityDict: [String: Int] = [:]
    private var operatorModuleDict: [String: [[String: String]]] = [:]
    private var cancellables = Set<AnyCancellable>()

    struct MaterialRarity: Codable {
        let name: String
        let rarity: Int
    }

    init() {
        loadOperators()
        loadMaterialRarities()
        loadModuleTypeData()

        // 自动建议功能
        $operatorName
            .debounce(for: 0.2, scheduler: DispatchQueue.main)
            .sink { [weak self] input in
                guard let self = self else { return }
                if self.autoSuggestEnabled {
                    self.updateSuggestions(for: input)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 加载干员列表
    private func loadOperators() {
        Task {
            guard let result = await CloudData.json.load(CloudPath.operators, as: [String].self) else {
                print(" 云端和本机缓存都没有 all_operators.json，改用内置文件。")
                loadOperatorsFromLocal()
                return
            }
            await MainActor.run {
                self.allOperators = result.value
                print(" 已从\(result.source == .cloud ? " Firebase " : "本机缓存")加载 \(result.value.count) 个干员。")
            }
        }
    }

    private func loadOperatorsFromLocal() {
        guard let url = Bundle.main.url(forResource: "all_operators", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            print(" 无法从本地加载 all_operators.json。")
            return
        }
        DispatchQueue.main.async {
            self.allOperators = list
            print(" 已从本地加载 \(list.count) 个干员。")
        }
    }

    // MARK: - 加载材料稀有度：先用本地（立即可用），再用云端数据覆盖（包含新材料）
    private func loadMaterialRarities() {
        loadMaterialRaritiesFromLocal()
        Task {
            guard let result = await CloudData.json.load(CloudPath.materials, as: [MaterialRarity].self) else {
                print(" 云端材料稀有度不可用，继续使用内置数据。")
                return
            }
            await MainActor.run {
                for item in result.value { self.materialRarityDict[item.name] = item.rarity }
                print(" 已从\(result.source == .cloud ? " Firebase " : "本机缓存")更新材料稀有度：共 \(result.value.count) 项。")
            }
        }
    }

    private func loadMaterialRaritiesFromLocal() {
        guard let url = Bundle.main.url(forResource: "arknights_materials_rarity", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([MaterialRarity].self, from: data) else {
            print(" 无法加载材料稀有度 JSON。")
            return
        }
        for item in list {
            materialRarityDict[item.name] = item.rarity
        }
        print(" 已加载材料稀有度：共 \(materialRarityDict.count) 项。")
    }

    // MARK: - 加载模组类型
    private func loadModuleTypeData() {
        Task {
            guard let result = await CloudData.json.load(CloudPath.modules, as: [String: [[String: String]]].self) else {
                print(" 云端和本机缓存都没有模组类型数据，改用内置文件。")
                loadModuleTypeDataFromLocal()
                return
            }
            await MainActor.run {
                self.operatorModuleDict = result.value
                print(" 已从\(result.source == .cloud ? " Firebase " : "本机缓存")加载模组类型数据。")
            }
        }
    }

    private func loadModuleTypeDataFromLocal() {
        guard let url = Bundle.main.url(forResource: "operator_modules_cleaned", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) else {
            print(" 无法从本地加载 operator_modules_cleaned.json。")
            return
        }
        DispatchQueue.main.async {
            self.operatorModuleDict = dict
            print(" 已从本地加载模组类型数据。")
        }
    }

    // MARK: - 其他功能保持不变
    func getModuleType(for operatorName: String, moduleName: String) -> String? {
        guard let modules = operatorModuleDict[operatorName] else { return nil }
        return modules.first(where: { $0["名称"] == moduleName })?["类型"]
    }

    func normalizeType(_ type: String) -> String {
        return type
            .replacingOccurrences(of: "Δ", with: "D")
            .replacingOccurrences(of: "α", with: "A")
            .replacingOccurrences(of: "β", with: "B")
            .replacingOccurrences(of: "γ", with: "G")
            .replacingOccurrences(of: "τ", with: "T")
    }

    func rarityColor(for material: String) -> Color {
        switch materialRarityDict[material] {
        case 4: return Color(hex: "#FFD700")
        case 3: return Color(hex: "#C678DD")
        case 2: return Color(hex: "#61AFEF")
        case 1: return Color(hex: "#98C379")
        case 0: return Color(hex: "#7F848E")
        default: return Color.white
        }
    }

    func updateSuggestions(for input: String) {
        suggestions = input.isEmpty ? [] : allOperators.filter {
            $0.localizedCaseInsensitiveContains(input)
        }
    }

    func fetchMaterials(for name: String) {
        operatorName = name
        selectedOperatorName = name
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let urlStr = "https://prts.wiki/api.php?action=query&prop=revisions&titles=\(encoded)&rvslots=main&rvprop=content&format=json"

        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["query"] as? [String: Any],
                  let pages = query["pages"] as? [String: Any],
                  let firstPage = pages.values.first as? [String: Any],
                  let revisions = firstPage["revisions"] as? [[String: Any]],
                  let slots = revisions.first?["slots"] as? [String: Any],
                  let content = slots["main"] as? [String: Any],
                  let rawText = content["*"] as? String else { return }

            DispatchQueue.main.async {
                self.eliteMaterials = extractMaterialList(from: extractFullTemplateBlock(from: rawText, templateName: "精英化材料") ?? "")
                self.skillMaterials = extractMaterialList(from: extractFullTemplateBlock(from: rawText, templateName: "技能升级材料") ?? "")
                self.moduleMaterials = extractModuleMaterials(from: rawText)
                self.skillNames = self.extractSkillNames(from: rawText)
            }
        }.resume()
    }

    func extractSkillNames(from text: String) -> [String] {
        let pattern = "\\|\\s*技能名\\s*=\\s*([^\\n|]+)"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        var names: [String] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: text) {
                let name = text[range].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    names.append(name)
                }
            }
            if names.count == 3 { break }
        }
        return names
    }

    func specializationLevelText(for levelStr: Substring) -> String {
        switch levelStr {
        case "8": return "专精一"
        case "9": return "专精二"
        case "10": return "专精三"
        default: return "Lv\(levelStr)"
        }
    }
}
