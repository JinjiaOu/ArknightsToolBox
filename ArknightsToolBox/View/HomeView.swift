//
//  HomeView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI

// MARK: - 模块数据结构
struct ModuleItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let destination: AnyView
    let backgroundColor: Color
}

// MARK: - 主视图
struct HomeView: View {
    let modules: [ModuleItem] = [
        ModuleItem(
            title: "公开招募模拟器",
            icon: "tag.fill",
            destination: AnyView(RecruitView()),
            backgroundColor: Color(hex: "#FF8C00")
        ),
        ModuleItem(
            title: "干员材料检索",
            icon: "person.text.rectangle",
            destination: AnyView(MaterialSearchView()),
            backgroundColor: Color(hex: "#FF8C00")
        ),
        ModuleItem(
            title: "干员经验计算",
            icon: "plus.forwardslash.minus",
            destination: AnyView(ExpCalculatorView()),
            backgroundColor: Color(hex: "#FF8C00")
        )
    ]

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // 顶部 LOGO + 标题
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "#E0E0E0")) // 灰色背景
                                .frame(width: 50, height: 50)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color(hex: "#FF8C00").opacity(0.4), lineWidth: 1.5)
                                )
                                .shadow(color: Color(hex: "#FF8C00").opacity(0.25), radius: 3)

                            Image("logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                        }


                        Text("明日方舟工具箱")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // 模块卡片区域
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(modules) { module in
                            NavigationLink(destination: module.destination) {
                                VStack(spacing: 12) {
                                    Image(systemName: module.icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                        .foregroundColor(.white)

                                    Text(module.title)
                                        .foregroundColor(.white)
                                        .font(.subheadline.bold())
                                        .multilineTextAlignment(.center)
                                }
                                .arknightsCardStyle()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .background(Color(hex: "#0F0F0F").edgesIgnoringSafeArea(.all))
        }
    }
}

// MARK: - 卡片样式扩展
extension View {
    func arknightsCardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#2A2A2A")) // ⬅️ 调亮卡片背景
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "#FF8C00").opacity(0.4), lineWidth: 1.5)
                    )
            )
            .shadow(color: Color(hex: "#FF8C00").opacity(0.25), radius: 5)
    }
}

#Preview {
    HomeView()
}
