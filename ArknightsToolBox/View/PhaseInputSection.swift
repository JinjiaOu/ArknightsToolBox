//
//  PhaseInputSection.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/22/25.
//

import SwiftUI

struct PhaseInputSection: View {
    let title: String
    @Binding var phase: String
    @Binding var level: Int
    var onMaxLevel: (() -> Void)? = nil
    var exp: Binding<Int>? = nil
    var onMaxExp: (() -> Void)? = nil

    @EnvironmentObject var viewModel: ExpCalculatorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)

            // 使用滑块样式
            Picker("精英阶段", selection: $phase) {
                ForEach(["精0", "精1", "精2"], id: \.self) { Text($0) }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            HStack {
                Text("当前等级")
                    .foregroundColor(.white)

                TextField("等级", value: $level, formatter: NumberFormatter())
                    .keyboardType(.numberPad)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color(hex: "#1E1E1E"))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: level) { newValue in
                        let cap = getLevelCap(phase: phase, star: viewModel.starLevel)
                        if level > cap { level = cap }
                        if level < 1 { level = 1 }
                    }

                if let max = onMaxLevel {
                    Button("最大") { max() }
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal)

            if let exp = exp {
                HStack {
                    Text("当前经验")
                        .foregroundColor(.white)

                    TextField("经验", value: exp, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color(hex: "#1E1E1E"))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: exp.wrappedValue) { newValue in
                            let maxExp = viewModel.getMaxExpForLevel(phase: phase, level: level)
                            if exp.wrappedValue >= maxExp {
                                exp.wrappedValue = max(0, maxExp - 1)
                            }
                            if exp.wrappedValue < 0 {
                                exp.wrappedValue = 0
                            }
                        }

                    if let maxExp = onMaxExp {
                        Button("最大") { maxExp() }
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    func getLevelCap(phase: String, star: Int) -> Int {
        let caps: [Int: [String: Int]] = [
            6: ["精0": 50, "精1": 80, "精2": 90],
            5: ["精0": 50, "精1": 70, "精2": 80],
            4: ["精0": 45, "精1": 60, "精2": 70],
            3: ["精0": 40, "精1": 55],
            2: ["精0": 30],
            1: ["精0": 30]
        ]
        return caps[star]?[phase] ?? 1
    }
}
