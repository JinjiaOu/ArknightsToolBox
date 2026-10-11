//
//  ImageSync.swift
//  ArknightsToolBox
//
//  头像、技能图标、模组类型图标的同步：对比云端已有文件，只下载缺失的，
//  上传前校验 PNG 完整性。
//

import Foundation

// MARK: - 通用上传

struct ImageJob: Sendable {
    let name: String          // 用于记录的名字，如干员名
    let wikiFile: String      // PRTS 上的文件名
    let cloudPath: String     // 云端完整路径
}

struct ImageUploader {
    let client: PRTSClient
    let store: any CloudStoring
    var dryRun = false
    var concurrency = 3

    func upload(_ jobs: [ImageJob], dataset: String, progress: SyncProgressHandler? = nil) async -> [SyncRecord] {
        var records: [SyncRecord] = []
        var completed = 0
        let client = self.client
        let store = self.store
        let dryRun = self.dryRun

        await runConcurrently(jobs, limit: concurrency, work: { job -> SyncRecord in
            if dryRun { return SyncRecord(dataset: dataset, name: job.name, status: .updated, message: "将上传 \(job.cloudPath)") }
            do {
                let url = try await client.imageURL(filename: job.wikiFile)
                let data = try await client.download(url)
                try await store.uploadPNG(data, to: job.cloudPath)
                return SyncRecord(dataset: dataset, name: job.name, status: .updated, message: job.cloudPath)
            } catch is CancellationError {
                return SyncRecord(dataset: dataset, name: job.name, status: .failed, message: "已取消")
            } catch {
                return SyncRecord(dataset: dataset, name: job.name, status: .failed, message: error.localizedDescription)
            }
        }, onResult: { _, record in
            records.append(record)
            completed += 1
            progress?(SyncProgress(stage: "上传\(dataset)", completed: completed, total: jobs.count))
        })
        return records
    }
}

// MARK: - 头像

struct AvatarSync {
    static let dataset = "干员头像"
    let client: PRTSClient
    let store: any CloudStoring
    var dryRun = false

    func run(operators: [String], progress: SyncProgressHandler? = nil) async throws -> SyncSummary {
        let existing = try await store.listFileNames(in: CloudPath.avatarFolder)
        let jobs = operators.compactMap { name -> ImageJob? in
            let file = CloudPath.avatarFile(name)
            return existing.contains(file) ? nil
                : ImageJob(name: name, wikiFile: file, cloudPath: "\(CloudPath.avatarFolder)/\(file)")
        }
        var summary = SyncSummary(dataset: Self.dataset)
        summary.records = await ImageUploader(client: client, store: store, dryRun: dryRun)
            .upload(jobs, dataset: Self.dataset, progress: progress)
        if jobs.isEmpty { summary.records.append(SyncRecord(dataset: Self.dataset, name: "全部", status: .unchanged)) }
        return summary
    }
}

// MARK: - 技能图标

struct SkillIconSync {
    static let dataset = "技能图标"
    let client: PRTSClient
    let store: any CloudStoring
    var dryRun = false

    func run(skills: [String: [String]], progress: SyncProgressHandler? = nil) async throws -> SyncSummary {
        let existing = try await store.listFileNames(in: CloudPath.skillIconFolder)
        var summary = SyncSummary(dataset: Self.dataset)

        // 云端已有首选名或别名中的任意一个，都视为已存在
        var missing: [String: [String]] = [:]
        for (operatorName, list) in skills {
            for skill in list where !CloudPath.skillIconCandidates(operatorName: operatorName, skill: skill)
                .contains(where: existing.contains) {
                missing[operatorName, default: []].append(skill)
            }
        }

        // 用页面实际的图片文件名，不再猜测文件名
        var jobs: [ImageJob] = []
        for operatorName in missing.keys.sorted() {
            try Task.checkCancellation()
            do {
                let files = WikiDataParser.skillImages(fromImages: try await client.images(of: operatorName))
                for skill in missing[operatorName] ?? [] {
                    if let match = files.first(where: { $0.name == skill }) {
                        let target = CloudPath.skillIconFile(operatorName: operatorName, skill: skill)
                        jobs.append(ImageJob(name: "\(operatorName)·\(skill)", wikiFile: match.file,
                                             cloudPath: "\(CloudPath.skillIconFolder)/\(target)"))
                    } else {
                        summary.records.append(SyncRecord(dataset: Self.dataset, name: "\(operatorName)·\(skill)",
                                                          status: .failed, message: "页面中没有该技能图标"))
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                summary.records.append(SyncRecord(dataset: Self.dataset, name: operatorName,
                                                  status: .failed, message: error.localizedDescription))
            }
        }

        summary.records += await ImageUploader(client: client, store: store, dryRun: dryRun)
            .upload(jobs, dataset: Self.dataset, progress: progress)
        if summary.records.isEmpty { summary.records.append(SyncRecord(dataset: Self.dataset, name: "全部", status: .unchanged)) }
        return summary
    }
}

// MARK: - 模组类型图标

struct ModuleIconSync {
    static let dataset = "模组图标"
    static let prefix = "模组类型_"
    static let suffix = "_小图.png"
    let client: PRTSClient
    let store: any CloudStoring
    var dryRun = false

    func run(modules: [String: [ModuleEntry]], progress: SyncProgressHandler? = nil) async throws -> SyncSummary {
        // PRTS 上的全部模组类型小图，文件名规范化后作为云端文件名
        var sources: [String: String] = [:]      // 云端文件名 → PRTS 文件名
        for source in try await client.allImages(prefix: Self.prefix) {
            let normal = source.replacingOccurrences(of: " ", with: "_")
            guard normal.hasPrefix(Self.prefix), normal.hasSuffix(Self.suffix) else { continue }
            let label = String(normal.dropFirst(Self.prefix.count).dropLast(Self.suffix.count))
            sources[CloudPath.moduleIconFile(type: label)] = source
        }

        let existing = try await store.listFileNames(in: CloudPath.moduleIconFolder)
        let jobs = sources.keys.sorted().filter { !existing.contains($0) }.map {
            ImageJob(name: String($0.dropLast(4)), wikiFile: sources[$0]!, cloudPath: "\(CloudPath.moduleIconFolder)/\($0)")
        }

        var summary = SyncSummary(dataset: Self.dataset)
        summary.records = await ImageUploader(client: client, store: store, dryRun: dryRun)
            .upload(jobs, dataset: Self.dataset, progress: progress)

        // 数据里用到、但 PRTS 和云端都没有图标的类型
        let used = Set(modules.values.flatMap { $0.map(\.type) }.filter { !$0.isEmpty }.map(CloudPath.moduleIconFile(type:)))
        for file in used.subtracting(existing).subtracting(sources.keys).sorted() {
            summary.records.append(SyncRecord(dataset: Self.dataset, name: String(file.dropLast(4)),
                                              status: .failed, message: "PRTS 上没有该类型的小图"))
        }
        if summary.records.isEmpty { summary.records.append(SyncRecord(dataset: Self.dataset, name: "全部", status: .unchanged)) }
        return summary
    }
}
