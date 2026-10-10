import XCTest
@testable import LemmaCore

final class TermExtractionTests: XCTestCase {
    private func candidates(_ text: String, emphasised words: [String]) -> [TermCandidate] {
        let string = text as NSString
        let runs = words.map { word in
            EmphasisRun(text: word, range: string.range(of: word), style: .italic, relativeSize: 1)
        }
        return TermCandidates.candidates(runs: runs, pageText: text)
    }

    func testNarrativeTitlesAndRemoteNamingVerbsAreNotDefinitions() {
        let passages: [(String, String)] = [
            ("I read Gulliver’s Travels on holiday.", "Gulliver’s Travels"),
            ("He subscribed to a magazine called Science News-Letter for years.", "Science News-Letter"),
            ("She called to interview me for her book Master of the Game.", "Master of the Game"),
            ("A stockbroker named Jay Regan, who had read Beat the Market, telephoned.", "Beat the Market"),
            ("He called upon the Times board to accept his allies.", "Times"),
            ("They bankrolled a production called Redline. It was a film.", "Redline"),
            ("He ramped up distribution of what were now called Daily Observations.", "Daily Observations"),
        ]
        for (text, word) in passages {
            XCTAssertTrue(BookTerms.table(candidates(text, emphasised: [word]).map { (0, $0) }, index: []).isEmpty, word)
        }
        let text = "The rational figure known as Homo economicus is central to the model."
        let terms = BookTerms.table(candidates(text, emphasised: ["Homo economicus"]).map { (0, $0) }, index: [])
        XCTAssertEqual(terms.map(\.term), ["homo economicus"])
        let distribution = "This probability distribution is called the normal distribution."
        XCTAssertEqual(BookTerms.table(candidates(distribution, emphasised: ["normal distribution"]).map { (0, $0) }, index: []).map(\.term), ["normal distribution"])
    }

    func testFrenchDefinitionCuesAndExplicitHandoutTitles() {
        let text = "On parle de système bouclé lorsque les sorties participent à la commande.\nCe système est dit stable si sa trajectoire reste bornée."
        let terms = BookTerms.table(candidates(text, emphasised: ["système bouclé", "stable"]).map { (11, $0) }, index: [])
        XCTAssertEqual(terms.map(\.term), ["système bouclé", "stable"])
        XCTAssertTrue(terms.allSatisfy(\.definitional))

        let handout = "Définition 2.10 \u{2014} Fonction de Lyapunov. Soit V une fonction.\nDéfinition 2.15 \u{2014} Observabilité. Le système est observable si…\nDefinition 3.1 (Open set). A subset is open if…"
        let labelled = TermCandidates.candidates(runs: [], pageText: handout)
        XCTAssertEqual(labelled.map(\.surface), ["Fonction de Lyapunov", "Observabilité", "Open set"])
        XCTAssertTrue(labelled.allSatisfy(\.definitional))
        for term in labelled {
            XCTAssertEqual((handout as NSString).substring(with: term.range), term.surface, "Source navigation keeps UTF-16 ranges.")
        }
    }

    func testIndexCorroborationUsesTheListedOccurrenceAndDeduplicatesTitleRuns() {
        let text = "We study the nearest neighbour method for prediction."
        let earlier = candidates(text, emphasised: ["nearest neighbour"]).map { (pageIndex: 2, candidate: $0) }
        let later = candidates(text, emphasised: ["nearest neighbour"]).map { (pageIndex: 20, candidate: $0) }
        let index = [BookIndexEntry(id: 0, term: "Nearest neighbour", locators: [PageSpan(first: "21")], pageIndex: 100)]
        let table = BookTerms.table(earlier + later, index: index)
        XCTAssertEqual(table.map(\.pageIndex), [20])
        XCTAssertEqual(table.first?.occurrences, 2)

        let title = "Définition 2.15 \u{2014} Observabilité. Le système est observable si…"
        let terms = candidates(title, emphasised: ["Observabilité"])
        XCTAssertEqual(terms.count, 1)
        XCTAssertTrue(terms[0].definitional)
    }
}
