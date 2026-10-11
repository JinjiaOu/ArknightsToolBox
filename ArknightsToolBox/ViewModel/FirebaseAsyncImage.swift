//
//  FirebaseAsyncImage.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/30/25.
//

import SwiftUI
import FirebaseStorage

struct FirebaseAsyncImage: View {
    /// 按顺序尝试的云端路径；第一个成功的会被显示
    let paths: [String]
    let fallback: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    /// 为 true 时，云端图片加载期间先显示本地备用图，而不是转圈（用于一屏有很多小图标的列表）
    let showsFallbackWhileLoading: Bool

    init(path: String, fallback: String, width: CGFloat, height: CGFloat, cornerRadius: CGFloat,
         showsFallbackWhileLoading: Bool = false) {
        self.init(paths: [path], fallback: fallback, width: width, height: height,
                  cornerRadius: cornerRadius, showsFallbackWhileLoading: showsFallbackWhileLoading)
    }

    init(paths: [String], fallback: String, width: CGFloat, height: CGFloat, cornerRadius: CGFloat,
         showsFallbackWhileLoading: Bool = false) {
        self.paths = paths
        self.fallback = fallback
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.showsFallbackWhileLoading = showsFallbackWhileLoading
        // 内存里已有就直接显示，避免滚动或重建视图时闪烁
        _uiImage = State(initialValue: CloudImageStore.shared.memoryImage(paths: paths))
    }

    @State private var uiImage: UIImage? = nil
    @State private var isLoading = false
    @State private var currentRequestID = UUID() // 用于标识当前加载任务

    var body: some View {
        Group {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else if isLoading && !showsFallbackWhileLoading {
                ProgressView()
                    .frame(width: width, height: height)
            } else {
                Image(fallback)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear(perform: loadImage)
        .onChange(of: paths) { _ in
            loadImage() // 当路径变化时重新加载
        }
    }

    private func loadImage() {
        // 内存里已有：直接用
        if let cached = CloudImageStore.shared.memoryImage(paths: paths) {
            uiImage = cached
            isLoading = false
            return
        }

        // 生成新的请求 ID（旧请求自动失效）
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true
        uiImage = nil

        let candidates = paths
        Task {
            let loaded = await CloudImageStore.shared.image(paths: candidates)

            await MainActor.run {
                // 如果不是当前请求，直接丢弃结果
                guard self.currentRequestID == requestID else { return }

                if let loaded {
                    withAnimation(.easeInOut(duration: 0.25)) { self.uiImage = loaded }
                } else {
                    print("Firebase image load failed for \(candidates)")
                }
                self.isLoading = false
            }
        }
    }
}

/// 材料图标：云端优先，本地 Assets 作为加载期间和失败时的备用
struct MaterialIconView: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        FirebaseAsyncImage(
            path: "\(CloudPath.materialIconFolder)/\(CloudPath.materialIconFile(name))",
            fallback: name,
            width: size,
            height: size,
            cornerRadius: 4,
            showsFallbackWhileLoading: true
        )
    }
}
