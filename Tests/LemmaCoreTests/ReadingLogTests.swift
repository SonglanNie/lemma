import XCTest
@testable import LemmaCore

/// Reading time per page and day, and outline titles repaired from their pages.
final class ReadingLogTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    func testRecordsPagesDaysAndStreaks() {
        let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 10))!
        var log = ReadingLog()
        log.record(25, onPage: 10, at: monday, calendar: calendar)
        log.record(10, onPage: 11, at: monday, calendar: calendar)
        log.record(70, onPage: 11, at: monday.addingTimeInterval(86_400), calendar: calendar)
        log.record(90, onPage: 12, at: monday.addingTimeInterval(2 * 86_400), calendar: calendar)
        log.record(700, onPage: 13, at: monday, calendar: calendar)
        XCTAssertNil(log.pageSeconds["13"], "Implausible chunks are ignored.")
        XCTAssertEqual(log.seconds(onPage: 11), 80)
        XCTAssertTrue(log.isRead(10)); XCTAssertTrue(log.isRead(11)); XCTAssertFalse(log.isRead(9))
        XCTAssertEqual(log.readCount(in: 10..<12), 2)
        XCTAssertEqual(log.pagesRead, 3)
        XCTAssertEqual(log.totalSeconds, 195)
        XCTAssertEqual(log.daySeconds["2026-09-28"], 35)
        let wednesday = monday.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(log.streak(endingAt: wednesday, calendar: calendar), 2, "Monday has less than a minute, so the streak starts Tuesday.")
        XCTAssertEqual(log.streak(endingAt: wednesday.addingTimeInterval(86_400), calendar: calendar), 2, "A streak survives until today ends.")
        XCTAssertEqual(log.streak(endingAt: wednesday.addingTimeInterval(3 * 86_400), calendar: calendar), 0)
        let week = log.days(7, endingAt: wednesday, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.seconds, 90)
        XCTAssertEqual(week.map(\.seconds).reduce(0, +), 195)
        XCTAssertEqual(ReadingSummary.days([log, log], count: 1, endingAt: wednesday, calendar: calendar).first?.seconds, 180)
    }

    func testDescriptions() {
        XCTAssertEqual(ReadingLog.describe(40), "40 s")
        XCTAssertEqual(ReadingLog.describe(12 * 60 + 20), "12 min")
        XCTAssertEqual(ReadingLog.describe(3_900), "1 h 05 min")
        XCTAssertEqual(ReadingLog.describeShort(0), "0 min")
        XCTAssertEqual(ReadingLog.describeShort(30), "< 1 min")
        XCTAssertEqual(ReadingLog.describeShort(3_900), "1 h 05")
    }

    func testOutlineTitlesTakeTheirPagesSpacing() {
        XCTAssertEqual(OutlineTitle.repaired("3.4.1Ridge Regression"), "3.4.1 Ridge Regression")
        XCTAssertEqual(OutlineTitle.repaired("12 Support Vector Machines andFlexible Discriminants",
                                              pageText: "12\nSupport Vector Machines and\nFlexible Discriminants\n12.1 Introduction"),
                       "12 Support Vector Machines and Flexible Discriminants")
        XCTAssertEqual(OutlineTitle.repaired("3.4.3 Discussion: Subset Selection, Ridge Regressionand the Lasso",
                                              pageText: "3.4.3 Discussion: Subset Selection, Ridge Regression\nand the Lasso\nIn this section"),
                       "3.4.3 Discussion: Subset Selection, Ridge Regression and the Lasso")
        XCTAssertEqual(OutlineTitle.repaired("10.4 Exponential Loss and AdaBoost", pageText: "10.4 Exponential Loss and AdaBoost\nWe now"),
                       "10.4 Exponential Loss and AdaBoost", "Words the page prints joined stay joined.")
        XCTAssertEqual(OutlineTitle.repaired("4.4 Logistic Regression", pageText: "unrelated text"), "4.4 Logistic Regression")
        XCTAssertEqual(OutlineTitle.repaired("2.3 Least Squares and Nearest Neighbors", pageText: "Least Squares and Near-\nest Neighbors"),
                       "2.3 Least Squares and Nearest Neighbors", "A hyphenated line break is not taken as spacing.")
        XCTAssertEqual(OutlineTitle.repaired("Preface to the Second Edition"), "Preface to the Second Edition")
    }
}
