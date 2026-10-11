//
//  HomeView.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 5/20/25.
//

import SwiftUI
import FirebaseStorage

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
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var lastUpdateTime: String = UserDefaults.standard.string(forKey: "LastUpdateTime") ?? "暂无记录"
    @State private var isRefreshing = false   // 控制整体刷新状态
    @State private var progressMessage = ""   // 刷新过程中的进度文字
    @State private var cloudUpdatedText: String?   // 云端数据最后一次同步的时间

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
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        moduleGrid

                        // 底部显示上次更新时间
                        VStack(spacing: 4) {
                            Divider().background(Color.white.opacity(0.3))
                            Text(footerText)
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.bottom, 40)
                        }
                    }
                    .padding(.top)
                }
                .background(Color(hex: "#0F0F0F").edgesIgnoringSafeArea(.all))
                .task { await loadCloudUpdatedAt() }

                // 居中浮层提示
                if showToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text(toastMessage)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 28)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.8))
                                .shadow(radius: 8)
                        )
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    .zIndex(2)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
                }


                // 右下角刷新按钮
                VStack {
                    Button {
                        Task {
                            await performRefresh()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#FF8C00"))
                                .frame(width: 60, height: 60)
                            if isRefreshing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                    }
                    .disabled(isRefreshing)
                    #if DEBUG
                    // 仅开发版：长按可执行"抓取 PRTS 并写入云端"的完整同步（需要云端写入权限）
                    .contextMenu {
                        Button("更新云端数据（仅开发）") {
                            Task { await performFullRefresh() }
                        }
                    }
                    #endif
                    .padding()
                    .shadow(color: Color(hex: "#FF8C00").opacity(0.5), radius: 8)
                }
            }
        }
    }

    // MARK: - 页脚文字
    private var footerText: String {
        if isRefreshing && !progressMessage.isEmpty { return progressMessage }
        if let cloudUpdatedText { return "云端数据更新于：\(cloudUpdatedText)" }
        return "上次刷新：\(lastUpdateTime)"
    }

    private func loadCloudUpdatedAt() async {
        if let date = await CloudData.cloudUpdatedAt() { cloudUpdatedText = Self.format(date) }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 刷新数据（只读）：重新下载云端数据并缓存到本机，图片缓存按需更新
    private func performRefresh() async {
        isRefreshing = true
        progressMessage = "正在从云端刷新数据..."

        let result = await CloudData.refreshAll()
        if let date = result.cloudUpdatedAt { cloudUpdatedText = Self.format(date) }

        if result.isOffline {
            showToastMessage("无法连接云端，继续使用本机已有的数据")
        } else {
            updateLastUpdateTime()
            let partial = result.failedFiles > 0 ? "（\(result.failedFiles) 项没有取到）" : ""
            showToastMessage(result.hasNewData ? "已更新到最新数据\(partial)" : "数据已是最新\(partial)")
        }

        progressMessage = ""
        isRefreshing = false
    }

    // MARK: - 完整同步（仅开发版）：抓取 PRTS 并写入云端
    private func performFullRefresh() async {
        isRefreshing = true
        progressMessage = "正在检查更新..."
        showToastMessage("开始检查更新...")

        do {
            let service = CloudSyncService(store: CloudStore())
            let report = try await service.run { progress in
                let text = progress.total > 0
                    ? "\(progress.stage)（\(progress.completed)/\(progress.total)）"
                    : progress.stage
                DispatchQueue.main.async { progressMessage = text }
            }

            print("===== 更新结果 =====\n\(report.text)")
            for failure in report.failures {
                print("失败 \(failure.dataset)/\(failure.name)：\(failure.message ?? "")")
            }

            updateLastUpdateTime()
            let failed = report.failures.count
            if failed > 0 {
                showToastMessage("更新完成：\(report.updatedCount) 项更新，\(failed) 项失败")
            } else if report.updatedCount == 0 {
                showToastMessage("已是最新，没有需要更新的内容")
            } else {
                showToastMessage("更新完成，共更新 \(report.updatedCount) 项")
            }
        } catch is CancellationError {
            showToastMessage("更新已取消")
        } catch {
            print("更新失败：\(error)")
            showToastMessage("更新失败：\(error.localizedDescription)")
        }

        progressMessage = ""
        isRefreshing = false
    }

    // MARK: - 显示 Toast 提示
    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showToast = false
            }
        }
    }

    // MARK: - 更新时间
    private func updateLastUpdateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = formatter.string(from: Date())
        lastUpdateTime = now
        UserDefaults.standard.set(now, forKey: "LastUpdateTime")
    }

    // MARK: - 顶部 LOGO 与标题
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#E0E0E0"))
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
    }

    // MARK: - 模块区域
    private var moduleGrid: some View {
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
}

// MARK: - 卡片样式扩展
extension View {
    func arknightsCardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#2A2A2A"))
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
