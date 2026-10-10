import Foundation

/// A published work a reference names, found online: its title, authors, where to read it and an open PDF when one exists.
public struct PaperCandidate: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var doi: String?
    public var arxivID: String?
    public var abstract: String?
    public var citationCount: Int?
    /// A PDF anyone may read (arXiv, or an open-access copy).
    public var pdfURL: URL?
    public var pageURL: URL?
    /// How well it matches the reference: authors, year and title words found in the entry (0…1).
    public var confidence: Double

    public init(id: String, title: String, authors: [String] = [], year: Int? = nil, venue: String? = nil, doi: String? = nil, arxivID: String? = nil,
                abstract: String? = nil, citationCount: Int? = nil, pdfURL: URL? = nil, pageURL: URL? = nil, confidence: Double = 0) {
        self.id = id; self.title = title; self.authors = authors; self.year = year; self.venue = venue; self.doi = doi; self.arxivID = arxivID
        self.abstract = abstract; self.citationCount = citationCount; self.pdfURL = pdfURL; self.pageURL = pageURL; self.confidence = confidence
    }

    public var authorLine: String {
        switch authors.count {
        case 0: ""
        case 1: authors[0]
        case 2: authors.joined(separator: " and ")
        default: "\(authors[0]) et al."
        }
    }
}

/// Finds the work a reference list entry names, using public scholarly indexes, only when the reader asks:
/// Crossref matches the whole entry to a DOI, Semantic Scholar adds the abstract and an open-access PDF, arXiv finds preprints.
/// Only the entry's printed text is sent.
public enum PaperLookup {
    public static let userAgent = "Lemma/1.0 (reader for mathematics; macOS)"

