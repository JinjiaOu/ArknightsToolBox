//
//  OperatorModuleFetcher.swift
//  ArknightsToolBox
//
//  Created by Jinjia Ou on 10/30/25.
//

import Foundation
import FirebaseStorage

@MainActor
class OperatorModuleFetcher: ObservableObject {
    private let baseURL = "https://prts.wiki/api.php"
    private let storage = Storage.storage()
    private let moduleJsonPath = "json/operator_modules_cleaned.json"

    @Published var statusMessage = ""
    @Published var progress: Double = 0.0  // 新增进度条支持

    // 永久跳过（确认没有模组的干员）
    private let skipList: Set<String> = [
        "12F", "CONFESS-47", "Castle-3", "Friston-3", "Lancet-2", "PhonoR-0", "THRM-EX", "U-Official",
        "克洛丝", "卡缇", "史都华德", "夜刀", "安德切尔", "安赛尔", "巡林者", "斑点", "月见夜", "杜林", "梓兰",
        "正义骑士号", "泡普卡", "泰拉大陆调查团", "炎熔", "玫兰莎", "空爆", "米格鲁", "翎羽", "芙蓉", "芬", "香草", "黑角"
    ]

    // ⚙️ 性能配置
    private struct Config {
        static let maxConcurrency = 6        // 并发数：5个同时请求
        static let batchDelay = 0.3          // 批次间延迟：300ms
        static let requestTimeout = 20       // 请求超时：20秒
        static let resourceTimeout = 30      // 资源超时：30秒
        static let retryLimit = 3            // 重试次数：3次
        static let retryBackoff = 1.5        // 退避系数：1.5
    }

