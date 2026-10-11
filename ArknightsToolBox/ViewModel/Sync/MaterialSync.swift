//
//  MaterialSync.swift
//  ArknightsToolBox
//
//  材料数据同步：稀有度表（json/arknights_materials_rarity.json）与材料图标（material_icons/）。
//  数据来自 PRTS "道具一览" 页面；图标使用页面里的"带框"原图。
//

import Foundation

struct MaterialSync {
    static let dataDataset = "材料数据"
    static let iconDataset = "材料图标"
    static let pagePath = "道具一览"
    static let iconPrefix = "道具_带框_"

    let client: PRTSClient
    let store: any CloudStoring
    var mode: OperatorDataSync.Mode = .incremental
    var dryRun = false

    /// - Parameter lastModified: 上次解析页面时的 Last-Modified；页面没变就跳过下载与解析
    /// - Returns: 结果汇总，以及应保存的新 Last-Modified
    func run(lastModified: String?, progress: SyncProgressHandler? = nil) async throws -> (summaries: [SyncSummary], lastModified: String?) {
        var dataSummary = SyncSummary(dataset: Self.dataDataset)
        var newModified = lastModified

        var values = Dictionary(
            uniqueKeysWithValues: (try await store.readJSON(CloudPath.materials, as: [MaterialEntry].self) ?? []).map { ($0.name, $0) })
        let hadData = !values.isEmpty

        // 1. 材料目录。云端还没有数据时不带条件，保证一定拿到页面
        let condition = (mode == .incremental && hadData) ? lastModified : nil
        do {
            if let page = try await client.page(path: Self.pagePath, ifModifiedSince: condition) {
                let catalog = WikiDataParser.materialCatalog(fromHTML: page.html)
                guard !catalog.isEmpty else { throw PRTSError.failed("道具一览页面没有识别到材料，保留云端数据") }

                for entry in catalog where values[entry.name] != entry {
                    let message = values[entry.name].map { "稀有度 \($0.rarity)→\(entry.rarity)" } ?? "新增材料"
                    values[entry.name] = entry
                    dataSummary.records.append(SyncRecord(dataset: Self.dataDataset, name: entry.name, status: .updated, message: message))
                }
                if dataSummary.records.isEmpty {
                    dataSummary.records.append(SyncRecord(dataset: Self.dataDataset, name: "全部", status: .unchanged))
                }
                if !dryRun {
                    if dataSummary.count(.updated) > 0 || !hadData {
                        let sorted = values.values.sorted {
                            Array($0.name.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.name.unicodeScalars.map(\.value))
                        }
                        try await store.writeJSON(sorted, to: CloudPath.materials)
                    }
                    newModified = page.lastModified ?? lastModified
                }
            } else {
                dataSummary.records.append(SyncRecord(dataset: Self.dataDataset, name: "全部", status: .skipped, message: "页面未变化"))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            dataSummary.records.append(SyncRecord(dataset: Self.dataDataset, name: "整体", status: .failed, message: error.localizedDescription))
        }

        // 2. 图标：云端缺哪些就补哪些；没有缺的就不请求 PRTS
        var iconSummary = SyncSummary(dataset: Self.iconDataset)
        do {
            let existing = try await store.listFileNames(in: CloudPath.materialIconFolder)
            let missing = values.keys.sorted().filter { !existing.contains(CloudPath.materialIconFile($0)) }

            if missing.isEmpty {
                iconSummary.records.append(SyncRecord(dataset: Self.iconDataset, name: "全部", status: .unchanged))
            } else {
                // 一次取回全部"带框"图标文件名，按名字匹配，不再逐个猜测
                let sources = try await client.allImages(prefix: Self.iconPrefix)
                var byKey: [String: String] = [:]
                for source in sources { byKey[Self.key(source)] = source }

                var jobs: [ImageJob] = []
                for name in missing {
                    if let file = byKey[Self.key("\(Self.iconPrefix)\(name).png")] {
                        jobs.append(ImageJob(name: name, wikiFile: file,
                                             cloudPath: "\(CloudPath.materialIconFolder)/\(CloudPath.materialIconFile(name))"))
                    } else {
                        iconSummary.records.append(SyncRecord(dataset: Self.iconDataset, name: name,
                                                              status: .failed, message: "PRTS 上没有该材料的带框图标"))
                    }
                }
                iconSummary.records += await ImageUploader(client: client, store: store, dryRun: dryRun)
                    .upload(jobs, dataset: Self.iconDataset, progress: progress)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            iconSummary.records.append(SyncRecord(dataset: Self.iconDataset, name: "整体", status: .failed, message: error.localizedDescription))
        }

        return ([dataSummary, iconSummary], newModified)
    }

    /// 文件名比较用：空格与下划线等价，不区分大小写
    private static func key(_ filename: String) -> String {
        filename.replacingOccurrences(of: " ", with: "_").lowercased()
    }
}
