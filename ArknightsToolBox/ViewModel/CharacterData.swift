//
//  CharacterData.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation
import FirebaseStorage  //  新增：Firebase Storage 支持

// 中间结构体：用于解码 JSON 文件
struct RecruitCharacter: Codable {
    let name: String
    let method: String
    let tags: [String]
    let rarity: Int
}

class CharacterData: ObservableObject {
    @Published var characters: [Character] = []

    init() {
        loadCharactersFromCloud()
    }

    // MARK: - 从 Firebase 加载
    private func loadCharactersFromCloud() {
        let storage = Storage.storage()
        let ref = storage.reference(withPath: "json/公开招募干员带标签.json")

        ref.getData(maxSize: 5 * 1024 * 1024) { data, error in
            if let error = error {
                print(" Firebase 加载干员数据失败：\(error.localizedDescription)，改用本地文件。")
                self.loadCharactersFromLocal()
                return
            }

            guard let data = data else {
                print(" Firebase 返回空数据，改用本地文件。")
                self.loadCharactersFromLocal()
                return
            }

            do {
                let recruitData = try JSONDecoder().decode([RecruitCharacter].self, from: data)
                self.parseCharacters(from: recruitData)
                print(" 已从 Firebase 加载公开招募干员数据，共 \(recruitData.count) 条。")
            } catch {
                print(" Firebase JSON 解码失败：\(error.localizedDescription)，改用本地文件。")
                self.loadCharactersFromLocal()
            }
        }
    }

    // MARK: - 从本地文件加载（离线模式）
    private func loadCharactersFromLocal() {
        guard let url = Bundle.main.url(forResource: "公开招募干员带标签", withExtension: "json") else {
            print(" 无法找到本地 JSON 文件。")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let recruitData = try JSONDecoder().decode([RecruitCharacter].self, from: data)
            self.parseCharacters(from: recruitData)
            print(" 已从本地加载公开招募干员数据，共 \(recruitData.count) 条。")
        } catch {
            print(" 本地 JSON 解码失败: \(error)")
        }
    }

    // MARK: - 统一的解析函数
    private func parseCharacters(from recruitData: [RecruitCharacter]) {
        DispatchQueue.main.async {
            self.characters = recruitData.map { entry in
                //  新的星级处理逻辑（基于 rarity）
                let starLevel: StarLevel = {
                    switch entry.rarity {
                    case 5: return .sixStar
                    case 4: return .fiveStar
                    case 3: return .fourStar
                    case 2: return .threeStar
                    case 1: return .twoStar
                    case 0: return .oneStar
                    default: return .fourStar
                    }
                }()

                // 旧数据把多个标签合并成一个字符串（如 "输出 防护"），先按空白拆开再精确匹配。
                // 不能用子串匹配：否则 "支援机械" 会被当成 "支援"，"高级资深干员" 会被当成 "资深干员"。
                let tags = Set(entry.tags.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) })

                let profession = Profession.allCases.first {
                    tags.contains($0.rawValue)
                } ?? .guardsman

                let location = Location.allCases.first {
                    tags.contains($0.rawValue)
                } ?? .melee

                let abilities = Ability.allCases.filter { tags.contains($0.rawValue) }

                return Character(
                    name: entry.name,
                    starLevel: starLevel,
                    profession: profession,
                    location: location,
                    abilities: abilities
                )
            }
        }
    }

    // MARK: - 获取所有标签
    func getAllTags() -> [String] {
        var tags: Set<String> = []

        characters.forEach { character in
            tags.insert(character.starLevel.rawValue)
            tags.insert(character.profession.rawValue)
            tags.insert(character.location.rawValue)
            character.abilities.forEach { tags.insert($0.rawValue) }
        }

        return Array(tags).sorted()
    }
}
