//
//  ExpResultView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/22/25.
//

import SwiftUI

struct ExpResultView: View {
    let neededExp: Int
    let neededCoin: Int
    let recommendedRecords: [String: Int]

    @Environment(\.dismiss) private var dismiss

    let imageNameMap: [String: String] = [
        "高级": "高级作战记录",
        "中级": "中级作战记录",
        "初级": "初级作战记录",
        "基础": "基础作战记录"
    ]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // 自定义标题
                Text("计算结果")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image("龙门币")
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text("所需龙门币：\(neededCoin)")
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 8) {
                        Image("经验值")
                            .resizable()
                            .frame(width: 24, height: 24)
                        Text("所需经验：\(neededExp)")
                            .foregroundColor(.white)
                    }

                    if neededExp == 0 && neededCoin == 0 {
                        Text("当前状态已达成或超过目标")
                            .foregroundColor(.green)
                            .padding(.top, 4)
                    } else {
                        Text("推荐使用的作战记录：")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.top, 4)

                        ForEach(recommendedRecords.sorted(by: { $0.value > $1.value }), id: \.key) { (type, count) in
                            HStack(spacing: 8) {
                                Image(imageNameMap[type] ?? "")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                Text("\(type)作战记录 × \(count)")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Text("关闭")
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
                .padding(.bottom)
            }
            .background(Color(hex: "#181818").edgesIgnoringSafeArea(.all))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EmptyView() // 移除系统标题
                }
            }
        }
    }
}
