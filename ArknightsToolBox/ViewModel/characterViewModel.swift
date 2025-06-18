//
//  characterViewModel.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation

class CharacterViewModel: ObservableObject {
    @Published var starLevels: [String]
    @Published var qualifications: [String]
    @Published var professions: [String]
    @Published var locations: [String]
    @Published var abilities: [String]
    
    init() {
        starLevels = StarLevel.allCases.map { $0.rawValue }
        qualifications = ["高级资深干员", "资深干员", "新手", "支援机制"] // Example custom list
        professions = Profession.allCases.map { $0.rawValue }
        locations = Location.allCases.map { $0.rawValue }
        abilities = Ability.allCases.map { $0.rawValue }
    }
}
