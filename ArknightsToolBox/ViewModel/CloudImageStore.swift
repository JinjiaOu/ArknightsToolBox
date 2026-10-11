//
//  CloudImageStore.swift
//  ArknightsToolBox
//
//  云端图片的缓存：内存 → 磁盘（7 天内直接使用）→ Firebase。
//  网络失败时退回过期的磁盘缓存，所以看过一次的图片离线也能显示。
//  找不到的路径会短时间记住，避免同一个列表反复请求不存在的图片。
//

import UIKit
import CryptoKit
import FirebaseStorage

final class CloudImageStore {
    static let shared = CloudImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var misses: [String: Date] = [:]

    private let freshInterval: TimeInterval = 7 * 86_400
    private let missInterval: TimeInterval = 10 * 60
    private let maxSize: Int64 = 2 * 1024 * 1024

    /// 必须在 init 里初始化：lazy var 在多线程同时首次访问时不是线程安全的，
    /// 材料页一次并发加载几十个图标，会因此崩溃
    private let directory: URL

    private init() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directory = url
    }

    private let staleKey = "CloudImageStaleBefore"

    /// 把现有缓存全部标记为过期：下次显示时重新向云端取，取不到就继续用旧图。
    /// 不直接删除，所以刷新后断网也不会丢图。
    func markAllStale() {
        memory.removeAllObjects()
        lock.lock(); misses.removeAll(); lock.unlock()
        UserDefaults.standard.set(Date(), forKey: staleKey)
    }

    /// 同步读内存缓存，用于视图首次渲染时避免闪烁
    func memoryImage(paths: [String]) -> UIImage? {
        for path in paths {
            if let image = memory.object(forKey: path as NSString) { return image }
        }
        return nil
    }

    /// 按顺序尝试多个路径，返回第一个能取到的图片
    func image(paths: [String]) async -> UIImage? {
        for path in paths {
            if let image = await image(path: path) { return image }
        }
        return nil
    }

    func image(path: String) async -> UIImage? {
        let key = path as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if recentlyMissed(path) { return nil }

        // 磁盘缓存
        let file = fileURL(for: path)
        var stale: UIImage?
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
            let staleBefore = UserDefaults.standard.object(forKey: staleKey) as? Date ?? .distantPast
            if let modified, modified > staleBefore, Date().timeIntervalSince(modified) < freshInterval {
                memory.setObject(image, forKey: key)
                return image
            }
            stale = image
        }

        // 网络
        do {
            let data = try await Storage.storage().reference(withPath: path).data(maxSize: maxSize)
            guard let image = UIImage(data: data) else { return stale }
            try? data.write(to: file, options: .atomic)
            memory.setObject(image, forKey: key)
            return image
        } catch {
            if let stale {
                memory.setObject(stale, forKey: key)
                return stale
            }
            if (error as NSError).code == StorageErrorCode.objectNotFound.rawValue { recordMiss(path) }
            return nil
        }
    }

    private func fileURL(for path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }

    private func recentlyMissed(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let date = misses[path] else { return false }
        if Date().timeIntervalSince(date) < missInterval { return true }
        misses[path] = nil
        return false
    }

    private func recordMiss(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        misses[path] = Date()
    }
}
