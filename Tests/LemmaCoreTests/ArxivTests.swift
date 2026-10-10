import XCTest
@testable import LemmaCore

final class ArxivTests: XCTestCase {
    static let feed = """
    <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
    <opensearch:totalResults>45</opensearch:totalResults><opensearch:startIndex>20</opensearch:startIndex>
    <entry><id>http://arxiv.org/abs/1706.03762v7</id><published>2017-06-12T17:57:34Z</published><title>Attention Is All
    You Need</title><summary>Attention &amp; sequence modelling.</summary><author><name>Ashish Vaswani</name></author>
    <author><name>Noam Shazeer</name></author><category term="cs.CL"/><category term="cs.LG"/></entry></feed>
    """
    func testStrictIdentifiersPreserveVersionsAndRejectUnrelatedURLs() throws {
        for (text, id) in [
            ("1706.03762v7", "1706.03762v7"), ("arXiv:math/0406456v2", "math/0406456v2"),
            ("https://arxiv.org/pdf/1706.03762v7.pdf?download=true", "1706.03762v7"),
            ("https://arxiv.org/html/2401.12345v2", "2401.12345v2"), ("https://export.arxiv.org/abs/astro-ph/0601001", "astro-ph/0601001")
        ] { XCTAssertEqual(ArxivIdentifier.parse(text), id) }
        for text in ["https://evil.test/1706.03762", "https://arxiv.org.evil.test/abs/1706.03762", "file:///1706.03762", "1706.03762;open", "1706.03762v0", "see paper 1706.03762", "https://arxiv.org/search/?query=1706.03762"] {
            XCTAssertNil(ArxivIdentifier.parse(text), text)
        }
        XCTAssertEqual(ArxivIdentifier.link("math/0406456v2")?.host, "arxiv")
        XCTAssertNil(ArxivIdentifier.link("bad"))
    }
    func testSearchQueriesAndAtomPaging() throws {
        let plain = try XCTUnwrap(URLComponents(url: ArxivSearch.url(query: "ridge regression", start: 20, sort: .submittedDate), resolvingAgainstBaseURL: false))
        let items = Dictionary(plain.queryItems!.map { ($0.name, $0.value!) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(items["search_query"], "all:\"ridge\" AND all:\"regression\"")
        XCTAssertEqual(items["start"], "20"); XCTAssertEqual(items["sortBy"], "submittedDate")
        XCTAssertTrue(ArxivSearch.url(query: "1706.03762v7").absoluteString.contains("id_list=1706.03762v7"))
        let page = try ArxivSearch.parse(Data(Self.feed.utf8))
        XCTAssertEqual(page.total, 45); XCTAssertEqual(page.start, 20); XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.papers.first?.id, "1706.03762v7")
        XCTAssertEqual(page.papers.first?.title, "Attention Is All You Need")
        XCTAssertEqual(page.papers.first?.authors, ["Ashish Vaswani", "Noam Shazeer"])
        XCTAssertEqual(page.papers.first?.categories, ["cs.CL", "cs.LG"])
        XCTAssertEqual(page.papers.first?.pdfURL.absoluteString, "https://arxiv.org/pdf/1706.03762v7")
        XCTAssertThrowsError(try ArxivSearch.parse(Data("not an Atom feed".utf8)))
        XCTAssertThrowsError(try ArxivSearch.parse(Data("<feed><entry><id>http://arxiv.org/api/errors#bad</id><title>Error</title></entry></feed>".utf8)))
    }
    func testNetworkErrorsAreNotEmptyResultsAndSuccessfulQueriesAreCached() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); ArxivTestProtocol.responseStatus = 200 }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ArxivTestProtocol.self]
        let client = ArxivClient(session: URLSession(configuration: config), minimumInterval: 0)
        ArxivTestProtocol.responseStatus = 200
        let first = try await client.search(query: "attention", cacheFolder: root)
        ArxivTestProtocol.responseStatus = 503
        let cached = try await client.search(query: "attention", cacheFolder: root)
        XCTAssertEqual(cached, first)
        do { _ = try await client.search(query: "unavailable", cacheFolder: root); XCTFail("An HTTP failure must remain an error") }
        catch { XCTAssertEqual((error as? URLError)?.code, .badServerResponse) }
    }
}

private final class ArxivTestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseStatus = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus, httpVersion: nil, headerFields: ["Content-Type": "application/atom+xml"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(ArxivTests.feed.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
