//
//  CharacterData.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation

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
        loadCharactersFromJSON()
    }

    private func loadCharactersFromJSON() {
        guard let url = Bundle.main.url(forResource: "公开招募干员带标签", withExtension: "json") else {
            print("❌ 无法找到 JSON 文件")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let recruitData = try JSONDecoder().decode([RecruitCharacter].self, from: data)

            self.characters = recruitData.map { entry in
                // ⭐ 新的星级处理逻辑（基于 rarity）
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

                let profession = Profession.allCases.first {
                    entry.tags.contains($0.rawValue)
                } ?? .guardsman

                let location = Location.allCases.first {
                    entry.tags.contains($0.rawValue)
                } ?? .melee

                let abilities = Ability.allCases.filter { ab in
                    entry.tags.contains { $0.contains(ab.rawValue) }
                }

                return Character(
                    name: entry.name,
                    starLevel: starLevel,
                    profession: profession,
                    location: location,
                    abilities: abilities
                )
            }

        } catch {
            print("❌ JSON 解码失败: \(error)")
        }
    }


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
