//
//  Character.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation

enum StarLevel: String, CaseIterable {
    case all = "全选"
    case sixStar = "6★"
    case fiveStar = "5★"
    case fourStar = "4★"
    case threeStar = "3★"
    case twoStar = "2★"
    case oneStar = "1★"
}

enum Profession: String, CaseIterable {
    case guardsman = "近卫干员"
    case sniper = "狙击干员"
    case defender = "重装干员"
    case medic = "医疗干员"
    case supporter = "辅助干员"
    case caster = "术师干员"
    case specialist = "特种干员"
    case vanguard = "先锋干员"
}

enum Location: String, CaseIterable {
    case melee = "近战位"
    case ranged = "远程位"
}

enum Ability: String, CaseIterable {
    case newbie = "新手"
    case mechanical = "支援机械"
    case TopOperator = "高级资深干员"
    case SeniorOperator = "资深干员"
    case control = "控场"
    case burst = "爆发"
    case healing = "治疗"
    case support = "支援"
    case costRecovery = "费用回复"
    case damage = "输出"
    case survival = "生存"
    case aoe = "群攻"
    case protection = "防护"
    case slow = "减速"
    case weaken = "削弱"
    case fastRevive = "快速复活"
    case reposition = "位移"
    case summon = "召唤"
    case elemental = "元素"
   
}

class Character: Identifiable {
    let id = UUID()
    let name: String
    let starLevel: StarLevel
    let profession: Profession
    let location: Location
    let abilities: [Ability]
    
    init(name: String, starLevel: StarLevel, profession: Profession, location: Location, abilities: [Ability]) {
        self.name = name
        self.starLevel = starLevel
        self.profession = profession
        self.location = location
        self.abilities = abilities
    }
    
    // Get all tags as an array of strings
    func getTagsAsStrings() -> [String] {
        var tags: [String] = []
        tags.append(starLevel.rawValue)
        tags.append(profession.rawValue)
        tags.append(location.rawValue)
        tags.append(contentsOf: abilities.map { $0.rawValue })
        return tags
    }
}

extension Character {
    var imageName: String {
        "头像_\(name)"
    }
}
