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

    private lazy var directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

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
            if let modified, Date().timeIntervalSince(modified) < freshInterval {
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
