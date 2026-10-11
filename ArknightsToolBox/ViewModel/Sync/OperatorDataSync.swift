//
//  OperatorDataSync.swift
//  ArknightsToolBox
//
//  技能列表、模组列表与公开招募数据的增量同步。
//
//  相比旧实现的区别：
//  - 已有干员的页面被编辑后也会重新抓取（用页面版本号判断，一次请求可查 50 个页面）
//  - 失败只影响单个干员，旧数据保持不变
//  - 已有非空数据本次解析为空时视为异常，保留旧数据
//  - 不再需要手写的"无技能/无模组干员"名单
//  - 按块批量取页面源码（每块 15 位干员 1 个请求），技能、模组、公招都在本地从源码解析，
//    请求数从每位干员约 3 个降到约 0.1 个
//

import Foundation

struct OperatorDataSync {
    enum Mode {
        case incremental     // 只抓取新干员和页面有变化的干员
        case full            // 重新抓取全部干员
    }

    static let skillsDataset = "技能列表"
    static let modulesDataset = "模组列表"
    static let recruitDataset = "公开招募"

    let client: PRTSClient
    let store: any CloudStoring
    var mode: Mode = .incremental
    var dryRun = false
    var concurrency = 3

    private struct Outcome: Sendable {
        var skills: Swift.Result<[String], Failure>?
        var modules: Swift.Result<[ModuleEntry], Failure>?
        var recruit: Swift.Result<RecruitEntry?, Failure>?     // nil 表示不是公开招募干员
    }
    private struct Failure: Error, Sendable { let message: String }

    struct Result {
        var summaries: [SyncSummary]
        var skills: [String: [String]]
        var modules: [String: [ModuleEntry]]
        var recruitment: [RecruitEntry]
    }

