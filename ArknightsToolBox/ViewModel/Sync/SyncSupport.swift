//
//  SyncSupport.swift
//  ArknightsToolBox
//
//  同步流程共用的类型：云端存储协议、进度与结果、增量状态、云端命名规则。
//  只依赖 Foundation，便于不连 Firebase 单独测试。
//

import Foundation

// MARK: - 云端存储协议

protocol CloudStoring {
    /// 文件不存在返回 nil；网络或解码错误应抛出，避免被当成"没有旧数据"而覆盖
    func readJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T?
    /// 覆盖写入；实现应先把旧文件备份一份
    func writeJSON<T: Encodable>(_ value: T, to path: String) async throws
    func listFileNames(in folder: String) async throws -> Set<String>
    /// 校验 PNG 后上传
    func uploadPNG(_ data: Data, to path: String) async throws
}

// MARK: - 进度与结果

enum SyncStatus: String {
    case updated        // 数据有变化并已写入
    case unchanged      // 检查过，没有变化
    case skipped        // 未变化，无需检查
    case failed         // 失败，旧数据保持不变
}

struct SyncRecord {
    let dataset: String
    let name: String
    let status: SyncStatus
    var message: String?
}

struct SyncSummary {
    let dataset: String
    var records: [SyncRecord] = []

    func count(_ status: SyncStatus) -> Int { records.filter { $0.status == status }.count }
    var failures: [SyncRecord] { records.filter { $0.status == .failed } }

    var text: String {
        "\(dataset)：更新 \(count(.updated))，无变化 \(count(.unchanged) + count(.skipped))，失败 \(count(.failed))"
    }
}

struct SyncProgress {
    let stage: String
    let completed: Int
    let total: Int
}

typealias SyncProgressHandler = (SyncProgress) -> Void

// MARK: - 增量状态（保存在云端 json/sync_state.json）

struct SyncState: Codable, Equatable {
    /// 解析规则变化时递增，使所有干员重新抓取一次
    static let currentParserVersion = 1

    var parserVersion = SyncState.currentParserVersion
    /// 数据集名 → 干员名 → 上次成功同步时的页面版本签名
    var signatures: [String: [String: String]] = [:]
    /// 上次完整检查页面更新时的 PRTS 服务器时间（ISO 8601）。
    /// 有它且不太久远时，只需问 PRTS"这之后改了哪些页面"，不必逐页查版本。
    var lastChangeCheck: String?
    /// 上次解析"道具一览"页面时的 Last-Modified，用于条件请求（页面没变就不必重新下载解析）
    var materialPageModified: String?

    /// 超过这个天数就不再信任"最近更改"记录（Wiki 会清理旧记录），改回逐页查版本
    static let changeLogMaxAgeDays = 14

    /// 距离上次检查是否在可信范围内
    func lastChangeCheckDate(now: Date = Date()) -> Date? {
        guard let lastChangeCheck,
              let date = ISO8601DateFormatter().date(from: lastChangeCheck),
              now.timeIntervalSince(date) < Double(Self.changeLogMaxAgeDays) * 86_400,
              date <= now.addingTimeInterval(300) else { return nil }
        return date
    }

    mutating func resetIfParserChanged() {
        if parserVersion != SyncState.currentParserVersion {
            self = SyncState()
        }
    }
}

// MARK: - 云端路径与文件命名（App 取图与同步上传必须使用同一套规则）

enum CloudPath {
    static let operators = "json/all_operators.json"
    static let skills = "json/skills.json"
    static let modules = "json/operator_modules_cleaned.json"
    static let recruitment = "json/公开招募干员带标签.json"
    static let materials = "json/arknights_materials_rarity.json"
    static let syncState = "json/sync_state.json"

    static let avatarFolder = "character_logo"
    static let skillIconFolder = "skill_icons"
    static let moduleIconFolder = "module_icons"
    static let materialIconFolder = "material_icons"

    static func avatarFile(_ operatorName: String) -> String {
        "头像_\(operatorName).png"
    }

    /// 首选文件名：与页面中的技能名一致，App 优先请求这个
    static func skillIconFile(operatorName: String, skill: String) -> String {
        "技能图标_\(operatorName)_\(skill).png"
    }

    /// 别名：去掉首尾引号、替换非法字符、去掉结尾的点（ResourceTool 的命名习惯）
    static func skillIconAlias(operatorName: String, skill: String) -> String {
        safeFileName("技能图标_\(operatorName)_\(skillLabel(skill))") + ".png"
    }

    /// 云端可能存在的全部文件名，按优先级排列
    static func skillIconCandidates(operatorName: String, skill: String) -> [String] {
        let primary = skillIconFile(operatorName: operatorName, skill: skill)
        let alias = skillIconAlias(operatorName: operatorName, skill: skill)
        return primary == alias ? [primary] : [primary, alias]
    }

    static func materialIconFile(_ name: String) -> String {
        "\(name).png"
    }

    static func moduleIconFile(type: String) -> String {
        WikiDataParser.moduleType(type) + ".png"
    }

    static func skillLabel(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(String, String)] = [("\"", "\""), ("“", "”")]
        while s.count >= 2, let first = s.first, let last = s.last,
              pairs.contains(where: { $0.0 == String(first) && $0.1 == String(last) }) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    static func safeFileName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = s.last, last == "." || last == " " { s.removeLast() }
        return s
    }
}

// MARK: - 小工具

extension Sequence where Element == String {
    /// 按 Unicode 码点排序，与 Python 的 sorted() 结果一致
    func sortedByCodePoint() -> [String] {
        sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
    }
}

extension Array {
    func chunks(ofSize size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// 限制并发数地处理一批任务；每个任务完成时在调用方的上下文里回调
func runConcurrently<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    limit: Int,
    work: @escaping @Sendable (Item) async -> Output,
    onResult: (Item, Output) -> Void
) async {
    await withTaskGroup(of: (Int, Output).self) { group in
        var next = 0
        func startNext() {
            guard next < items.count else { return }
            let index = next
            next += 1
            let item = items[index]
            group.addTask { (index, await work(item)) }
        }
        for _ in 0..<min(limit, items.count) { startNext() }
        while let (index, output) = await group.next() {
            onResult(items[index], output)
            if Task.isCancelled { group.cancelAll(); continue }
            startNext()
        }
    }
}
