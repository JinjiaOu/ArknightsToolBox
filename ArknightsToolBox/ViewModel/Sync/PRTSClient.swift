//
//  PRTSClient.swift
//  ArknightsToolBox
//
//  统一的 PRTS Wiki 请求层：全局限速、重试退避、结果缓存。
//  对应 ArknightsResourceTool 的 client.py。
//

import Foundation

enum PRTSError: LocalizedError {
    case missing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missing(let message), .failed(let message): return message
        }
    }
}

actor PRTSClient {
    struct Options {
        var apiURL = "https://prts.wiki/api.php"
        var userAgent = "ArknightsToolBox/2.0 (iOS)"
        var timeout: TimeInterval = 30
        var retries = 3
        var interval: TimeInterval = 0.4     // 相邻两次 API 请求的最小间隔（所有并发任务共用）
    }

    private let options: Options
    private let session: URLSession
    private var nextSlot: TimeInterval = 0

    private var wikitextCache: [String: String] = [:]
    private var wikitextOrder: [String] = []          // 缓存插入顺序，用于限制内存
    private let wikitextCacheLimit = 48
    private var imagesCache: [String: [String]] = [:]
    private var allImagesCache: [String: [String]] = [:]

    init(options: Options = Options()) {
        self.options = options
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = options.timeout
        config.timeoutIntervalForResource = options.timeout * 2
        config.httpAdditionalHeaders = ["User-Agent": options.userAgent]
        session = URLSession(configuration: config)
    }

    func clearCache() {
        wikitextCache.removeAll()
        wikitextOrder.removeAll()
        imagesCache.removeAll()
        allImagesCache.removeAll()
    }

    // MARK: - 连通性检查

    /// 同步开始前确认能连上 PRTS：最多两次、每次 15 秒，失败立即给出明确提示，
    /// 避免后面每个步骤都等满超时和重试。
    @discardableResult
    func checkConnection() async throws -> String? {
        let url = try apiURL(["action": "query", "meta": "siteinfo", "curtimestamp": "1"])
        var lastError: Error?
        for _ in 0..<2 {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.setValue(options.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = PRTSError.failed("HTTP \(http.statusCode)")
                    continue
                }
                // 服务器当前时间，作为本次检查的时间基准（比本机时钟可靠）
                return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["curtimestamp"] as? String
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        let reason = lastError?.localizedDescription ?? "未知原因"
        throw PRTSError.failed("无法连接 PRTS（prts.wiki）：\(reason)。请检查网络或代理后重试")
    }

    // MARK: - 基础请求

    /// 预约下一个请求时段。没有 await，因此在 actor 内是原子的。
    private func reserveSlot() -> TimeInterval {
        let now = ProcessInfo.processInfo.systemUptime
        let start = max(now, nextSlot)
        nextSlot = start + options.interval
        return start - now
    }

    private func request(_ url: URL, rateLimited: Bool) async throws -> Data {
        try await perform(url, rateLimited: rateLimited, ifModifiedSince: nil).data
    }

    private struct Fetched {
        let data: Data
        let notModified: Bool
        let lastModified: String?
    }

    private func perform(_ url: URL, rateLimited: Bool, ifModifiedSince: String?) async throws -> Fetched {
        var lastError: Error = PRTSError.failed("请求失败：\(url.absoluteString)")

        for attempt in 0..<options.retries {
            try Task.checkCancellation()
            if rateLimited {
                let delay = reserveSlot()
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }

            let started = Date()
            do {
                var urlRequest = URLRequest(url: url)
                if let ifModifiedSince {
                    urlRequest.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
                    // 不让 URLSession 用本地缓存替我们处理 304，这样才能直接知道"页面没变"
                    urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
                }
                let (data, response) = try await session.data(for: urlRequest)
                log(url, "✓", started, "\((response as? HTTPURLResponse)?.statusCode ?? 0) \(data.count)B")
                if let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 200..<300:
                        return Fetched(data: data, notModified: false, lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
                    case 304 where ifModifiedSince != nil:
                        return Fetched(data: Data(), notModified: true, lastModified: ifModifiedSince)
                    case 429:
                        lastError = PRTSError.failed("触发速率限制（429）")
                        try await backoff(seconds: 5 * Double(attempt + 1))
                        continue
                    case 403, 408, 500..<600:
                        // PRTS 前面有 CDN，偶尔会临时返回 403/408，按服务器错误处理
                        lastError = PRTSError.failed("服务器返回 \(http.statusCode)")
                        try await backoff(seconds: min(pow(2, Double(attempt)), 8))
                        continue
                    case 404:
                        throw PRTSError.missing("资源不存在：\(url.lastPathComponent)")
                    default:
                        throw PRTSError.failed("HTTP \(http.statusCode)：\(url.absoluteString)")
                    }
                }
                return Fetched(data: data, notModified: false, lastModified: nil)
            } catch let error as PRTSError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                log(url, "✗", started, "第 \(attempt + 1) 次 \(error.code.rawValue) \(error.localizedDescription)")
                if error.code == .cancelled { throw CancellationError() }
                if error.code == .notConnectedToInternet { throw PRTSError.failed("网络未连接") }
                lastError = error
                try await backoff(seconds: min(pow(2, Double(attempt)), 8))
            }
        }
        throw PRTSError.failed("请求失败：\(lastError.localizedDescription)")
    }

    /// Debug 下打印每个请求的耗时，便于定位网络问题
    private func log(_ url: URL, _ mark: String, _ started: Date, _ detail: String) {
        #if DEBUG
        let query = (url.query ?? url.lastPathComponent).removingPercentEncoding ?? ""
        let brief = query.count > 70 ? String(query.prefix(70)) + "…" : query
        print("[PRTS] \(mark) \(String(format: "%.1f", Date().timeIntervalSince(started)))s \(detail)  \(url.host ?? "") \(brief)")
        #endif
    }

    private func backoff(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func apiURL(_ params: [String: String]) throws -> URL {
        guard var components = URLComponents(string: options.apiURL) else {
            throw PRTSError.failed("API 地址无效")
        }
        var all = params
        all["format"] = "json"
        components.queryItems = all.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLQueryItem 不会编码 "+"，页面名里出现时会被服务器当作空格
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw PRTSError.failed("无法构造请求地址") }
        return url
    }

    private func api(_ params: [String: String]) async throws -> [String: Any] {
        let data = try await request(try apiURL(params), rateLimited: true)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PRTSError.failed("响应不是有效的 JSON")
        }
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? String ?? ""
            let info = error["info"] as? String ?? "未知错误"
            if code == "missingtitle" { throw PRTSError.missing(info) }
            throw PRTSError.failed("\(code)：\(info)")
        }
        return json
    }

    /// 带 continue 的列表接口，自动翻页
    private func listing(_ type: String, params: [String: String], itemKey: String) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var continuation: [String: String] = [:]
        while true {
            let json = try await api(params.merging(["action": "query", "list": type]) { $1 }
                .merging(continuation) { $1 })
            guard let list = (json["query"] as? [String: Any])?[itemKey] as? [[String: Any]] else {
                throw PRTSError.failed("列表响应缺少 \(itemKey)")
            }
            items += list
            guard let next = json["continue"] as? [String: Any] else { break }
            continuation = next.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
        }
        return items
    }

    // MARK: - 业务接口

    /// 分类成员页面名
    func category(_ name: String) async throws -> [String] {
        let items = try await listing("categorymembers",
                                      params: ["cmtitle": "Category:\(name)", "cmlimit": "max"],
                                      itemKey: "categorymembers")
        return items.compactMap { $0["title"] as? String }
    }

    /// 以指定前缀开头的全部文件名
    func allImages(prefix: String) async throws -> [String] {
        if let cached = allImagesCache[prefix] { return cached }
        let items = try await listing("allimages",
                                      params: ["aiprefix": prefix, "ailimit": "max"],
                                      itemKey: "allimages")
        let names = items.compactMap { $0["name"] as? String }
        allImagesCache[prefix] = names
        return names
    }

    /// 页面源码
    func wikitext(_ name: String) async throws -> String {
        if let cached = wikitextCache[name] { return cached }
        guard let content = try await wikitexts([name])[name] else {
            throw PRTSError.missing("页面不存在或无源码：\(name)")
        }
        wikitextCache[name] = content
        wikitextOrder.append(name)
        if wikitextOrder.count > wikitextCacheLimit {
            wikitextCache.removeValue(forKey: wikitextOrder.removeFirst())
        }
        return content
    }

    /// 批量取页面源码（每次请求最多 25 个页面）。不存在或没有内容的页面不会出现在结果里。
    func wikitexts(_ titles: [String]) async throws -> [String: String] {
        var result: [String: String] = [:]
        for batch in titles.chunks(ofSize: 25) {
            let json = try await api([
                "action": "query", "prop": "revisions", "titles": batch.joined(separator: "|"),
                "rvslots": "main", "rvprop": "content"
            ])
            guard let query = json["query"] as? [String: Any] else {
                throw PRTSError.failed("页面响应异常")
            }
            var original: [String: String] = [:]
            for entry in query["normalized"] as? [[String: Any]] ?? [] {
                if let from = entry["from"] as? String, let to = entry["to"] as? String { original[to] = from }
            }
            for page in (query["pages"] as? [String: Any] ?? [:]).values {
                guard let page = page as? [String: Any], let title = page["title"] as? String,
                      page["missing"] == nil,
                      let revision = (page["revisions"] as? [[String: Any]])?.first else { continue }
                let content = (revision["slots"] as? [String: Any]).flatMap { ($0["main"] as? [String: Any])?["*"] as? String }
                    ?? revision["*"] as? String
                    ?? ""
                if !content.isEmpty { result[original[title] ?? title] = content }
            }
        }
        return result
    }

    /// 指定时间之后被编辑、新建、移动或删除的页面标题（只含正文命名空间）。
    /// 一次请求就能知道哪些页面变了，比逐页查版本号快得多。
    func changedPages(since: Date) async throws -> Set<String> {
        let formatter = ISO8601DateFormatter()
        var titles = Set<String>()
        var continuation: [String: String] = [:]
        while true {
            var params = [
                "action": "query", "list": "recentchanges",
                "rcnamespace": "0", "rctype": "edit|new|log",
                "rcprop": "title", "rclimit": "max",
                "rcend": formatter.string(from: since)
            ]
            params.merge(continuation) { $1 }
            let json = try await api(params)
            guard let changes = (json["query"] as? [String: Any])?["recentchanges"] as? [[String: Any]] else {
                throw PRTSError.failed("最近更改响应异常")
            }
            titles.formUnion(changes.compactMap { $0["title"] as? String })
            guard let next = json["continue"] as? [String: Any] else { break }
            continuation = next.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
        }
        return titles
    }

    /// 批量查询页面的最新版本号（每 50 个页面一次请求）。页面不存在记为 0。
    /// 用于判断页面自上次同步后是否被编辑过。
    func revisionIDs(of titles: [String], onBatch: ((_ done: Int, _ total: Int) -> Void)? = nil) async throws -> [String: Int] {
        var result: [String: Int] = [:]
        var done = 0
        for batch in titles.chunks(ofSize: 50) {
            let json = try await api([
                "action": "query", "prop": "revisions", "rvprop": "ids",
                "titles": batch.joined(separator: "|")
            ])
            guard let query = json["query"] as? [String: Any] else {
                throw PRTSError.failed("版本查询响应异常")
            }
            // 服务器会规范化标题（如首字母大写、下划线），需要映射回请求时的名字
            var original: [String: String] = [:]
            for entry in query["normalized"] as? [[String: Any]] ?? [] {
                if let from = entry["from"] as? String, let to = entry["to"] as? String { original[to] = from }
            }
            for page in (query["pages"] as? [String: Any] ?? [:]).values {
                guard let page = page as? [String: Any], let title = page["title"] as? String else { continue }
                let requested = original[title] ?? title
                let revision = ((page["revisions"] as? [[String: Any]])?.first)?["revid"] as? Int
                result[requested] = page["missing"] != nil ? 0 : (revision ?? 0)
            }
            done += batch.count
            onBatch?(done, titles.count)
        }
        return result
    }

    /// 页面内嵌图片文件名
    func images(of page: String) async throws -> [String] {
        if let cached = imagesCache[page] { return cached }
        let json = try await api(["action": "parse", "page": page, "prop": "images"])
        guard let images = (json["parse"] as? [String: Any])?["images"] as? [String] else {
            throw PRTSError.failed("图片列表响应异常：\(page)")
        }
        imagesCache[page] = images
        return images
    }

    /// 文件的真实下载地址
    func imageURL(filename: String) async throws -> URL {
        let json = try await api([
            "action": "query", "titles": "File:\(filename)", "prop": "imageinfo", "iiprop": "url"
        ])
        guard let pages = (json["query"] as? [String: Any])?["pages"] as? [String: Any],
              let page = pages.values.first as? [String: Any] else {
            throw PRTSError.failed("图片响应异常：\(filename)")
        }
        if page["missing"] != nil { throw PRTSError.missing("图片不存在：\(filename)") }
        guard let urlString = ((page["imageinfo"] as? [[String: Any]])?.first)?["url"] as? String,
              let url = URL(string: urlString) else {
            throw PRTSError.failed("图片响应没有下载链接：\(filename)")
        }
        return url
    }

    /// 取一个普通网页（非 API）。带 If-Modified-Since 且页面没变时返回 nil。
    func page(path: String, ifModifiedSince: String? = nil) async throws -> (html: String, lastModified: String?)? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://prts.wiki/w/\(encoded)") else {
            throw PRTSError.failed("页面地址无效：\(path)")
        }
        let delay = reserveSlot()
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let fetched = try await perform(url, rateLimited: false, ifModifiedSince: ifModifiedSince)
        if fetched.notModified { return nil }
        guard let html = String(data: fetched.data, encoding: .utf8), !html.isEmpty else {
            throw PRTSError.failed("页面内容为空：\(path)")
        }
        return (html, fetched.lastModified)
    }

    /// 下载文件内容（不占用 API 限速）
    func download(_ url: URL) async throws -> Data {
        try await request(url, rateLimited: false)
    }
}