    /// - Parameter checkedAt: 本次检查开始时的 PRTS 服务器时间，成功后记入状态，供下次用"最近更改"判断
    func run(operators: [String],
             state: inout SyncState,
             checkedAt: String? = nil,
             progress: SyncProgressHandler? = nil) async throws -> Result {
        var skillValues = try await store.readJSON(CloudPath.skills, as: [String: [String]].self) ?? [:]
        var moduleValues = try await store.readJSON(CloudPath.modules, as: [String: [ModuleEntry]].self) ?? [:]
        var recruitValues = Dictionary(
            uniqueKeysWithValues: (try await store.readJSON(CloudPath.recruitment, as: [RecruitEntry].self) ?? [])
                .map { ($0.name, $0) })
        let hadSkills = !skillValues.isEmpty, hadModules = !moduleValues.isEmpty, hadRecruit = !recruitValues.isEmpty
        state.resetIfParserChanged()

        // 先确定哪些干员需要查版本。
        // 增量模式且上次检查不久前：问一次"最近更改"，只检查被改过的页面，以及还没有完整同步记录的干员。
        // 否则（第一次、太久没同步、查询失败、强制全量）逐页查版本。
        let upgradeTitle: (String) -> String = { "\($0)(升级)" }
        var toCheck = operators
        if mode == .incremental, let since = state.lastChangeCheckDate() {
            progress?(SyncProgress(stage: "检查干员页面更新", completed: 0, total: 1))
            if let changedTitles = try? await client.changedPages(since: since) {
                let known = Set(operators)
                var changed = Set<String>()
                for title in changedTitles {
                    if known.contains(title) {
                        changed.insert(title)
                    } else if title.hasSuffix("(升级)"), known.contains(String(title.dropLast("(升级)".count))) {
                        changed.insert(String(title.dropLast("(升级)".count)))
                    }
                }
                let datasets = [Self.skillsDataset, Self.modulesDataset, Self.recruitDataset]
                toCheck = operators.filter { name in
                    changed.contains(name) || skillValues[name] == nil || moduleValues[name] == nil
                        || datasets.contains { state.signatures[$0]?[name] == nil }
                }
            }
            try Task.checkCancellation()
        }
        let checkSet = Set(toCheck)

        // 页面版本签名：主页面 + "(升级)" 页面
        progress?(SyncProgress(stage: "检查干员页面更新", completed: 0, total: max(toCheck.count * 2, 1)))
        let revisions = toCheck.isEmpty ? [:] : try await client.revisionIDs(of: toCheck + toCheck.map(upgradeTitle)) { done, total in
            progress?(SyncProgress(stage: "检查干员页面更新", completed: done, total: total))
        }
        func signature(_ name: String, includeUpgrade: Bool) -> String {
            let main = revisions[name] ?? 0
            return includeUpgrade ? "\(main)/\(revisions[upgradeTitle(name)] ?? 0)" : "\(main)"
        }

        // 哪些干员需要抓取
        func needsSkills(_ name: String) -> Bool {
            guard checkSet.contains(name) else { return false }
            return mode == .full || skillValues[name] == nil
                || state.signatures[Self.skillsDataset]?[name] != signature(name, includeUpgrade: false)
        }
        func needsModules(_ name: String) -> Bool {
            guard checkSet.contains(name) else { return false }
            return mode == .full || moduleValues[name] == nil
                || state.signatures[Self.modulesDataset]?[name] != signature(name, includeUpgrade: true)
        }
        // 公招数据只收录公开招募干员，不能靠"是否已有条目"判断，只看页面版本
        func needsRecruit(_ name: String) -> Bool {
            guard checkSet.contains(name) else { return false }
            return mode == .full || state.signatures[Self.recruitDataset]?[name] != signature(name, includeUpgrade: false)
        }
        let targets = toCheck.filter { needsSkills($0) || needsModules($0) || needsRecruit($0) }

        var skillSummary = SyncSummary(dataset: Self.skillsDataset)
        var moduleSummary = SyncSummary(dataset: Self.modulesDataset)
        var recruitSummary = SyncSummary(dataset: Self.recruitDataset)
        // 抓取与解析：每块 15 位干员合并成一次页面源码请求
        let wantSkills = Set(targets.filter(needsSkills)), wantModules = Set(targets.filter(needsModules))
        let wantRecruit = Set(targets.filter(needsRecruit))
        for name in operators {
            if !wantSkills.contains(name) { skillSummary.records.append(SyncRecord(dataset: Self.skillsDataset, name: name, status: .skipped)) }
            if !wantModules.contains(name) { moduleSummary.records.append(SyncRecord(dataset: Self.modulesDataset, name: name, status: .skipped)) }
            if !wantRecruit.contains(name) { recruitSummary.records.append(SyncRecord(dataset: Self.recruitDataset, name: name, status: .skipped)) }
        }

        // 版本号大于 0 说明"(升级)"页面存在；不存在的页面不需要请求
        let upgradePages = Set(operators.filter { (revisions[upgradeTitle($0)] ?? 0) > 0 })

        var completed = 0
        let client = self.client
        await runConcurrently(targets.chunks(ofSize: 15), limit: concurrency, work: { chunk -> [(String, Outcome)] in
            let titles = chunk + chunk.filter(upgradePages.contains).map(upgradeTitle)
            do {
                let texts = try await client.wikitexts(titles)
                return chunk.map { name in
                    (name, Self.parse(name, texts: texts, hasUpgradePage: upgradePages.contains(name),
                                      skills: wantSkills.contains(name), modules: wantModules.contains(name),
                                      recruit: wantRecruit.contains(name)))
                }
            } catch {
                let message = error is CancellationError ? "已取消" : error.localizedDescription
                let failure = Failure(message: message)
                return chunk.map { name in
                    var outcome = Outcome()
                    if wantSkills.contains(name) { outcome.skills = .failure(failure) }
                    if wantModules.contains(name) { outcome.modules = .failure(failure) }
                    if wantRecruit.contains(name) { outcome.recruit = .failure(failure) }
                    return (name, outcome)
                }
            }
        }, onResult: { _, results in
            for (name, outcome) in results {
                completed += 1
                progress?(SyncProgress(stage: "同步技能、模组与公招", completed: completed, total: targets.count))

                if let result = outcome.skills {
                    let record = Self.merge(result, name: name, dataset: Self.skillsDataset,
                                            values: &skillValues, isEmpty: { $0.isEmpty })
                    skillSummary.records.append(record)
                    if record.status != .failed {
                        state.signatures[Self.skillsDataset, default: [:]][name] = signature(name, includeUpgrade: false)
                    }
                }
                if let result = outcome.modules {
                    let record = Self.merge(result, name: name, dataset: Self.modulesDataset,
                                            values: &moduleValues, isEmpty: { $0.isEmpty })
                    moduleSummary.records.append(record)
                    if record.status != .failed {
                        state.signatures[Self.modulesDataset, default: [:]][name] = signature(name, includeUpgrade: true)
                    }
                }
                if let result = outcome.recruit {
                    let record = Self.mergeRecruit(result, name: name, values: &recruitValues)
                    recruitSummary.records.append(record)
                    if record.status != .failed {
                        state.signatures[Self.recruitDataset, default: [:]][name] = signature(name, includeUpgrade: false)
                    }
                }
            }
        })
        try Task.checkCancellation()
        if let checkedAt { state.lastChangeCheck = checkedAt }

        // 公招文件是数组，按干员名排序，保证输出稳定
        let recruitArray = recruitValues.values.sorted {
            Array($0.name.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.name.unicodeScalars.map(\.value))
        }

        // 写回云端：只有确实发生变化才写
        if !dryRun {
            if skillSummary.count(.updated) > 0 || !hadSkills { try await store.writeJSON(skillValues, to: CloudPath.skills) }
            if moduleSummary.count(.updated) > 0 || !hadModules { try await store.writeJSON(moduleValues, to: CloudPath.modules) }
            if recruitSummary.count(.updated) > 0 || !hadRecruit { try await store.writeJSON(recruitArray, to: CloudPath.recruitment) }
        }
        return Result(summaries: [skillSummary, moduleSummary, recruitSummary],
                      skills: skillValues, modules: moduleValues, recruitment: recruitArray)
    }

