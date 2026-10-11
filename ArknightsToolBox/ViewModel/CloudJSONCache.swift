//
//  CloudJSONCache.swift
//  ArknightsToolBox
//
//  云端 JSON 的本机缓存：优先取云端，成功就更新缓存；联网失败时用上一次成功拿到的缓存。
//  云端返回的内容必须能解码才会写入缓存，不会让一次坏数据覆盖好缓存。
//  只依赖 Foundation，取数据的方式由外部注入，便于测试。
//

import Foundation
import CryptoKit

final class CloudJSONCache {
    enum Source { case cloud, cache }
    enum RefreshOutcome { case updated, unchanged, failed }
    typealias Fetcher = (_ path: String) async throws -> Data

    private let directory: URL
    private let fetch: Fetcher

    init(directory: URL, fetch: @escaping Fetcher) {
        self.directory = directory
        self.fetch = fetch
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 云端优先；失败则用本机缓存；都没有返回 nil（调用方再退回 App 内置数据）
    func load<T: Decodable>(_ path: String, as type: T.Type) async -> (value: T, source: Source)? {
        if let data = try? await fetch(path), let value = try? JSONDecoder().decode(T.self, from: data) {
            write(data, for: path)
            return (value, .cloud)
        }
        if let data = cachedData(for: path), let value = try? JSONDecoder().decode(T.self, from: data) {
            return (value, .cache)
        }
        return nil
    }

    /// 强制从云端拉取并更新缓存。内容不是有效 JSON 时视为失败，不改动缓存。
    func refresh(_ path: String) async -> RefreshOutcome {
        guard let data = try? await fetch(path),
              (try? JSONSerialization.jsonObject(with: data)) != nil else { return .failed }
        let unchanged = cachedData(for: path) == data
        write(data, for: path)
        return unchanged ? .unchanged : .updated
    }

    func cachedData(for path: String) -> Data? {
        try? Data(contentsOf: fileURL(for: path))
    }

    private func write(_ data: Data, for path: String) {
        try? data.write(to: fileURL(for: path), options: .atomic)
    }

    private func fileURL(for path: String) -> URL {
        let name = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
}
