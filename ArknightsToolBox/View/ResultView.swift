//
//  ResultView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

extension Character {
    func getStarColor() -> Color {
        switch self.starLevel {
        case .sixStar:
            return Color(hex: "#FF3B30") // 红
        case .fiveStar:
            return Color(hex: "#FF9500") // 橙
        case .fourStar:
            return Color(hex: "#007AFF") // 蓝
        case .threeStar:
            return Color(hex: "#34C759") // 绿
        case .twoStar:
            return Color(hex: "#AF52DE") // 紫
        case .oneStar:
            return Color.white
        case .all:
            return Color.white
        }
    }

}

struct CombinationResultView: View {
    let combination: TagCombinationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标签展示
            HStack(spacing: 8) {
                ForEach(combination.combinationTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .arknightsTagStyle()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(combination.starLevel)
                    .foregroundColor(Color(hex: "#FF8C00"))
                    .font(.system(size: 14, weight: .bold))

                FlowLayout(spacing: 8) {
                    ForEach(combination.possibleCharacters) { character in
                        HStack(spacing: 6) {
                            Image(character.imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))

                            Text(character.name)
                                .foregroundColor(character.getStarColor())
                                .font(.system(size: 14))
                        }
                        .padding(4)
                        .background(Color(hex: "#1E1E1E"))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#1A1A1A"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#FF8C00").opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ResultView: View {
    @ObservedObject var viewModel: ResultViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(hex: "#0F0F0F").ignoresSafeArea()

            VStack(spacing: 16) {
                // 顶部栏
                HStack {
                    Spacer()
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "#FF8C00"))
                }
                .padding(.horizontal)

                Text("筛选结果")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "#FF8C00"))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.tagCombinations) { result in
                            CombinationResultView(combination: result)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
    }
}

#Preview {
    ResultView(viewModel: ResultViewModel())
}