    // 自定义短超时 Session
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval(Config.requestTimeout)
        config.timeoutIntervalForResource = TimeInterval(Config.resourceTimeout)
        config.httpAdditionalHeaders = ["User-Agent": "ArknightsModuleFetcher/Swift/3.0"]
        // 启用 HTTP/2 以提高性能
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config)
    }

    // MARK: - 主刷新流程（并发优化版）
    func refreshModules() async {
        let startTime = Date()
        statusMessage = "正在检查模组数据..."
        progress = 0.0

        // Step 1 获取 all_operators.json
        guard let operatorList = await fetchOperatorList() else {
            statusMessage = "无法读取干员列表"
            return
        }
        print("干员总数：\(operatorList.count)")

        // Step 2 获取旧模组 JSON
        var existingModules: [String: [[String: String]]] = [:]
        if let oldData = await fetchOldModuleList() {
            existingModules = oldData
            print("已有模组数据：\(existingModules.count) 位干员")
        }

        // Step 3 计算新干员（跳过 skipList）
        let oldNames = Set(existingModules.keys)
        let allNames = Set(operatorList)
        let newOperators = Array(allNames.subtracting(oldNames).subtracting(skipList)).sorted()

        if newOperators.isEmpty {
            print("没有新干员需要更新模组列表。")
            statusMessage = "模组数据已是最新。"
            progress = 1.0
            return
        }

        print("检测到 \(newOperators.count) 个新干员")
        print("预计耗时：\(estimateTime(count: newOperators.count)) 秒")

        // Step 4 并发抓取模组
        let newModuleData = await fetchModulesConcurrently(operators: newOperators)

        // Step 5 合并数据并上传
        let mergedData = existingModules.merging(newModuleData) { old, new in new }

        do {
            let data = try JSONEncoder().encode(mergedData)
            let localURL = try saveToTempFile(data: data)
            try await uploadToFirebase(localURL: localURL)
            
            let elapsed = Date().timeIntervalSince(startTime)
            statusMessage = "模组数据更新成功，新增 \(newModuleData.count) 位干员（耗时 \(String(format: "%.1f", elapsed))秒）"
            progress = 1.0
            print(statusMessage)
        } catch {
            statusMessage = "上传失败：\(error.localizedDescription)"
            print(statusMessage)
        }
    }

    // MARK: - 并发抓取核心逻辑
    private func fetchModulesConcurrently(operators: [String]) async -> [String: [[String: String]]] {
        var result: [String: [[String: String]]] = [:]
        let total = operators.count
        var completed = 0
        
        // 使用 actor 保证线程安全
        actor ResultCollector {
            private var data: [String: [[String: String]]] = [:]
            
            func add(name: String, modules: [[String: String]]) {
                data[name] = modules
            }
            
            func getAll() -> [String: [[String: String]]] {
                return data
            }
        }
        
        let collector = ResultCollector()
        
        // 分批处理，每批 maxConcurrency 个
        let batches = operators.chunked(into: Config.maxConcurrency)
        
        for (batchIndex, batch) in batches.enumerated() {
            print("\n📦 批次 \(batchIndex + 1)/\(batches.count)，处理 \(batch.count) 个干员")
            
            // 并发处理当前批次
            await withTaskGroup(of: (String, [[String: String]]).self) { group in
                for name in batch {
                    group.addTask {
                        let modules = await self.fetchOperatorModule(name: name)
                        return (name, modules)
                    }
                }
                
                // 收集结果
                for await (name, modules) in group {
                    if !modules.isEmpty {
                        await collector.add(name: name, modules: modules)
                    }
                    
                    completed += 1
                    
                    // 更新进度
                    await MainActor.run {
                        self.progress = Double(completed) / Double(total)
                    }
                }
            }
            
            // 批次间延迟（最后一批不延迟）
            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(Config.batchDelay * 1_000_000_000))
            }
        }
        
        return await collector.getAll()
    }

    // MARK: - 抓取单个干员模组
    private func fetchOperatorModule(name: String) async -> [[String: String]] {
        print("  [处理] \(name)")
        
        let content = await fetchWikiTextImproved(for: name)
        if content.isEmpty {
            print("  [失败] \(name)")
            return []
        }

        let modules = parseModulesImproved(from: content)
        if modules.isEmpty {
            print("  [无模组] \(name)")
        } else {
            print("  [成功] \(name) - \(modules.count) 个模组")
        }
        
        return modules
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

    // MARK: - 获取旧模组 JSON
    private func fetchOldModuleList() async -> [String: [[String: String]]]? {
        let ref = storage.reference(withPath: moduleJsonPath)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("modules_old.json")
        do {
            try await ref.writeAsync(toFile: tempURL)
            let data = try Data(contentsOf: tempURL)
            return try JSONDecoder().decode([String: [[String: String]]].self, from: data)
        } catch {
            print("无旧模组数据或读取失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 改进的请求页面逻辑
    private func fetchWikiTextImproved(for name: String, retries: Int = Config.retryLimit) async -> String {
        for attempt in 1...retries {
            do {
                var components = URLComponents(string: baseURL)!
                components.queryItems = [
                    URLQueryItem(name: "action", value: "query"),
                    URLQueryItem(name: "prop", value: "revisions"),
                    URLQueryItem(name: "titles", value: name),
                    URLQueryItem(name: "rvprop", value: "content"),
                    URLQueryItem(name: "format", value: "json")
                ]

                guard let url = components.url else { return "" }

                let (data, response) = try await session.data(from: url)
                
                // 检查 HTTP 状态码
                if let httpResponse = response as? HTTPURLResponse {
                    // 处理 429 Too Many Requests
                    if httpResponse.statusCode == 429 {
                        print("  ⚠️ 触发速率限制，等待 5 秒...")
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        continue
                    }
                    
                    // 其他错误状态码
                    if httpResponse.statusCode != 200 {
                        if attempt < retries {
                            let backoff = pow(Config.retryBackoff, Double(attempt))
                            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                            continue
                        }
                        return ""
                    }
                }
                
                // 解析 JSON
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = json["query"] as? [String: Any],
                      let pages = query["pages"] as? [String: Any],
                      let page = pages.values.first as? [String: Any] else {
                    return ""
                }
                
                // 检查页面是否存在
                if page["missing"] != nil {
                    return ""
                }
                
                // 提取内容
                if let revisions = page["revisions"] as? [[String: Any]],
                   let firstRevision = revisions.first {
                    if let content = firstRevision["*"] as? String {
                        return content
                    }
                    if let slots = firstRevision["slots"] as? [String: Any],
                       let main = slots["main"] as? [String: Any],
                       let content = main["*"] as? String {
                        return content
                    }
                }
                
                return ""
                
            } catch let error as URLError {
                switch error.code {
                case .timedOut:
                    break  // 重试
                case .notConnectedToInternet:
                    return ""  // 不重试
                default:
                    break  // 重试
                }
                
                if attempt < retries {
                    let backoff = pow(Config.retryBackoff, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            } catch {
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: UInt64(Double(attempt) * Config.retryBackoff * 1_000_000_000))
                }
            }
        }
        
        return ""
    }

    // MARK: - 改进的模组解析逻辑
    private func parseModulesImproved(from wikiText: String) -> [[String: String]] {
        guard !wikiText.isEmpty else { return [] }
        var result: [[String: String]] = []

        let templatePattern = #"\{\{模组[^\}]*\}\}"#
        guard let templateRegex = try? NSRegularExpression(pattern: templatePattern, options: [.caseInsensitive]) else {
            return []
        }
        
        let matches = templateRegex.matches(in: wikiText, range: NSRange(location: 0, length: wikiText.utf16.count))
        
        for match in matches {
            guard let matchRange = Range(match.range, in: wikiText) else { continue }
            let templateText = String(wikiText[matchRange])
            
            var moduleName: String?
            var moduleType: String?
            
            // 提取名称
            let namePattern = #"\|\s*名称\s*=\s*([^|\n\}]+)"#
            if let nameRegex = try? NSRegularExpression(pattern: namePattern, options: []),
               let nameMatch = nameRegex.firstMatch(in: templateText, range: NSRange(location: 0, length: templateText.utf16.count)),
               let nameRange = Range(nameMatch.range(at: 1), in: templateText) {
                moduleName = String(templateText[nameRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "<br>", with: "")
                    .replacingOccurrences(of: "<br/>", with: "")
            }
            
            // 提取类型
            let typePattern = #"\|\s*类型\s*=\s*([^|\n\}]+)"#
            if let typeRegex = try? NSRegularExpression(pattern: typePattern, options: []),
               let typeMatch = typeRegex.firstMatch(in: templateText, range: NSRange(location: 0, length: templateText.utf16.count)),
               let typeRange = Range(typeMatch.range(at: 1), in: templateText) {
                moduleType = String(templateText[typeRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "<br>", with: "")
                    .replacingOccurrences(of: "<br/>", with: "")
            }
            
            if let name = moduleName, let type = moduleType,
               !name.isEmpty, !type.isEmpty {
                result.append(["名称": name, "类型": type])
            }
        }

        return result
    }

    // MARK: - 保存与上传
    private func saveToTempFile(data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("operator_modules_cleaned.json")
        try data.write(to: fileURL)
        return fileURL
    }

    private func uploadToFirebase(localURL: URL) async throws {
        let ref = storage.reference(withPath: moduleJsonPath)
        _ = try await ref.putFileAsync(from: localURL)
    }
    
    // MARK: - 辅助函数
    
    /// 预估耗时
    private func estimateTime(count: Int) -> Int {
        // 每批 5 个，批次间延迟 0.3 秒
        // 每个请求平均 2 秒（包含重试）
        let batches = (count + Config.maxConcurrency - 1) / Config.maxConcurrency
        let avgTimePerBatch = 2  // 秒（因为是并发）
        let totalDelay = batches * Int(Config.batchDelay)
        return batches * avgTimePerBatch + totalDelay
    }
}

// MARK: - 扩展：辅助功能
extension OperatorModuleFetcher {
    /// 测试单个干员的抓取（用于调试）
    func testFetchOperator(name: String) async {
        print("=== 测试抓取：\(name) ===")
        let modules = await fetchOperatorModule(name: name)
        
        if modules.isEmpty {
            print("❌ 获取失败或无模组")
        } else {
            print("✅ 成功提取 \(modules.count) 个模组")
            for (index, module) in modules.enumerated() {
                print("  模组 \(index + 1)：\(module)")
            }
        }
    }
    
    /// 批量测试（调试用）
    func testBatch(names: [String]) async {
        print("=== 批量测试：\(names.count) 个干员 ===")
        let startTime = Date()
        
        let result = await fetchModulesConcurrently(operators: names)
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("\n✅ 完成！耗时 \(String(format: "%.1f", elapsed)) 秒")
        print("成功：\(result.count) 个")
        print("失败：\(names.count - result.count) 个")
    }
}

// MARK: - Array 分块扩展
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
