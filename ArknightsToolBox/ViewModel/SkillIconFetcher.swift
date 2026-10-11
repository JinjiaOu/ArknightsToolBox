//
//  SkillIconFetcher.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/30/25.
//

import Foundation
import FirebaseStorage

@MainActor
class SkillIconFetcher: ObservableObject {
    private let baseAPI = "https://prts.wiki/api.php"
    private let headers = ["User-Agent": "ArknightsSkillIconFetcher/Swift"]
    private let storage = Storage.storage()
    private let retryLimit = 2
    private let firebaseSkillFolder = "skill_icons"
    private let firebaseSkillListPath = "json/skills.json"

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        config.timeoutIntervalForRequest = 40
        return URLSession(configuration: config)
    }

    func updateAllSkillIcons() async {
        do {
            let skillList = try await loadSkillListFromFirebase()
            print(" 从 Firebase 读取技能列表，共 \(skillList.count) 位干员")

            let existingFiles = try await fetchExistingSkillIcons()
            print(" Firebase 已有技能图标：\(existingFiles.count) 个")

            var expectedFiles: [String] = []
            for (opName, skills) in skillList {
                for skill in skills {
                    expectedFiles.append("技能图标_\(opName)_\(skill).png")
                }
            }

            let missingFiles = expectedFiles.filter { !existingFiles.contains($0) }

            guard !missingFiles.isEmpty else {
                print("所有技能图标已是最新，无需更新。")
                return
            }

            print("检测到 \(missingFiles.count) 个缺失技能图标，开始下载...\n")

            let startTime = Date()
            let maxConcurrent = 6

            try await withThrowingTaskGroup(of: Void.self) { group in
                var activeCount = 0
                var iterator = missingFiles.makeIterator()

                func addNext() {
                    if activeCount < maxConcurrent, let fileName = iterator.next() {
                        activeCount += 1
                        group.addTask {
                            await self.downloadAndUploadSkillIcon(fileName: fileName)
                        }
                    }
                }

                // 初始启动
                for _ in 0..<maxConcurrent { addNext() }

                // 每完成一个，补充下一个
                while let _ = try await group.next() {
                    activeCount -= 1
                    addNext()
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            print("\n技能图标同步完成，用时 \(String(format: "%.1f", duration)) 秒\n")

        } catch {
            print(" 技能图标更新失败：\(error.localizedDescription)")
        }
    }


    // MARK: - 下载并上传单个技能图标
    private func downloadAndUploadSkillIcon(fileName: String) async {
        let trimmed = fileName
            .replacingOccurrences(of: "技能图标_", with: "")
            .replacingOccurrences(of: ".png", with: "")

        let parts = trimmed.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }

        let operatorName = parts[0]
        let skillName = parts[1]

        // 尝试多种 Wiki 文件名格式
        let possibleNames = [
            "技能_\(operatorName)_\(skillName).png",
            "技能_\(skillName).png",
            "\(skillName).png"
        ]

        var imageURL: URL? = nil
        for name in possibleNames {
            if let url = await getImageURL(filename: name) {
                imageURL = url
                break
            }
        }

        guard let validURL = imageURL else {
            print("[跳过] 未找到图片链接：\(fileName)")
            return
        }

        do {
            let (data, _) = try await session.data(from: validURL)
            guard data.count > 500 else {
                print("图片无效或过小：\(fileName)")
                return
            }

            let ref = storage.reference(withPath: "\(firebaseSkillFolder)/\(fileName)")
            _ = try await ref.putDataAsync(data)
            print("上传完成：\(fileName)")
        } catch {
            print("上传失败：\(fileName) -> \(error.localizedDescription)")
        }
    }

    // MARK: - 从 Firebase 读取 skills.json
    private func loadSkillListFromFirebase() async throws -> [String: [String]] {
        let ref = storage.reference(withPath: firebaseSkillListPath)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("skills_temp.json")
        try await ref.writeAsync(toFile: tempURL)
        let data = try Data(contentsOf: tempURL)
        return try JSONDecoder().decode([String: [String]].self, from: data)
    }

    // MARK: - 获取 Firebase 已有技能图标
    private func fetchExistingSkillIcons() async throws -> Set<String> {
        var result = Set<String>()
        let folderRef = storage.reference(withPath: firebaseSkillFolder)
        var pageToken: String? = nil

        repeat {
            let listResult: StorageListResult
            if let token = pageToken {
                listResult = try await folderRef.list(maxResults: 1000, pageToken: token)
            } else {
                listResult = try await folderRef.list(maxResults: 1000)
            }
            result.formUnion(listResult.items.map { $0.name })
            pageToken = listResult.pageToken
        } while pageToken != nil

        return result
    }

    // MARK: - 获取图片真实 URL
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
                print("获取失败（第 \(attempt) 次）：\(filename)")
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * attempt))
            }
        }
        return nil
    }
}
