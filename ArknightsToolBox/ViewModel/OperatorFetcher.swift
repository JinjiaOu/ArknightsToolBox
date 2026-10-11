//
//  OperatorFetcher.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/29/25.
//

import Foundation
import FirebaseStorage

@MainActor
class OperatorFetcher: ObservableObject {
    @Published var isLoading = false
    @Published var statusMessage = ""

    private let baseURL = "https://prts.wiki/api.php"
    private let excludeOperators: Set<String> = [
        "echanist(卫戍协议)", "Misery(卫戍协议)", "Pith", "Pith(卫戍协议)", "Raidian(卫戍协议)",
        "Sharp", "Sharp(卫戍协议)", "Stormeye", "Stormeye(卫戍协议)", "Touch", "Touch(卫戍协议)",
        "暮落(集成战略)", "郁金香", "郁金香(卫戍协议)",
        "预备干员-先锋(卫戍协议)", "预备干员-医疗(卫戍协议)", "预备干员-后勤", "预备干员-术师",
        "预备干员-术师(卫戍协议)", "预备干员-特种(卫戍协议)", "预备干员-狙击", "预备干员-狙击(卫戍协议)",
        "预备干员-辅助(卫戍协议)", "预备干员-近卫(卫戍协议)", "预备干员-近战", "预备干员-重装",
        "预备干员-重装(卫戍协议)", "Mechanist(卫戍协议)", "领主·Sharp", "盟约·辅助干员"
    ]

    private let storage = Storage.storage()
    private let storagePath = "json/all_operators.json"

    func refreshData() async {
        isLoading = true
        statusMessage = "正在获取干员数据..."

        let result = await fetchAllOperators()
        guard !result.isEmpty else {
            statusMessage = "获取失败或无数据"
            isLoading = false
            return
        }

        do {
            let data = try JSONEncoder().encode(result)
            let localURL = try saveToTempFile(data: data)
            try await uploadToFirebase(localURL: localURL)
            statusMessage = "上传成功，共 \(result.count) 位干员"
        } catch {
            statusMessage = "错误: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func fetchAllOperators() async -> [String] {
        var allOperators: [String] = []
        var cmcontinue: String? = nil

        repeat {
            var components = URLComponents(string: baseURL)!
            components.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "list", value: "categorymembers"),
                URLQueryItem(name: "cmtitle", value: "Category:干员"),
                URLQueryItem(name: "cmlimit", value: "max"),
                URLQueryItem(name: "format", value: "json")
            ]
            if let cont = cmcontinue {
                components.queryItems?.append(URLQueryItem(name: "cmcontinue", value: cont))
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let query = json["query"] as? [String: Any],
                   let members = query["categorymembers"] as? [[String: Any]] {

                    let names = members.compactMap { $0["title"] as? String }
                        .filter { !excludeOperators.contains($0) }

                    allOperators.append(contentsOf: names)

                    cmcontinue = (json["continue"] as? [String: Any])?["cmcontinue"] as? String
                    if cmcontinue != nil { try await Task.sleep(nanoseconds: 500_000_000) } // 0.5s
                } else {
                    cmcontinue = nil
                }
            } catch {
                print("获取失败: \(error.localizedDescription)")
                return []
            }
        } while cmcontinue != nil

        return Array(Set(allOperators)).sorted()
    }

    private func saveToTempFile(data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("all_operators.json")
        try data.write(to: fileURL)
        return fileURL
    }

    private func uploadToFirebase(localURL: URL) async throws {
        let ref = storage.reference(withPath: storagePath)
        _ = try await ref.putFileAsync(from: localURL)
    }
}

