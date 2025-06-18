//
//  ExpData.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/22/25.
//

import Foundation

struct LevelExp: Codable {
    let level: Int
    let exp: Int
    let total_exp: Int
    let coin: Int
    let total_coin: Int
}

struct ExpData {
    static let data: [String: [LevelExp]] = {
        guard let url = Bundle.main.url(forResource: "exp_data", withExtension: "json"),
              let jsonData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [LevelExp]].self, from: jsonData) else {
            print(" 加载 exp_data.json 失败")
            return [:]
        }
        return decoded
    }()
}
