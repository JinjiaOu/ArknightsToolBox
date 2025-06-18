//
//  ExpCalculatorView.swift
//  ArknightsToolBox
//

import SwiftUI

struct ExpCalculatorView: View {
    @StateObject var viewModel = ExpCalculatorViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("经验计算器")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top)
                            .padding(.horizontal)

                        // 星级滑块
                        Picker("星级", selection: $viewModel.starLevel) {
                            ForEach(1...6, id: \.self) { Text("★\($0)") }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(Color.clear)

                        Divider().background(Color.white.opacity(0.2))

                        PhaseInputSection(
                            title: "当前状态",
                            phase: $viewModel.currentPhase,
                            level: $viewModel.currentLevel,
                            onMaxLevel: viewModel.maxCurrentLevel,
                            exp: $viewModel.currentExp,
                            onMaxExp: viewModel.maxCurrentExp
                        )

                        Divider().background(Color.white.opacity(0.2))

                        PhaseInputSection(
                            title: "目标状态",
                            phase: $viewModel.targetPhase,
                            level: $viewModel.targetLevel,
                            onMaxLevel: viewModel.maxTargetLevel
                        )

                        Divider().background(Color.white.opacity(0.2))

                        VStack(alignment: .leading, spacing: 16) {
                            Text("已拥有作战记录")
                                .font(.headline)
                                .foregroundColor(.white)

                            ForEach(["高级", "中级", "初级", "基础"], id: \.self) { type in
                                HStack(spacing: 8) {
                                    Image("\(type)作战记录")
                                        .resizable()
                                        .frame(width: 24, height: 24)

                                    Text("\(type) ×")
                                        .foregroundColor(.white)
                                        .frame(width: 50, alignment: .leading)

                                    NumberInputField(
                                        title: type,
                                        number: Binding(
                                            get: { viewModel.ownedRecords[type] ?? 0 },
                                            set: { viewModel.ownedRecords[type] = $0 }
                                        ),
                                        placeholder: "输入数量"
                                    )
                                }
                            }

                            Divider().background(Color.white.opacity(0.2))

                            HStack(spacing: 8) {
                                Image("龙门币")
                                    .resizable()
                                    .frame(width: 24, height: 24)

                                Text("拥有龙门币")
                                    .foregroundColor(.white)

                                NumberInputField(
                                    title: "龙门币",
                                    number: $viewModel.ownedCoin,
                                    placeholder: "输入数量"
                                )
                            }
                        }
                        .padding(.horizontal)

                        Spacer(minLength: 100)
                    }
                    .padding(.bottom, 100)
                }
                .onTapGesture {
                    hideKeyboard() // ✅ 点击空白收起键盘
                }

                // 固定底部按钮
                VStack {
                    Spacer()
                    Button(action: {
                        hideKeyboard() // ✅ 按钮前先收起键盘
                        viewModel.calculate()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(hex: "#0F0F0F"), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("重置") {
                        hideKeyboard()
                        viewModel.reset()
                    }
                    .foregroundColor(Color(hex: "#FF8C00"))
                }
            }
            .sheet(isPresented: $viewModel.showResult) {
                ExpResultView(
                    neededExp: viewModel.neededExp,
                    neededCoin: viewModel.neededCoin,
                    recommendedRecords: viewModel.recommendedRecords
                )
                .presentationDetents([.fraction(0.5)])
            }
        }
        .environmentObject(viewModel)
    }
}


#Preview {
    ExpCalculatorView()
}
