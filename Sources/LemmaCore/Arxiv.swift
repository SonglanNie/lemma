import Foundation
import CryptoKit

public enum ArxivIdentifier {
    /// Accept an identifier or an arXiv abstract/PDF/HTML URL. Keep the version the reader chose.
    public static func parse(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("arxiv:") { value = String(value.dropFirst(6)) }
        if let url = URL(string: value), let host = url.host {
            guard ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].contains(host.lowercased()), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            let path = url.path
            guard let prefix = ["/abs/", "/pdf/", "/html/"].first(where: { path.hasPrefix($0) }) else { return nil }
            value = String(path.dropFirst(prefix.count))
            if value.hasSuffix(".pdf") { value = String(value.dropLast(4)) }
        }
        let pattern = #"^(?:\d{4}\.\d{4,5}|[a-z][a-z\-]*(?:\.[A-Z]{2})?/\d{7})(?:v[1-9]\d*)?$"#
        return value.range(of: pattern, options: .regularExpression) != nil ? value : nil
    }
    public static func base(_ id: String) -> String { id.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression) }
    public static func link(_ id: String) -> URL? {
        guard let id = parse(id) else { return nil }
        var url = URLComponents(); url.scheme = "lemma"; url.host = "arxiv"
        url.queryItems = [URLQueryItem(name: "id", value: id)]
        return url.url
    }
}

public struct ArxivPaper: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var authors: [String]
    public var summary: String
    public var published: String
    public var categories: [String]
    public var pdfURL: URL { URL(string: "https://arxiv.org/pdf/\(id)")! }
    public var pageURL: URL { URL(string: "https://arxiv.org/abs/\(id)")! }
}

public struct ArxivSearchPage: Codable, Equatable, Sendable {
    public var papers: [ArxivPaper]
    public var total: Int
    public var start: Int
    public var hasMore: Bool { !papers.isEmpty && start + papers.count < total }
}

public enum ArxivSort: String, CaseIterable, Sendable {
    case relevance, submittedDate
    public var label: String { self == .relevance ? "Relevance" : "Newest" }
}

public enum ArxivSearch {
    public static func url(query: String, start: Int = 0, sort: ArxivSort = .relevance) -> URL {
        var url = URLComponents(string: "https://export.arxiv.org/api/query")!
        if let id = ArxivIdentifier.parse(query) { url.queryItems = [URLQueryItem(name: "id_list", value: id)] }
        else {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            // Advanced arXiv fields (au:, ti:, cat:…) can be entered directly; ordinary words search all fields.
            let search = text.contains(":") ? text : text.split(whereSeparator: \.isWhitespace).map {
                "all:\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }.joined(separator: " AND ")
            url.queryItems = [URLQueryItem(name: "search_query", value: search), URLQueryItem(name: "sortBy", value: sort.rawValue), URLQueryItem(name: "sortOrder", value: "descending")]
        }
        url.queryItems! += [URLQueryItem(name: "start", value: String(max(0, start))), URLQueryItem(name: "max_results", value: "20")]
        return url.url!
    }

    public static func parse(_ data: Data) throws -> ArxivSearchPage {
        let reader = ArxivSearchFeed()
        let xml = XMLParser(data: data); xml.delegate = reader
        guard xml.parse(), !reader.isError else { throw URLError(.cannotParseResponse) }
        return ArxivSearchPage(papers: reader.papers, total: reader.total ?? reader.papers.count, start: reader.start)
    }
}

private final class ArxivSearchFeed: NSObject, XMLParserDelegate {
    var papers: [ArxivPaper] = []
    var total: Int?
    var start = 0
    var isError = false
    private var paper: ArxivPaper?
    private var text = ""
    private var inAuthor = false
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if element == "entry" { paper = ArxivPaper(id: "", title: "", authors: [], summary: "", published: "", categories: []) }
        if element == "author" { inAuthor = true }
        if element == "category", let term = attributes["term"] { paper?.categories.append(term) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "opensearch:totalResults": total = Int(value)
        case "opensearch:startIndex": start = Int(value) ?? 0
        case "id" where paper != nil:
            if value.contains("/api/errors") { isError = true }
            paper?.id = ArxivIdentifier.parse(value) ?? ""
        case "title": paper?.title = value
        case "summary": paper?.summary = value
        case "published": paper?.published = value
        case "name" where inAuthor: paper?.authors.append(value)
        case "author": inAuthor = false
        case "entry":
            if let paper, !paper.id.isEmpty, !paper.title.isEmpty { papers.append(paper) }
            self.paper = nil
        default: break
        }
        text = ""
    }
}

/// Explicit searches only, with a one-day disk cache and the spacing requested by arXiv's API documentation.
public actor ArxivClient {
    public static let shared = ArxivClient()
    private var nextRequest = Date.distantPast
    private let minimumInterval: TimeInterval
    private let session: URLSession
    public init(session: URLSession = .shared, minimumInterval: TimeInterval = 3) { self.session = session; self.minimumInterval = minimumInterval }
    private struct Cache: Codable { var date: Date; var page: ArxivSearchPage }

    public func search(query: String, start: Int = 0, sort: ArxivSort = .relevance, cacheFolder: URL) async throws -> ArxivSearchPage {
        let url = ArxivSearch.url(query: query, start: start, sort: sort)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = cacheFolder.appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: file), let cache = try? JSONDecoder().decode(Cache.self, from: data), Date().timeIntervalSince(cache.date) < 86400 { return cache.page }
        let scheduled = max(Date(), nextRequest)
        nextRequest = scheduled.addingTimeInterval(minimumInterval)
        if scheduled > Date() { try await Task.sleep(for: .seconds(scheduled.timeIntervalSinceNow)) }
        try Task.checkCancellation()
        let data = try await PaperLookup.get(url, session: session, accept: "application/atom+xml")
        let page = try ArxivSearch.parse(data)
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(Cache(date: .now, page: page)) { try? encoded.write(to: file, options: .atomic) }
        return page
    }
}
