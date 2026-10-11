//
//  CloudSyncService.swift
//  ArknightsToolBox
//
//  更新流程的总入口：按顺序执行各数据集的同步，任一阶段失败不影响其他阶段。
//

import Foundation

struct SyncReport {
    var summaries: [SyncSummary] = []
    var dryRun = false

    var failures: [SyncRecord] { summaries.flatMap(\.failures) }
    var updatedCount: Int { summaries.reduce(0) { $0 + $1.count(.updated) } }

    var text: String {
        summaries.map(\.text).joined(separator: "\n")
    }
}

struct CloudSyncService {
    struct Options {
        var mode: OperatorDataSync.Mode = .incremental
        var dryRun = false            // 只计算差异，不写入云端
    }

    let store: any CloudStoring
    let client: PRTSClient

    init(store: any CloudStoring, client: PRTSClient = PRTSClient()) {
        self.store = store
        self.client = client
    }

    func run(options: Options = Options(), progress: SyncProgressHandler? = nil) async throws -> SyncReport {
        // 先确认 PRTS 可达；连不上时直接抛错，由调用方提示，而不是逐个步骤等超时
        let checkedAt = try await client.checkConnection()

        var report = SyncReport(dryRun: options.dryRun)
        func fail(_ dataset: String, _ error: Error) {
            var summary = SyncSummary(dataset: dataset)
            summary.records.append(SyncRecord(dataset: dataset, name: "整体", status: .failed, message: error.localizedDescription))
            report.summaries.append(summary)
        }

        // 增量状态读取失败时不继续：否则会被当作"从未同步过"而全量覆盖
        var state = try await store.readJSON(CloudPath.syncState, as: SyncState.self) ?? SyncState()
        let originalState = state

        // 1. 干员名单：后续所有步骤的基础。抓取失败时回退到云端现有名单，仍无名单才终止
        var operators: [String]
        do {
            let result = try await OperatorListSync(client: client, store: store, dryRun: options.dryRun).run()
            operators = result.names
            report.summaries.append(result.summary)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            fail("干员名单", error)
            operators = try await store.readJSON(CloudPath.operators, as: [String].self) ?? []
            if operators.isEmpty { return report }
        }

        // 头像只依赖干员名单，与技能、模组、公招的同步并行进行（请求仍共用同一个限速）
        let operatorNames = operators
        async let avatarOutcome: Swift.Result<SyncSummary, Error> = {
            do {
                return .success(try await AvatarSync(client: client, store: store, dryRun: options.dryRun)
                    .run(operators: operatorNames))
            } catch {
                return .failure(error)
            }
        }()

        // 材料数据与图标同样独立于干员数据，并行进行。它用到的状态字段单独传入、单独取回，避免并发修改 state
        let materialModified = state.materialPageModified
        async let materialOutcome: Swift.Result<(summaries: [SyncSummary], lastModified: String?), Error> = {
            do {
                return .success(try await MaterialSync(client: client, store: store, mode: options.mode, dryRun: options.dryRun)
                    .run(lastModified: materialModified))
            } catch {
                return .failure(error)
            }
        }()

        // 2. 技能、模组与公招数据
        var skills: [String: [String]] = [:]
        var modules: [String: [ModuleEntry]] = [:]
        do {
            let result = try await OperatorDataSync(client: client, store: store, mode: options.mode, dryRun: options.dryRun)
                .run(operators: operators, state: &state, checkedAt: checkedAt, progress: progress)
            report.summaries += result.summaries
            skills = result.skills
            modules = result.modules
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            fail("技能、模组与公招", error)
        }

        // 3. 图片（技能图标、模组图标依赖上面的数据）
        switch await avatarOutcome {
        case .success(let summary): report.summaries.append(summary)
        case .failure(let error):
            if error is CancellationError { throw CancellationError() }
            fail(AvatarSync.dataset, error)
        }

        do {
            report.summaries.append(try await SkillIconSync(client: client, store: store, dryRun: options.dryRun)
                .run(skills: skills, progress: progress))
        } catch is CancellationError { throw CancellationError() } catch { fail(SkillIconSync.dataset, error) }

        do {
            report.summaries.append(try await ModuleIconSync(client: client, store: store, dryRun: options.dryRun)
                .run(modules: modules, progress: progress))
        } catch is CancellationError { throw CancellationError() } catch { fail(ModuleIconSync.dataset, error) }

        switch await materialOutcome {
        case .success(let result):
            report.summaries += result.summaries
            state.materialPageModified = result.lastModified
        case .failure(let error):
            if error is CancellationError { throw CancellationError() }
            fail("材料", error)
        }

        // 4. 保存增量状态
        if !options.dryRun, state != originalState {
            do { try await store.writeJSON(state, to: CloudPath.syncState) } catch { fail("同步状态", error) }
        }
        await client.clearCache()
        return report
    }
}
