//
//  RecruitView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

struct RecruitView: View {
    @State private var selectedStarLevels: [String] = ["全选", "5★", "4★", "3★", "2★", "1★"]
    @State private var selectedQualifications: [String] = []
    @State private var selectedProfessions: [String] = []
    @State private var selectedLocations: [String] = []
    @State private var selectedAbilities: [String] = []
    @State private var showResult: Bool = false
    @StateObject private var resultViewModel = ResultViewModel()

    private func getAllSelectedTags() -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: selectedStarLevels.filter { $0 != "全选" })

        if selectedQualifications.contains("高级资深干员") {
            tags.append("6★")
        }

        tags.append(contentsOf: selectedQualifications)
        tags.append(contentsOf: selectedProfessions)
        tags.append(contentsOf: selectedLocations)
        tags.append(contentsOf: selectedAbilities)
        return tags
    }

    private func handleStarSelection(_ item: String) {
        if item == "全选" {
            selectedStarLevels = selectedStarLevels.contains("全选") ? [] : ["全选", "5★", "4★", "3★", "2★", "1★"]
        } else {
            if selectedStarLevels.contains(item) {
                selectedStarLevels.removeAll { $0 == item || $0 == "全选" }
            } else {
                selectedStarLevels.append(item)
                let allSelected = ["5★", "4★", "3★", "2★", "1★"].allSatisfy { selectedStarLevels.contains($0) }
                if allSelected { selectedStarLevels.append("全选") }
            }
        }
        updateResultViewModel()
    }

    private func updateResultViewModel() {
        resultViewModel.updateMainViewTags(getAllSelectedTags())
    }

    private func resetAllTags() {
        selectedStarLevels = ["全选", "5★", "4★", "3★", "2★", "1★"]
        selectedQualifications = []
        selectedProfessions = []
        selectedLocations = []
        selectedAbilities = []
        updateResultViewModel()
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 30) {
                        // 标题 + 重置按钮
                        HStack {
                            Text("请选择词条")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button("重置", action: resetAllTags)
                                .foregroundColor(Color(hex: "#FF8C00"))
                        }
                        .padding(.horizontal)
                        .padding(.top)

                        // 星级选择
                        VStack(alignment: .leading, spacing: 16) {
                            Text("星级")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                                ForEach(["全选", "6★", "5★", "4★", "3★", "2★", "1★"], id: \.self) { item in
                                    Text(item)
                                        .frame(height: 44)
                                        .frame(maxWidth: .infinity)
                                        .foregroundColor(.white)
                                        .background(
                                            Capsule()
                                                .fill(selectedStarLevels.contains(item) ? Color(hex: "#FF8C00") : Color(hex: "#1E1E1E"))
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color(hex: "#FF8C00").opacity(0.4), lineWidth: selectedStarLevels.contains(item) ? 2 : 1)
                                        )
                                        .shadow(color: selectedStarLevels.contains(item) ? Color(hex: "#FF8C00").opacity(0.4) : .clear, radius: 4)
                                        .onTapGesture { handleStarSelection(item) }
                                        .opacity(item == "6★" ? 0.5 : 1.0)
                                }
                            }
                            .padding(.horizontal)
                        }

                        // 其他词条模块
                        SelectButton(
                            title: "资历",
                            items: ["高级资深干员", "资深干员", "新手", "支援机械"],
                            selectedItems: $selectedQualifications,
                            onSelectionChanged: updateResultViewModel
                        )
                        SelectButton(
                            title: "职业",
                            items: ["近卫干员", "狙击干员", "重装干员", "医疗干员", "辅助干员", "术师干员", "特种干员", "先锋干员"],
                            selectedItems: $selectedProfessions,
                            onSelectionChanged: updateResultViewModel
                        )
                        SelectButton(
                            title: "位置",
                            items: ["近战位", "远程位"],
                            selectedItems: $selectedLocations,
                            onSelectionChanged: updateResultViewModel
                        )
                        SelectButton(
                            title: "能力",
                            items: ["控场", "爆发", "治疗", "支援", "费用回复", "输出", "生存", "群攻", "防护", "减速", "削弱", "快速复活", "位移", "召唤", "元素"],
                            selectedItems: $selectedAbilities,
                            onSelectionChanged: updateResultViewModel
                        )
                    }
                    .padding(.bottom, 100)
                    .padding()
                }

                // 固定底部按钮
                VStack {
                    Spacer()
                    Button(action: {
                        updateResultViewModel()
                        showResult = true
                    }) {
                        Text("查看结果")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "#FF8C00"))
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .stroke(Color(hex: "#FF8C00"), lineWidth: 2)
                                    .background(Capsule().fill(Color(hex: "#1E1E1E")))
                            )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(Color.black)
                }
            }
            .background(Color(hex: "#0F0F0F").edgesIgnoringSafeArea(.all))
            .onAppear { updateResultViewModel() }
            .sheet(isPresented: $showResult) {
                ResultView(viewModel: resultViewModel)
            }
        }
    }
}

#Preview {
    RecruitView()
}

