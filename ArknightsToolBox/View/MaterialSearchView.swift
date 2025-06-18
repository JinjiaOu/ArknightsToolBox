//
//  MaterialSearchView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

struct MaterialSearchView: View {
    @StateObject var viewModel = OperatorMaterialViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 8) {
                Text("干员材料查询")
                    .font(.largeTitle.bold())
                    .foregroundColor(Color(hex: "#FF8C00"))
                    .padding(.top)
                    .padding(.horizontal)

                HStack {
                    TextField("", text: $viewModel.operatorName)
                        .placeholder(when: viewModel.operatorName.isEmpty) {
                            Text("输入干员名称")
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                        }
                        .padding(10)
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($isInputFocused)

                    // 如果有输入内容，显示清除按钮
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


                if !viewModel.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(viewModel.suggestions, id: \.self) { name in
                            Button(action: {
                                viewModel.autoSuggestEnabled = false
                                viewModel.operatorName = name
                                viewModel.suggestions = []
                                viewModel.fetchMaterials(for: name)
                                isInputFocused = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    viewModel.autoSuggestEnabled = true
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

                if viewModel.selectedOperatorName != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let selected = viewModel.selectedOperatorName {
                                HStack(spacing: 12) {
                                    Image("头像_\(selected)")
                                        .resizable()
                                        .frame(width: 60, height: 60)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))

                                    Text(selected)
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal)
                            }

                            if !viewModel.eliteMaterials.isEmpty {
                                Text("【精英化材料】")
                                    .font(.title3.bold())
                                    .foregroundColor(Color(hex: "#FF8C00"))
                                materialBlock(viewModel.eliteMaterials)
                            }

                            if !viewModel.skillMaterials.isEmpty {
                                Text("【技能升级材料】")
                                    .font(.title3.bold())
                                    .foregroundColor(Color(hex: "#FF8C00"))
                                groupedSkillMaterialsBlock(viewModel.skillMaterials)
                            }

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
                }

                Spacer()
            }
            .background(Color(hex: "#0F0F0F").ignoresSafeArea())
        }
    }

    func materialBlock(_ data: [String: [(String, String)]]) -> some View {
        ForEach(data.sorted(by: { materialKeyPriority($0.key) < materialKeyPriority($1.key) }), id: \.key) { key, items in
            VStack(alignment: .leading, spacing: 4) {
                Text(" \(displayKeyTitle(key, skillNames: viewModel.skillNames))")
                    .font(.body.bold())
                    .foregroundColor(.white)

                ForEach(items, id: \.0) { matName, count in
                    HStack(spacing: 8) {
                        Image(matName)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text("\(matName) × \(count)")
                            .font(.callout)
                            .foregroundColor(viewModel.rarityColor(for: matName))
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func groupedSkillMaterialsBlock(_ data: [String: [(String, String)]]) -> some View {
        let grouped = Dictionary(grouping: data.sorted(by: { materialKeyPriority($0.key) < materialKeyPriority($1.key) })) { entry in
            extractSkillIndex(from: entry.key) ?? -1
        }

        ForEach(grouped.keys.sorted(), id: \.self) { index in
            if index == -1 {
                EmptyView()
            } else if let skillName = viewModel.skillNames[safe: index], let op = viewModel.selectedOperatorName {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image("技能图标_\(op)_\(skillName)")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

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
                                    Image(matName)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text("\(matName) × \(count)")
                                        .font(.callout)
                                        .foregroundColor(viewModel.rarityColor(for: matName))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    func groupedModuleMaterialsBlock(_ modules: [(String, [String: [(String, String)]])]) -> some View {
        ForEach(modules, id: \.0) { modName, stages in
            if stages.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // 模组标题 + 类型图标（自动处理希腊字母）
                    HStack(spacing: 8) {
                        if let op = viewModel.selectedOperatorName,
                           let rawType = viewModel.getModuleType(for: op, moduleName: modName) {
                            let iconName = viewModel.normalizeType(rawType)
                            Image(iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        Text("模组 “\(modName)”")
                            .font(.body.bold())
                            .foregroundColor(.white)
                    }

                    // 材料阶段
                    ForEach(stages.sorted(by: { stageKeyPriority($0.key) < stageKeyPriority($1.key) }), id: \.key) { stage, items in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stageDisplayName(stage))
                                .font(.callout.bold())
                                .foregroundColor(Color(hex: "#FF8C00"))

                            ForEach(items, id: \.0) { matName, count in
                                HStack(spacing: 8) {
                                    Image(matName)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text("\(matName) × \(count)")
                                        .font(.callout)
                                        .foregroundColor(viewModel.rarityColor(for: matName))
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func extractSkillIndex(from key: String) -> Int? {
        switch key.prefix(1) {
        case "一": return 0
        case "二": return 1
        case "三": return 2
        default: return nil
        }
    }

    func materialKeyPriority(_ key: String) -> Int {
        if key == "精1" { return 1 }
        if key == "精2" { return 2 }

        let mapping = ["一": 1, "二": 2, "三": 3]
        let prefix = String(key.prefix(1))
        let suffix = String(key.dropFirst())

        if let base = mapping[prefix], let level = Int(suffix) {
            return 100 + base * 10 + level
        }

        if let n = Int(key) {
            return 10 + n
        }

        return 9999
    }

    func stageKeyPriority(_ key: String) -> Int {
        switch key {
        case "材料消耗": return 1
        case "材料消耗2": return 2
        case "材料消耗3": return 3
        default: return 999
        }
    }

    func displayKeyTitle(_ key: String, skillNames: [String]) -> String {
        if key == "精1" { return "精1" }
        if key == "精2" { return "精2" }
        if let n = Int(key) { return "等级 \(n)" }

        if key.hasPrefix("一") {
            return "\(skillNames[safe: 0] ?? "第1技能") \(viewModel.specializationLevelText(for: key.dropFirst()))"
        }
        if key.hasPrefix("二") {
            return "\(skillNames[safe: 1] ?? "第2技能") \(viewModel.specializationLevelText(for: key.dropFirst()))"
        }
        if key.hasPrefix("三") {
            return "\(skillNames[safe: 2] ?? "第3技能") \(viewModel.specializationLevelText(for: key.dropFirst()))"
        }

        return key
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
