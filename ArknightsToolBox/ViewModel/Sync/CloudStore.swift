//
//  CloudStore.swift
//  ArknightsToolBox
//
//  Firebase Storage 的读写封装：JSON 读取/覆盖、文件列表、带校验的 PNG 上传。
//

import Foundation
import FirebaseStorage

enum CloudStoreError: LocalizedError {
    case invalidImage(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage(let name): return "图片无效或已损坏：\(name)"
        }
    }
}

struct CloudStore: CloudStoring {
    private let storage = Storage.storage()

    /// 读取 JSON。文件不存在时返回 nil；其他错误（网络、解码）向上抛出，避免误当作"没有旧数据"而覆盖
    func readJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T? {
        do {
            let data = try await storage.reference(withPath: path).data(maxSize: 20 * 1024 * 1024)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as NSError where Self.isNotFound(error) {
            return nil
        }
    }

    func writeJSON<T: Encodable>(_ value: T, to path: String) async throws {
        // 覆盖前把旧文件复制到 json_backup/，只保留上一个版本，便于回滚
        let reference = storage.reference(withPath: path)
        do {
            let old = try await reference.data(maxSize: 20 * 1024 * 1024)
            let backup = StorageMetadata()
            backup.contentType = "application/json"
            _ = try await storage.reference(withPath: "json_backup/\((path as NSString).lastPathComponent)")
                .putDataAsync(old, metadata: backup)
        } catch let error as NSError where Self.isNotFound(error) {
            // 首次写入，没有旧文件
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)

        let metadata = StorageMetadata()
        metadata.contentType = "application/json"
        _ = try await reference.putDataAsync(data, metadata: metadata)
    }

    /// 文件夹内已有的文件名
    func listFileNames(in folder: String) async throws -> Set<String> {
        var names = Set<String>()
        let reference = storage.reference(withPath: folder)
        var pageToken: String?
        repeat {
            let result = pageToken == nil
                ? try await reference.list(maxResults: 1000)
                : try await reference.list(maxResults: 1000, pageToken: pageToken!)
            names.formUnion(result.items.map(\.name))
            pageToken = result.pageToken
        } while pageToken != nil
        return names
    }

    /// 校验 PNG 后上传；校验失败时不写入
    func uploadPNG(_ data: Data, to path: String) async throws {
        guard PNGValidator.isValid(data) else {
            throw CloudStoreError.invalidImage((path as NSString).lastPathComponent)
        }
        let metadata = StorageMetadata()
        metadata.contentType = "image/png"
        _ = try await storage.reference(withPath: path).putDataAsync(data, metadata: metadata)
    }

    private static func isNotFound(_ error: NSError) -> Bool {
        error.domain == StorageErrorDomain && error.code == StorageErrorCode.objectNotFound.rawValue
    }
}
