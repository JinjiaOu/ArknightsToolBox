//
//  ModuleIconFetcher.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/30/25.
//

import Foundation
import FirebaseStorage

@MainActor
class ModuleIconFetcher: ObservableObject {
    private let baseURL = "https://prts.wiki/api.php"
    private let storage = Storage.storage()
    private let moduleIconPath = "module_icons"
    private let retryLimit = 2

    @Published var statusMessage = ""

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "ArknightsModuleIconFetcher/Swift"]
        return URLSession(configuration: config)
    }

    // MARK: - 主更新入口
    func updateAllModuleIcons() async {
        statusMessage = "正在检查并上传模组类型图标..."
        print("开始同步模组类型图标...")

        do {
            // Step 1: 获取 Firebase 已有文件
            let existing = try await fetchExistingIcons()
            print("Firebase 已有 \(existing.count) 个模组小图")

            // Step 2: 从 PRTS 获取所有模组小图文件名
            let images = await fetchAllSmallModuleIcons()
            print("从 PRTS 获取到 \(images.count) 个图标")

            // Step 3: 转换 Firebase 文件名为 PRTS 命名形式进行对比
            let normalizedExisting = Set(existing.map {
                "模组类型_\($0.replacingOccurrences(of: ".png", with: ""))_小图.png"
            })
            let newImages = images.filter { !normalizedExisting.contains($0) }

            let skippedCount = images.count - newImages.count
            print("已存在：\(skippedCount)，🆕 需要上传的新图标：\(newImages.count) 个")

            if newImages.isEmpty {
                statusMessage = "模组小图已是最新。"
                print("无需更新，全部文件已存在。")
                return
            }

            // Step 4: 下载 + 上传新图标
            var uploadedCount = 0
            for (i, filename) in newImages.enumerated() {
                print("[进度] \(i + 1)/\(newImages.count)：\(filename)")
                if let url = await getImageURL(filename: filename) {
                    do {
                        let (data, _) = try await session.data(from: url)
                        guard data.count > 1024 else {
                            print("图片过小或无效：\(filename)")
                            continue
                        }

                        let saveName = filename
                            .replacingOccurrences(of: "模组类型_", with: "")
                            .replacingOccurrences(of: "_小图.png", with: "")
                            + ".png"

                        let ref = storage.reference(withPath: "\(moduleIconPath)/\(saveName)")
                        _ = try await ref.putDataAsync(data)
                        uploadedCount += 1
                        print("上传完成：\(saveName)")
                    } catch {
                        print("上传失败：\(filename) -> \(error.localizedDescription)")
                    }
                } else {
                    print("未找到图片链接：\(filename)")
                }

                // 请求间隔，防止封禁
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            // Step 5: 汇总结果
            statusMessage = "模组小图更新完成，新增 \(uploadedCount) 个，跳过 \(skippedCount) 个"
            print(statusMessage)

        } catch {
            statusMessage = "模组小图更新失败：\(error.localizedDescription)"
            print(statusMessage)
        }
    }

    // MARK: - 从 Firebase 获取已有图标
    private func fetchExistingIcons() async throws -> Set<String> {
        var result = Set<String>()
        let folderRef = storage.reference(withPath: moduleIconPath)
        var pageToken: String? = nil

        repeat {
            let listResult: StorageListResult
            if let token = pageToken {
                listResult = try await folderRef.list(maxResults: 1000, pageToken: token)
            } else {
                listResult = try await folderRef.list(maxResults: 1000)
            }
            let names = listResult.items.map { $0.name }
            result.formUnion(names)
            pageToken = listResult.pageToken
        } while pageToken != nil

        return result
    }

    // MARK: - 从 PRTS 获取所有模组小图文件名
    private func fetchAllSmallModuleIcons() async -> [String] {
        var allImages: [String] = []
        var aicontinue: String? = nil

        print("正在抓取 PRTS 模组类型小图...")

        repeat {
            var components = URLComponents(string: baseURL)!
            components.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "list", value: "allimages"),
                URLQueryItem(name: "aiprefix", value: "模组类型_"),
                URLQueryItem(name: "ailimit", value: "max"),
                URLQueryItem(name: "format", value: "json")
            ]
            if let cont = aicontinue {
                components.queryItems?.append(URLQueryItem(name: "aicontinue", value: cont))
            }

            do {
                let (data, _) = try await session.data(from: components.url!)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let query = json["query"] as? [String: Any],
                   let images = query["allimages"] as? [[String: Any]] {
                    for img in images {
                        if let name = img["name"] as? String, name.hasSuffix("_小图.png") {
                            allImages.append(name)
                        }
                    }
                    aicontinue = (json["continue"] as? [String: Any])?["aicontinue"] as? String
                } else {
                    break
                }
            } catch {
                print("抓取失败：\(error.localizedDescription)")
                break
            }
        } while aicontinue != nil

        return allImages
    }

    // MARK: - 获取图片真实 URL
    private func getImageURL(filename: String) async -> URL? {
        for attempt in 1...retryLimit {
            do {
                var components = URLComponents(string: baseURL)!
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
                        if let pageDict = page as? [String: Any],
                           let info = pageDict["imageinfo"] as? [[String: Any]],
                           let urlStr = info.first?["url"] as? String,
                           let url = URL(string: urlStr) {
                            return url
                        }
                    }
                }
            } catch {
                print("获取失败（第 \(attempt) 次）：\(filename)")
                try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 * attempt))
            }
        }
        return nil
    }
}
