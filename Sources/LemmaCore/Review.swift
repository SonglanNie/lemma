import Foundation

/// The reader's own assessment after attempting a recall.
public enum ReviewGrade: String, Codable, CaseIterable, Sendable {
    case again, hard, good, easy

    public var label: String {
        switch self { case .again: "Again"; case .hard: "Hard"; case .good: "Good"; case .easy: "Easy" }
    }

    public var meaning: String {
        switch self {
        case .again: "I could not reconstruct it."
        case .hard: "I got there, with real effort or a gap."
        case .good: "I recalled it with the reasoning."
        case .easy: "It was immediate."
        }
    }
}

/// When a note returns for recall. Intervals grow with successful recalls (an SM-2 style schedule).
/// It is a study reminder computed from self-assessment, not a measure of mastery.
public struct ReviewSchedule: Codable, Equatable, Sendable {
    public var dueAt: Date
    /// Days until the next review after a successful recall; 0 while relearning.
    public var interval: Double
    public var ease: Double
    public var repetitions: Int
    public var lapses: Int
    public var lastGrade: ReviewGrade?

    public init(dueAt: Date = .now) {
        self.dueAt = dueAt; interval = 0; ease = 2.5; repetitions = 0; lapses = 0
    }
}

public enum ReviewScheduler {
    public static let relearnDelay: TimeInterval = 10 * 60
    public static let maximumInterval: Double = 365
    private static let day: TimeInterval = 86_400

    public static func next(_ schedule: ReviewSchedule, grade: ReviewGrade, now: Date = .now) -> ReviewSchedule {
        var next = schedule
        next.lastGrade = grade
        switch grade {
        case .again:
            if schedule.repetitions > 0 { next.lapses += 1 }
            next.repetitions = 0
            next.interval = 0
            next.ease = max(1.3, schedule.ease - 0.2)
            next.dueAt = now.addingTimeInterval(relearnDelay)
            return next
        case .hard:
            next.interval = schedule.repetitions == 0 ? 1 : max(1, schedule.interval * 1.2)
            next.ease = max(1.3, schedule.ease - 0.15)
        case .good:
            next.interval = schedule.repetitions == 0 ? 1 : schedule.repetitions == 1 ? max(3, schedule.interval + 1) : max(schedule.interval + 1, schedule.interval * schedule.ease)
        case .easy:
            next.interval = schedule.repetitions == 0 ? 4 : max(schedule.interval + 2, schedule.interval * schedule.ease * 1.3)
            next.ease = schedule.ease + 0.15
        }
        next.interval = min(maximumInterval, next.interval.rounded())
        next.repetitions += 1
        next.dueAt = now.addingTimeInterval(next.interval * day)
        return next
    }

    /// The delay each grade would schedule, for labelling the buttons.
    public static func delays(for schedule: ReviewSchedule, now: Date = .now) -> [ReviewGrade: TimeInterval] {
        Dictionary(uniqueKeysWithValues: ReviewGrade.allCases.map { ($0, next(schedule, grade: $0, now: now).dueAt.timeIntervalSince(now)) })
    }

    /// "10 min", "1 d", "3 wk", "4 mo".
    public static func describe(_ delay: TimeInterval) -> String {
        let minutes = delay / 60, days = delay / day
        if minutes < 60 { return "\(max(1, Int(minutes.rounded()))) min" }
        if days < 1 { return "\(Int((minutes / 60).rounded())) h" }
        if days < 14 { return "\(Int(days.rounded())) d" }
        if days < 60 { return "\(Int((days / 7).rounded())) wk" }
        if days < 365 { return "\(Int((days / 30).rounded())) mo" }
        return "\(String(format: "%.1f", days / 365)) yr"
    }
}

extension StudyNote {
    /// In the review deck: scheduled, or marked Revisit in an earlier version.
    public var isInReview: Bool { review != nil || state == .revisit }

    /// Unscheduled Revisit notes are due immediately.
    public var reviewDueAt: Date? { review?.dueAt ?? (state == .revisit ? .distantPast : nil) }

    public func isDue(at date: Date = .now) -> Bool { (reviewDueAt ?? .distantFuture) <= date }

    /// The question shown when recalling: the reader's prompt, else the note's title.
    public var recallQuestion: String {
        let prompt = recallPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? title : prompt
    }

    /// Records a graded recall attempt and schedules the next one.
    public mutating func grade(_ grade: ReviewGrade, now: Date = .now) {
        review = ReviewScheduler.next(review ?? ReviewSchedule(dueAt: now), grade: grade, now: now)
        reviewCount += 1
        lastReviewedAt = now
        state = grade == .again || grade == .hard ? .revisit : .understood
    }
}