    /// 把一次抓取结果合并进已有数据，并给出记录
    private static func merge<Value: Equatable>(
        _ result: Swift.Result<Value, Failure>,
        name: String, dataset: String,
        values: inout [String: Value],
        isEmpty: (Value) -> Bool
    ) -> SyncRecord {
        switch result {
        case .failure(let failure):
            return SyncRecord(dataset: dataset, name: name, status: .failed, message: failure.message)
        case .success(let parsed):
            if let old = values[name], !isEmpty(old), isEmpty(parsed) {
                return SyncRecord(dataset: dataset, name: name, status: .failed,
                                  message: "已有非空数据，但本次未解析到任何项；保留旧数据，请检查页面模板")
            }
            if values[name] == parsed {
                return SyncRecord(dataset: dataset, name: name, status: .unchanged)
            }
            let isNew = values[name] == nil
            values[name] = parsed
            return SyncRecord(dataset: dataset, name: name, status: .updated, message: isNew ? "新增" : "内容变化")
        }
    }

    /// 公招数据：解析为 nil 表示该干员不是公开招募干员，需要从列表中移除
    private static func mergeRecruit(
        _ result: Swift.Result<RecruitEntry?, Failure>,
        name: String,
        values: inout [String: RecruitEntry]
    ) -> SyncRecord {
        let dataset = recruitDataset
        switch result {
        case .failure(let failure):
            return SyncRecord(dataset: dataset, name: name, status: .failed, message: failure.message)
        case .success(let parsed):
            guard let parsed else {
                guard values.removeValue(forKey: name) != nil else {
                    return SyncRecord(dataset: dataset, name: name, status: .unchanged)
                }
                return SyncRecord(dataset: dataset, name: name, status: .updated, message: "不再是公开招募干员")
            }
            if values[name] == parsed { return SyncRecord(dataset: dataset, name: name, status: .unchanged) }
            let isNew = values[name] == nil
            values[name] = parsed
            return SyncRecord(dataset: dataset, name: name, status: .updated, message: isNew ? "新增公招干员" : "内容变化")
        }
    }

    /// 从已取得的页面源码解析一位干员的技能、模组与公招
    private static func parse(_ name: String, texts: [String: String], hasUpgradePage: Bool,
                              skills: Bool, modules: Bool, recruit: Bool) -> Outcome {
        var outcome = Outcome()
        guard let main = texts[name] else {
            let failure = Failure(message: "页面不存在或无源码：\(name)")
            if skills { outcome.skills = .failure(failure) }
            if modules { outcome.modules = .failure(failure) }
            if recruit { outcome.recruit = .failure(failure) }
            return outcome
        }
        if skills { outcome.skills = .success(WikiDataParser.skillNames(fromWikitext: main)) }
        if modules {
            // 升级页应该存在却没取到时，说明这次请求不完整，不能当作"没有模组"
            let upgrade = texts["\(name)(升级)"]
            if hasUpgradePage && upgrade == nil {
                outcome.modules = .failure(Failure(message: "升级页面没有取到内容：\(name)(升级)"))
            } else {
                outcome.modules = .success(WikiDataParser.modules(upgradeText: upgrade, mainText: main))
            }
        }
        if recruit {
            do { outcome.recruit = .success(try WikiDataParser.recruitment(name: name, text: main)) }
            catch { outcome.recruit = .failure(Failure(message: error.localizedDescription)) }
        }
        return outcome
    }
}
