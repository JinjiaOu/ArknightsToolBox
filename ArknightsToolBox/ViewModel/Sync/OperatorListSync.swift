//
//  OperatorListSync.swift
//  ArknightsToolBox
//
//  干员名单同步。只增不删：已有名单与 PRTS 新名单取并集，
//  分类接口返回空列表时保持原数据，避免一次异常清空云端。
//

import Foundation

struct OperatorListSync {
    let client: PRTSClient
    let store: any CloudStoring
    var dryRun = false

    /// 返回同步后的完整名单，以及本次的结果汇总
    func run() async throws -> (names: [String], summary: SyncSummary) {
        let fetched = try await client.category("干员")
        guard !fetched.isEmpty else { throw PRTSError.failed("干员分类返回空列表，保留云端数据") }

        let existing = try await store.readJSON(CloudPath.operators, as: [String].self) ?? []
        let merged = Set(existing).union(WikiDataParser.operatorNames(fromCategory: fetched))
        let names = merged.sortedByCodePoint()

        var summary = SyncSummary(dataset: "干员名单")
        let added = merged.subtracting(existing).sortedByCodePoint()
        if added.isEmpty && !existing.isEmpty {
            summary.records.append(SyncRecord(dataset: "干员名单", name: "全部", status: .unchanged))
        } else {
            if !dryRun { try await store.writeJSON(names, to: CloudPath.operators) }
            for name in added {
                summary.records.append(SyncRecord(dataset: "干员名单", name: name, status: .updated, message: "新增干员"))
            }
        }
        return (names, summary)
    }
}