    public static func find(entry: String, authors: [String], year: String?, session: URLSession = .shared) async -> [PaperCandidate] {
        let query = String(entry.prefix(400))
        async let crossref = try? crossrefCandidates(query: query, session: session)
        async let arxiv = try? arxivCandidates(query: titleGuess(entry) ?? query, session: session)
        var candidates = (await crossref ?? []) + (await arxiv ?? [])
        // Enrich the best DOI matches with an abstract and an open PDF.
        for index in candidates.indices.prefix(3) where candidates[index].doi != nil {
            if let extra = try? await semanticScholar(doi: candidates[index].doi!, session: session) { candidates[index] = merged(candidates[index], extra) }
        }
        let year = year.flatMap { Int($0.prefix(4)) }
        for index in candidates.indices { candidates[index].confidence = confidence(candidates[index], entry: entry, authors: authors, year: year) }
        // One row per work: a preprint and its published version are merged when their titles agree.
        var unique: [PaperCandidate] = []
        for candidate in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            if let index = unique.firstIndex(where: { normalized($0.title) == normalized(candidate.title) }) { unique[index] = merged(unique[index], candidate) }
            else { unique.append(candidate) }
        }
        return Array(unique.filter { $0.confidence >= 0.25 }.prefix(4))
    }

    // MARK: Services

    static func get(_ url: URL, session: URLSession, accept: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    static func crossrefCandidates(query: String, session: URLSession) async throws -> [PaperCandidate] {
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [URLQueryItem(name: "query.bibliographic", value: query), URLQueryItem(name: "rows", value: "3"),
                                 URLQueryItem(name: "select", value: "DOI,title,author,issued,container-title,score,is-referenced-by-count")]
        return parseCrossref(try await get(components.url!, session: session))
    }

    public static func parseCrossref(_ data: Data) -> [PaperCandidate] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any], let items = message["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let doi = item["DOI"] as? String, let title = (item["title"] as? [String])?.first else { return nil }
            let authors = (item["author"] as? [[String: Any]] ?? []).compactMap { ($0["family"] as? String) ?? ($0["name"] as? String) }
            let year = ((item["issued"] as? [String: Any])?["date-parts"] as? [[Any]])?.first?.first as? Int
            return PaperCandidate(id: "doi:" + doi.lowercased(), title: clean(title), authors: authors, year: year,
                                  venue: (item["container-title"] as? [String])?.first, doi: doi,
                                  citationCount: item["is-referenced-by-count"] as? Int, pageURL: URL(string: "https://doi.org/" + doi))
        }
    }

    static func semanticScholar(doi: String, session: URLSession) async throws -> PaperCandidate {
        let escaped = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        let url = URL(string: "https://api.semanticscholar.org/graph/v1/paper/DOI:\(escaped)?fields=title,year,abstract,openAccessPdf,externalIds,citationCount,venue,authors")!
        return try parseSemanticScholar(try await get(url, session: session)) ?? PaperCandidate(id: "doi:" + doi, title: "")
    }

    public static func parseSemanticScholar(_ data: Data) throws -> PaperCandidate? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let title = json["title"] as? String else { return nil }
        let ids = json["externalIds"] as? [String: Any] ?? [:]
        let arxiv = ids["ArXiv"] as? String
        var pdf = (json["openAccessPdf"] as? [String: Any])?["url"] as? String
        if pdf?.isEmpty == true { pdf = nil }
        if pdf == nil, let arxiv { pdf = "https://arxiv.org/pdf/\(arxiv)" }
        let authors = (json["authors"] as? [[String: Any]] ?? []).compactMap { ($0["name"] as? String)?.split(separator: " ").last.map(String.init) }
        return PaperCandidate(id: (ids["DOI"] as? String).map { "doi:" + $0.lowercased() } ?? "s2:" + title, title: clean(title), authors: authors,
                              year: json["year"] as? Int, venue: (json["venue"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                              doi: ids["DOI"] as? String, arxivID: arxiv, abstract: (json["abstract"] as? String).map(clean),
                              citationCount: json["citationCount"] as? Int, pdfURL: pdf.flatMap(URL.init(string:)))
    }

    static func arxivCandidates(query: String, session: URLSession) async throws -> [PaperCandidate] {
        let words = normalized(query).split(separator: " ").filter { $0.count > 2 }.prefix(10)
        guard words.count >= 2 else { return [] }
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [URLQueryItem(name: "search_query", value: words.map { "ti:\($0)" }.joined(separator: " AND ")),
                                 URLQueryItem(name: "max_results", value: "3")]
        return parseArxiv(try await get(components.url!, session: session, accept: "application/atom+xml"))
    }

    /// Entries of an arXiv Atom feed.
    public static func parseArxiv(_ data: Data) -> [PaperCandidate] {
        let parser = ArxivFeedParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.entries.compactMap { entry in
            guard let id = entry["id"], let title = entry["title"] else { return nil }
            let arxivID = id.replacingOccurrences(of: #"^https?://arxiv\.org/abs/"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
            let authors = (entry["authors"] ?? "").split(separator: "|").compactMap { $0.split(separator: " ").last.map(String.init) }
            return PaperCandidate(id: "arxiv:" + arxivID, title: clean(title), authors: authors, year: entry["published"].flatMap { Int($0.prefix(4)) },
                                  venue: "arXiv", arxivID: arxivID, abstract: entry["summary"].map(clean),
                                  pdfURL: URL(string: "https://arxiv.org/pdf/\(arxivID)"), pageURL: URL(string: "https://arxiv.org/abs/\(arxivID)"))
        }
    }

    /// The title of an arXiv paper, from arXiv's API (nil when offline).
    public static func arxivTitle(_ id: String, session: URLSession = .shared) async -> String? {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [URLQueryItem(name: "id_list", value: id)]
        guard let data = try? await get(components.url!, session: session, accept: "application/atom+xml") else { return nil }
        return parseArxiv(data).first?.title
    }

    // MARK: Matching

    /// The title in a reference entry, after the authors and year: “Hastie, T. and Tibshirani, R. (1990). Generalized Additive Models, …”.
    public static func titleGuess(_ entry: String) -> String? {
        let text = entry.replacingOccurrences(of: "\n", with: " ")
        if let match = text.range(of: #"\(\d{4}[a-z]?\)\.?\s*"#, options: .regularExpression) {
            let rest = text[match.upperBound...]
            let title = rest.split(separator: ".", maxSplits: 1).first.map(String.init) ?? String(rest)
            return title.trimmingCharacters(in: .whitespaces).count > 8 ? title : nil
        }
        // Numbered styles: “[12] A. Author, B. Author, Title of the paper, Journal, 2004.”
        let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.first { $0.split(separator: " ").count >= 4 && !$0.contains(".") }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func confidence(_ candidate: PaperCandidate, entry: String, authors: [String], year: Int?) -> Double {
        let entryWords = Set(normalized(entry).split(separator: " ").map(String.init))
        let titleWords = normalized(candidate.title).split(separator: " ").map(String.init).filter { $0.count > 3 }
        let titleScore = titleWords.isEmpty ? 0 : Double(titleWords.filter(entryWords.contains).count) / Double(titleWords.count)
        let surnames = Set(authors.map { normalized($0) })
        let candidateSurnames = Set(candidate.authors.map { normalized($0) })
        let authorScore = surnames.isEmpty ? 0.5 : Double(surnames.intersection(candidateSurnames).count) / Double(surnames.count)
        let yearScore: Double = year.map { y in candidate.year.map { abs($0 - y) <= 1 ? 1 : 0 } ?? 0.5 } ?? 0.5
        return 0.55 * titleScore + 0.3 * authorScore + 0.15 * yearScore
    }

    static func merged(_ a: PaperCandidate, _ b: PaperCandidate) -> PaperCandidate {
        var result = a
        if result.title.isEmpty { result.title = b.title }
        if result.authors.isEmpty { result.authors = b.authors }
        result.year = result.year ?? b.year
        result.venue = result.venue ?? b.venue
        result.doi = result.doi ?? b.doi
        result.arxivID = result.arxivID ?? b.arxivID
        result.abstract = result.abstract ?? b.abstract
        result.citationCount = result.citationCount ?? b.citationCount
        result.pdfURL = result.pdfURL ?? b.pdfURL
        result.pageURL = result.pageURL ?? b.pageURL
        result.confidence = max(a.confidence, b.confidence)
        return result
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// An arXiv identifier in what the reader typed: “2401.01234”, “arXiv:2401.01234v2”, “https://arxiv.org/abs/math/0406456”.
    public static func arxivID(in text: String) -> String? {
        let patterns = [#"(\d{4}\.\d{4,5})(v\d+)?"#, #"([a-z\-]+(?:\.[A-Z]{2})?/\d{7})(v\d+)?"#]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return String(text[range]).replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
            }
        }
        return nil
    }
}

private final class ArxivFeedParser: NSObject, XMLParserDelegate {
    var entries: [[String: String]] = []
    private var current: [String: String]?
    private var text = ""
    private var authors: [String] = []
    private var inAuthor = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "entry" { current = [:]; authors = [] }
        if name == "author" { inAuthor = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "id", "title", "summary", "published": current?[name] = value
        case "name" where inAuthor: authors.append(value)
        case "author": inAuthor = false
        case "entry":
            current?["authors"] = authors.joined(separator: "|")
            if let current { entries.append(current) }
            current = nil
        default: break
        }
        text = ""
    }
}
