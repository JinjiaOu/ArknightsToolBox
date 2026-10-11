//
//  MaterialSearchView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI
import FirebaseStorage

struct MaterialSearchView: View {
    @StateObject var viewModel = OperatorMaterialViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 8) {
                // 顶部标题
                Text("干员材料查询")
                    .font(.largeTitle.bold())
                    .foregroundColor(Color(hex: "#FF8C00"))
                    .padding(.top)
                    .padding(.horizontal)

                // 🔍 搜索输入框
                HStack {
                    TextField("", text: $viewModel.operatorName)
                        .placeholder(when: viewModel.operatorName.isEmpty) {
                            Text("输入干员名称")
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(10)
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($isInputFocused)

                    if !viewModel.operatorName.isEmpty {
                        Button(action: {
                            viewModel.operatorName = ""
                            viewModel.suggestions = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.trailing, 12)
                    }
                }
                .background(Color(hex: "#1E1E1E"))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .padding(.horizontal)

                // 📜 搜索建议
                if !viewModel.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(viewModel.suggestions, id: \.self) { name in
                            Button(action: {
                                viewModel.autoSuggestEnabled = false
                                viewModel.operatorName = name
                                viewModel.suggestions = []
                                isLoading = true
                                viewModel.fetchMaterials(for: name)
                                isInputFocused = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    viewModel.autoSuggestEnabled = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    isLoading = false
                                }
                            }) {
                                HStack {
                                    Text(name)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(hex: "#2A2A2A"))
                            }
                            Divider().background(Color.gray)
                        }
                    }
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // 📦 加载中状态
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#FF8C00")))
                                .scaleEffect(1.6)
                            Text("加载中...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .padding(30)
                        .background(Color(hex: "#1A1A1A").opacity(0.9))
                        .cornerRadius(16)
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }


                // 📦 查询结果
                if let selected = viewModel.selectedOperatorName, !isLoading {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // 🧍‍♀️ 头像区域
                            HStack(spacing: 12) {
                                FirebaseAsyncImage(
                                    path: "character_logo/头像_\(selected).png",
                                    fallback: "头像_\(selected)",
                                    width: 60,
                                    height: 60,
                                    cornerRadius: 30
                                )
                                .id("avatar-\(selected)") // 强制刷新
                                .transition(.opacity.combined(with: .scale))
                                .animation(.easeInOut(duration: 0.25), value: selected)
                                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

                                Text(selected)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal)

                            // 精英化材料
                            if !viewModel.eliteMaterials.isEmpty {
                                Text("【精英化材料】")
                                    .font(.title3.bold())
                                    .foregroundColor(Color(hex: "#FF8C00"))
                                materialBlock(viewModel.eliteMaterials)
                            }

                            // 技能升级材料
                            if !viewModel.skillMaterials.isEmpty {
                                Text("【技能升级材料】")
                                    .font(.title3.bold())
                                    .foregroundColor(Color(hex: "#FF8C00"))
                                groupedSkillMaterialsBlock(viewModel.skillMaterials)
                            }

                            // 模组材料
                            if !viewModel.moduleMaterials.isEmpty {
                                Text("【模组材料】")
                                    .font(.title3.bold())
                                    .foregroundColor(Color(hex: "#FF8C00"))
                                groupedModuleMaterialsBlock(viewModel.moduleMaterials)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#1A1A1A"))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    .id(selected) // 每次切换干员时完全刷新 ScrollView
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: selected)
                }

                Spacer()
            }
            .background(Color(hex: "#0F0F0F").ignoresSafeArea())
        }
    }

    // MARK: - 普通材料（本地图）
    func materialBlock(_ data: [String: [(String, String)]]) -> some View {
        ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { key, items in
            VStack(alignment: .leading, spacing: 4) {
                Text(" \(key)")
                    .font(.body.bold())
                    .foregroundColor(.white)

                ForEach(items, id: \.0) { matName, count in
                    HStack(spacing: 8) {
                        MaterialIconView(name: matName)
                        Text("\(matName) × \(count)")
                            .font(.callout)
                            .foregroundColor(viewModel.rarityColor(for: matName))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 技能图标（Firebase）
    @ViewBuilder
    func groupedSkillMaterialsBlock(_ data: [String: [(String, String)]]) -> some View {
        let grouped = Dictionary(grouping: data) { entry in
            extractSkillIndex(from: entry.key) ?? -1
        }

        ForEach(grouped.keys.sorted(), id: \.self) { index in
            if index != -1,
               let skillName = viewModel.skillNames[safe: index],
               let op = viewModel.selectedOperatorName {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        FirebaseAsyncImage(
                            paths: CloudPath.skillIconCandidates(operatorName: op, skill: skillName)
                                .map { "\(CloudPath.skillIconFolder)/\($0)" },
                            fallback: "技能图标_\(op)_\(skillName)",
                            width: 32,
                            height: 32,
                            cornerRadius: 6
                        )
                        .id("skill-\(op)-\(skillName)") // 强制刷新技能图
                        Text(skillName)
                            .font(.body.bold())
                            .foregroundColor(.white)
                    }

                    ForEach(grouped[index] ?? [], id: \.key) { key, items in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.specializationLevelText(for: key.dropFirst()))
                                .font(.callout.bold())
                                .foregroundColor(Color(hex: "#FF8C00"))
                            ForEach(items, id: \.0) { matName, count in
                                HStack(spacing: 8) {
                                    MaterialIconView(name: matName)
                                    Text("\(matName) × \(count)")
                                        .font(.callout)
                                        .foregroundColor(viewModel.rarityColor(for: matName))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - 模组图标（Firebase）
    @ViewBuilder
    func groupedModuleMaterialsBlock(_ modules: [(String, [String: [(String, String)]])]) -> some View {
        ForEach(modules, id: \.0) { modName, stages in
            if !stages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let op = viewModel.selectedOperatorName,
                           let rawType = viewModel.getModuleType(for: op, moduleName: modName) {

                            let iconName = viewModel.normalizeType(rawType)
                            let fullPath = "module_icons/\(iconName).png"
                            let _ = print("🧩 模组图标检查：干员=\(op)，模组=\(modName)，rawType=\(rawType)，iconName=\(iconName)，Firebase路径=\(fullPath)")

                            FirebaseAsyncImage(
                                path: fullPath,
                                fallback: iconName,
                                width: 50,
                                height: 50,
                                cornerRadius: 6
                            )
                            .id("module-\(op)-\(modName)")
                        }


                        Text("模组 “\(modName)”")
                            .font(.body.bold())
                            .foregroundColor(.white)
                    }

                    ForEach(stages.sorted(by: { $0.key < $1.key }), id: \.key) { stage, items in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stageDisplayName(stage))
                                .font(.callout.bold())
                                .foregroundColor(Color(hex: "#FF8C00"))
                            ForEach(items, id: \.0) { matName, count in
                                HStack(spacing: 8) {
                                    MaterialIconView(name: matName)
                                    Text("\(matName) × \(count)")
                                        .font(.callout)
                                        .foregroundColor(viewModel.rarityColor(for: matName))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - 工具函数
    func extractSkillIndex(from key: String) -> Int? {
        switch key.prefix(1) {
        case "一": return 0
        case "二": return 1
        case "三": return 2
        default: return nil
        }
    }

    func stageDisplayName(_ key: String) -> String {
        switch key {
        case "材料消耗": return "一模"
        case "材料消耗2": return "二模"
        case "材料消耗3": return "三模"
        default: return key
        }
    }
}

#Preview {
    MaterialSearchView()
}
