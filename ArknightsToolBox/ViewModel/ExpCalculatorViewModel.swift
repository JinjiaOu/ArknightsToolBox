//
//  ExpCalculatorViewModel.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/22/25.
//

import SwiftUI

class ExpCalculatorViewModel: ObservableObject {
    @Published var starLevel: Int = 6 {
        didSet {
            adjustPhasesForStarLevel()
            clampLevels()
        }
    }

    @Published var currentPhase: String = "精0" {
        didSet { clampLevels() }
    }
    @Published var currentLevel: Int = 1
    @Published var currentExp: Int = 0

    @Published var targetPhase: String = "精0" {
        didSet { clampLevels() }
    }
    @Published var targetLevel: Int = 1

    @Published var ownedRecords: [String: Int] = ["高级": 0, "中级": 0, "初级": 0, "基础": 0]
    @Published var ownedCoin: Int = 0

    @Published var neededExp: Int = 0
    @Published var neededCoin: Int = 0
    @Published var recommendedRecords: [String: Int] = [:]
    @Published var showResult = false

    private let levelOrder = ["精0", "精1", "精2"]

    let levelCaps: [Int: [String: Int]] = [
        6: ["精0": 50, "精1": 80, "精2": 90],
        5: ["精0": 50, "精1": 70, "精2": 80],
        4: ["精0": 45, "精1": 60, "精2": 70],
        3: ["精0": 40, "精1": 55],
        2: ["精0": 30],
        1: ["精0": 30]
    ]

    private let recordExp: [String: Int] = [
        "高级": 2000,
        "中级": 1000,
        "初级": 400,
        "基础": 200
    ]

    private let eliteCost: [Int: [String: Int]] = [
        6: ["精0→精1": 30000, "精1→精2": 180000],
        5: ["精0→精1": 20000, "精1→精2": 120000],
        4: ["精0→精1": 15000, "精1→精2": 60000],
        3: ["精0→精1": 10000]
    ]

    func clampLevels() {
        let cap = levelCaps[starLevel]?[currentPhase] ?? 1
        currentLevel = min(currentLevel, cap)
        targetLevel = min(targetLevel, levelCaps[starLevel]?[targetPhase] ?? 1)
    }

    func maxCurrentLevel() {
        currentLevel = levelCaps[starLevel]?[currentPhase] ?? currentLevel
    }

    func maxTargetLevel() {
        targetLevel = levelCaps[starLevel]?[targetPhase] ?? targetLevel
    }

    func maxCurrentExp() {
        currentExp = getMaxExpForLevel(phase: currentPhase, level: currentLevel) - 1
    }

    func getMaxExpForLevel(phase: String, level: Int) -> Int {
        return ExpData.data[phase]?[safe: level - 1]?.exp ?? 0
    }

    func calculate() {
        let totalNeededExp = calculateTotalExp(
            fromPhase: currentPhase,
            fromLevel: currentLevel,
            currentExp: currentExp,
            toPhase: targetPhase,
            toLevel: targetLevel
        )

        let totalNeededCoin = calculateTotalCoin(
            fromPhase: currentPhase,
            fromLevel: currentLevel,
            toPhase: targetPhase,
            toLevel: targetLevel
        )

        var remainingExp = totalNeededExp
        let sortedRecords = recordExp.sorted { $0.value > $1.value }

        for (type, value) in sortedRecords {
            let available = ownedRecords[type] ?? 0
            let offset = min(available * value, remainingExp)
            remainingExp -= offset
        }

        neededExp = max(0, remainingExp)
        neededCoin = max(0, totalNeededCoin - ownedCoin)

        recommendedRecords = [:]
        var recommendRemaining = neededExp
        for (type, value) in sortedRecords {
            let count = recommendRemaining / value
            if count > 0 {
                recommendedRecords[type] = count
                recommendRemaining -= count * value
            }
        }

        showResult = true
    }

    func calculateTotalExp(fromPhase: String, fromLevel: Int, currentExp: Int, toPhase: String, toLevel: Int) -> Int {
        guard let fromIndex = levelOrder.firstIndex(of: fromPhase),
              let toIndex = levelOrder.firstIndex(of: toPhase),
              fromIndex <= toIndex else { return 0 }

        var total = 0
        for i in fromIndex...toIndex {
            let phase = levelOrder[i]
            let start = (i == fromIndex) ? fromLevel : 1
            let end = (i == toIndex) ? toLevel : (levelCaps[starLevel]?[phase] ?? 1)

            for lvl in start..<end {
                total += ExpData.data[phase]?[safe: lvl - 1]?.exp ?? 0
            }
        }

        total -= currentExp
        return max(0, total)
    }

    func calculateTotalCoin(fromPhase: String, fromLevel: Int, toPhase: String, toLevel: Int) -> Int {
        guard let fromIndex = levelOrder.firstIndex(of: fromPhase),
              let toIndex = levelOrder.firstIndex(of: toPhase),
              fromIndex <= toIndex else { return 0 }

        var total = 0
        for i in fromIndex...toIndex {
            let phase = levelOrder[i]
            let start = (i == fromIndex) ? fromLevel : 1
            let end = (i == toIndex) ? toLevel : (levelCaps[starLevel]?[phase] ?? 1)

            for lvl in start..<end {
                total += ExpData.data[phase]?[safe: lvl - 1]?.coin ?? 0
            }

            if i > fromIndex {
                let from = levelOrder[i - 1]
                let to = levelOrder[i]
                let key = "\(from)→\(to)"
                total += eliteCost[starLevel]?[key] ?? 0
            }
        }

        return total
    }

    private func adjustPhasesForStarLevel() {
        guard let allowedPhases = levelCaps[starLevel]?.keys else { return }
        let sorted = allowedPhases.sorted(by: { levelOrder.firstIndex(of: $0)! < levelOrder.firstIndex(of: $1)! })
        let maxAllowed = sorted.last ?? "精0"

        if !allowedPhases.contains(currentPhase) {
            currentPhase = maxAllowed
        }
        if !allowedPhases.contains(targetPhase) {
            targetPhase = maxAllowed
        }
    }

    func reset() {
        starLevel = 6
        currentPhase = "精0"
        currentLevel = 1
        currentExp = 0
        targetPhase = "精0"
        targetLevel = 1
        ownedRecords = ["高级": 0, "中级": 0, "初级": 0, "基础": 0]
        ownedCoin = 0
        neededExp = 0
        neededCoin = 0
        recommendedRecords = [:]
        showResult = false
    }

}
