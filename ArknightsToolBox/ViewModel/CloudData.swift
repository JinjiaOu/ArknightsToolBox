//
//  CloudData.swift
//  ArknightsToolBox
//
//  面向普通用户的只读数据入口：读取云端 JSON（带本机缓存），以及"刷新数据"。
//  这里不做任何写入；写云端的同步见 ViewModel/Sync/。
//

import Foundation
import FirebaseStorage

enum CloudData {
    /// 云端 JSON 的本机缓存，存放在 Application Support，断网时仍可使用上次拿到的最新数据
    static let json: CloudJSONCache = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudData", isDirectory: true)
        return CloudJSONCache(directory: base) { path in
            try await Storage.storage().reference(withPath: path).data(maxSize: 20 * 1024 * 1024)
        }
    }()

    /// 需要保持最新的数据（App 读取的那些）
    static let datasets = [CloudPath.operators, CloudPath.modules, CloudPath.recruitment, CloudPath.materials]

    private static let seenVersionKey = "CloudDataSeenVersion"

    private struct Version: Decodable { let lastChangeCheck: String? }

    /// 云端数据最后一次同步的时间（来自 sync_state.json；断网时用本机缓存的）
    static func cloudUpdatedAt() async -> Date? {
        guard let version = await json.load(CloudPath.syncState, as: Version.self)?.value,
              let text = version.lastChangeCheck else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    struct RefreshResult {
        var cloudUpdatedAt: Date?
        var updatedFiles = 0
        var unchangedFiles = 0
        var failedFiles = 0
        var imagesInvalidated = false

        /// 全部失败：基本可以判断没有网络
        var isOffline: Bool { updatedFiles + unchangedFiles == 0 && failedFiles > 0 }
        var hasNewData: Bool { updatedFiles > 0 || imagesInvalidated }
    }

    /// 1. 读云端数据时间  2. 重新下载并缓存各个 JSON  3. 云端数据有新版本时，让图片缓存失效
    static func refreshAll() async -> RefreshResult {
        var result = RefreshResult()

        await withTaskGroup(of: CloudJSONCache.RefreshOutcome.self) { group in
            for path in datasets { group.addTask { await json.refresh(path) } }
            for await outcome in group {
                switch outcome {
                case .updated: result.updatedFiles += 1
                case .unchanged: result.unchangedFiles += 1
                case .failed: result.failedFiles += 1
                }
            }
        }

        // 版本号来自 sync_state.json，每次云端同步都会变；变了才需要重新检查图片
        let version = await json.load(CloudPath.syncState, as: Version.self)
        if let version, version.source == .cloud {
            result.cloudUpdatedAt = version.value.lastChangeCheck.flatMap { ISO8601DateFormatter().date(from: $0) }
            let seen = UserDefaults.standard.string(forKey: seenVersionKey)
            if seen != version.value.lastChangeCheck {
                CloudImageStore.shared.markAllStale()
                result.imagesInvalidated = true
                UserDefaults.standard.set(version.value.lastChangeCheck, forKey: seenVersionKey)
            }
        } else if let version {
            result.cloudUpdatedAt = version.value.lastChangeCheck.flatMap { ISO8601DateFormatter().date(from: $0) }
        }
        return result
    }
}
