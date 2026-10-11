//
//  OperatorAvatarFetcher.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/30/25.
//

import Foundation
import FirebaseStorage

@MainActor
class OperatorAvatarFetcher: ObservableObject {
    private let baseAPI = "https://prts.wiki/api.php"
    private let headers = ["User-Agent": "ArknightsAvatarUploader/Swift"]
    private let retryLimit = 2
    private let storage = Storage.storage()
    private let firebaseJSONPath = "json/all_operators.json"
    private let firebaseLogoFolder = "character_logo"

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }

    func updateAllAvatars() async {
        do {
            // Step 1: 从 Firebase 获取干员列表
            let operatorList = try await loadOperatorListFromFirebase()

            // Step 2: 从 Firebase 获取现有头像文件名
            let existingNames = try await fetchExistingAvatarNames()
            print(" Firebase 已有头像数量：\(existingNames.count)")

            // Step 3: 找出缺失的干员
            let missing = operatorList.filter { !existingNames.contains("头像_\($0).png") }
            print(" 需要上传的新头像数量：\(missing.count)\n")

            if missing.isEmpty {
                print(" 所有头像已存在，无需更新。")
                return
            }

            // Step 4: 并发上传缺失头像
            await withTaskGroup(of: Void.self) { group in
                for name in missing {
                    group.addTask {
                        await self.uploadAvatarForOperator(name: name)
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 防止过快请求
                }
            }

            print(" 新头像上传完成！")
        } catch {
            print(" 头像上传任务失败：\(error.localizedDescription)")
        }
    }

    // 从 Firebase 读取干员列表
    private func loadOperatorListFromFirebase() async throws -> [String] {
        let ref = storage.reference(withPath: firebaseJSONPath)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("all_operators_temp.json")

        try await ref.writeAsync(toFile: tempURL)
        let data = try Data(contentsOf: tempURL)
        let list = try JSONDecoder().decode([String].self, from: data)
        print(" 从 Firebase 读取干员列表，共 \(list.count) 个")
        return list
    }

    // 获取 Firebase 已有头像列表
    private func fetchExistingAvatarNames() async throws -> Set<String> {
        var result = Set<String>()
        let folderRef = storage.reference(withPath: firebaseLogoFolder)

        var pageToken: String? = nil
        repeat {
            let listResult: StorageListResult

            // 判断是否有 pageToken（第一页没有）
            if let token = pageToken {
                listResult = try await folderRef.list(maxResults: 1000, pageToken: token)
            } else {
                listResult = try await folderRef.list(maxResults: 1000)
            }

            let names = listResult.items.map { $0.name }
            result.formUnion(names)
            pageToken = listResult.pageToken  // 下一页的 token（可能为 nil）
        } while pageToken != nil

        return result
    }

    // 获取头像图片并上传至 Firebase（不保存本地）
    private func uploadAvatarForOperator(name: String) async {
        let filename = "头像_\(name).png"

        guard let imageURL = await getImageURL(filename: filename) else {
            print(" 未找到头像：\(name)")
            return
        }

        do {
            let (data, _) = try await session.data(from: imageURL)
            guard data.count > 1024 else {
                print(" 图片异常：\(name)")
                return
            }

            let ref = storage.reference(withPath: "\(firebaseLogoFolder)/\(filename)")
            _ = try await ref.putDataAsync(data)
            print(" 上传完成：\(name)")
        } catch {
            print(" 上传失败：\(name) -> \(error.localizedDescription)")
        }
    }

    // 从 PRTS 获取图片下载地址
    private func getImageURL(filename: String) async -> URL? {
        for attempt in 1...retryLimit {
            do {
                var components = URLComponents(string: baseAPI)!
                components.queryItems = [
                    URLQueryItem(name: "action", value: "query"),
                    URLQueryItem(name: "titles", value: "File:\(filename)"),
                    URLQueryItem(name: "prop", value: "imageinfo"),
                    URLQueryItem(name: "iiprop", value: "url"),
                    URLQueryItem(name: "format", value: "json")
                ]
                let (data, _) = try await session.data(from: components.url!)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let pages = (json["query"] as? [String: Any])?["pages"] as? [String: Any] {
                    for page in pages.values {
                        if let pageData = page as? [String: Any],
                           let info = pageData["imageinfo"] as? [[String: Any]],
                           let urlStr = info.first?["url"] as? String,
                           let url = URL(string: urlStr) {
                            return url
                        }
                    }
                }
            } catch {
                print("  获取失败（第 \(attempt) 次）：\(filename)")
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * attempt))
            }
        }
        return nil
    }
}
