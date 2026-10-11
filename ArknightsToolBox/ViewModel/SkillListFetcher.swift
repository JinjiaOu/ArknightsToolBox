//
//  SkillListFetcher.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/29/25.
//

import Foundation
import FirebaseStorage

@MainActor
class SkillListFetcher: ObservableObject {
    private let baseURL = "https://prts.wiki/api.php"
    private let storage = Storage.storage()
    private let skillJsonPath = "json/skills.json"

    @Published var statusMessage = ""

    func refreshSkillList() async {
        statusMessage = "正在检查干员技能列表更新..."

        // Step 1 获取最新干员列表
        guard let operatorList = await fetchOperatorList() else {
            statusMessage = "无法读取干员列表"
            return
        }
        print("干员总数：\(operatorList.count)")

        // Step 2 读取旧 skills.json
        var existingSkills: [String: [String]] = [:]
        if let oldData = await fetchOldSkillList() {
            existingSkills = oldData
            print("已有技能数据：\(existingSkills.count) 位干员")
        } else {
            print("未检测到旧技能数据，将重新创建技能列表。")
        }

        // Step 3 找出新干员
        let oldNames = Set(existingSkills.keys)
        let allNames = Set(operatorList)
        let newOperators = Array(allNames.subtracting(oldNames)).sorted()

        if newOperators.isEmpty {
            print("没有新干员需要更新技能列表。")
            statusMessage = "技能列表已是最新。"
            return
        }

        print("检测到 \(newOperators.count) 个新干员：\(newOperators.joined(separator: ", "))")

        // Step 4 跳过已知无技能干员
        let skipOperators: Set<String> = [
            "12F", "CONFESS-47", "Castle-3", "Friston-3", "Lancet-2", "PhonoR-0",
            "THRM-EX", "U-Official", "夜刀", "巡林者", "杜林", "正义骑士号",
            "泰拉大陆调查团", "黑角"
        ]

        var newSkillData: [String: [String]] = [:]
        var processedCount = 0
        let totalCount = newOperators.count

        // Step 5 抓取新干员技能
        for name in newOperators {
            processedCount += 1

            if skipOperators.contains(name) {
                print("跳过无技能干员：\(name) (\(processedCount)/\(totalCount))")
                continue
            }

            let images = await getEmbeddedImages(for: name)
            let skillImages = images.filter { $0.hasPrefix("技能_") }
            let skillNames = skillImages.map {
                $0.replacingOccurrences(of: "技能_", with: "")
                    .replacingOccurrences(of: ".png", with: "")
            }

            if !skillNames.isEmpty {
                newSkillData[name] = skillNames
                print("\(name)：\(skillNames.joined(separator: ", "))")
            } else {
                print("\(name) 未找到技能图标，可能页面未更新")
            }

            print("进度：\(processedCount)/\(totalCount)")
        }

        // Step 6 合并旧数据与新数据
        var mergedData = existingSkills
        for (key, value) in newSkillData {
            mergedData[key] = value
        }

        // Step 7 上传更新后的 JSON
        do {
            let data = try JSONEncoder().encode(mergedData)
            let localURL = try saveToTempFile(data: data)
            try await uploadToFirebase(localURL: localURL)
            statusMessage = "技能列表更新成功，新增 \(newSkillData.count) 位干员"
            print(statusMessage)
        } catch {
            statusMessage = "上传失败：\(error.localizedDescription)"
            print(statusMessage)
        }
    }

    // MARK: - 从 Firebase 获取 all_operators.json
    private func fetchOperatorList() async -> [String]? {
        let ref = storage.reference(withPath: "json/all_operators.json")
        do {
            let data = try await ref.data(maxSize: 5 * 1024 * 1024)
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("获取干员列表失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 获取旧 skills.json
    private func fetchOldSkillList() async -> [String: [String]]? {
        let ref = storage.reference(withPath: skillJsonPath)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("skills_old.json")
        do {
            try await ref.writeAsync(toFile: tempURL)
            let data = try Data(contentsOf: tempURL)
            return try JSONDecoder().decode([String: [String]].self, from: data)
        } catch {
            print("无旧技能列表或读取失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 获取页面图片（技能图标）
    private func getEmbeddedImages(for page: String) async -> [String] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: page),
            URLQueryItem(name: "prop", value: "images"),
            URLQueryItem(name: "format", value: "json")
        ]

        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let parse = json["parse"] as? [String: Any],
               let images = parse["images"] as? [String] {
                return images
            }
        } catch {
            print("获取 \(page) 图片失败：\(error.localizedDescription)")
        }
        return []
    }

    // MARK: - 保存 JSON
    private func saveToTempFile(data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("skills.json")
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - 上传 Firebase
    private func uploadToFirebase(localURL: URL) async throws {
        let ref = storage.reference(withPath: skillJsonPath)
        _ = try await ref.putFileAsync(from: localURL)
    }
}
