//
//  ResultViewModel.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import Foundation

struct TagCombinationResult: Identifiable {
    let id = UUID()
    let combinationTags: [String]
    let starLevel: String
    let possibleCharacters: [Character]
}

class ResultViewModel: ObservableObject {
    @Published var tagCombinations: [TagCombinationResult] = []
    private let characterData = CharacterData()
    private var mainViewTags: [String] = []
    
    private func starLevelToInt(_ starLevel: String) -> Int {
        return Int(starLevel.replacingOccurrences(of: "★", with: "")) ?? 0
    }
    
    private func isStarTag(_ tag: String) -> Bool {
        return tag.contains("★") || tag == "全选"
    }
    
    private func getNonStarTags() -> [String] {
        return mainViewTags.filter { !isStarTag($0) }
    }
    
    private func getSelectedStarLevels() -> [String] {
        return mainViewTags.filter { $0.contains("★") }
    }
    
    private func isCharacterStarAllowed(_ character: Character) -> Bool {
        let selectedStars = getSelectedStarLevels()
        
        // If no star levels are explicitly selected, allow all stars
        if selectedStars.isEmpty {
            return true
        }
        
        // Special handling for 6★
        if character.starLevel == .sixStar {
            return mainViewTags.contains("高级资深干员")
        }
        
        // Check if character's star level is in selected stars
        return selectedStars.contains(character.starLevel.rawValue)
    }
    
    func updateMainViewTags(_ tags: [String]) {
        mainViewTags = tags.filter { $0 != "全选" } // Remove "全选" from tags
        findValidCombinations()
    }
    
    private func findValidCombinations() {
        var results: [TagCombinationResult] = []
        let nonStarTags = getNonStarTags()
        
        // Only proceed if there are non-star tags selected
        if nonStarTags.isEmpty {
            tagCombinations = []
            return
        }
        
        // Single tag combinations
        for tag in nonStarTags {
            let matchingChars = characterData.characters.filter { character in
                let charTags = character.getTagsAsStrings()
                return charTags.contains(tag) && isCharacterStarAllowed(character)
            }
            
            if !matchingChars.isEmpty {
                let sortedChars = matchingChars.sorted { char1, char2 in
                    let star1 = starLevelToInt(char1.starLevel.rawValue)
                    let star2 = starLevelToInt(char2.starLevel.rawValue)
                    return star1 > star2
                }
                
                results.append(TagCombinationResult(
                    combinationTags: [tag],
                    starLevel: sortedChars[0].starLevel.rawValue,
                    possibleCharacters: sortedChars
                ))
            }
        }
        
        // Two tag combinations
        for i in 0..<nonStarTags.count {
            for j in (i+1)..<nonStarTags.count {
                let tag1 = nonStarTags[i]
                let tag2 = nonStarTags[j]
                
                let matchingChars = characterData.characters.filter { character in
                    let charTags = character.getTagsAsStrings()
                    return charTags.contains(tag1) &&
                           charTags.contains(tag2) &&
                           isCharacterStarAllowed(character)
                }
                
                if !matchingChars.isEmpty {
                    let sortedChars = matchingChars.sorted { char1, char2 in
                        let star1 = starLevelToInt(char1.starLevel.rawValue)
                        let star2 = starLevelToInt(char2.starLevel.rawValue)
                        return star1 > star2
                    }
                    
                    results.append(TagCombinationResult(
                        combinationTags: [tag1, tag2],
                        starLevel: sortedChars[0].starLevel.rawValue,
                        possibleCharacters: sortedChars
                    ))
                }
            }
        }
        
        // Sort combinations by star level
        tagCombinations = results.sorted { result1, result2 in
            let star1 = starLevelToInt(result1.starLevel)
            let star2 = starLevelToInt(result2.starLevel)
            return star1 > star2
        }
    }
    
    func resetToMainViewTags() {
        findValidCombinations()
    }
}
