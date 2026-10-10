import SwiftUI
import Charts
import LemmaCore

@MainActor
extension StudyStore {
    /// Pages of a top-level outline entry: from its page to the next chapter's.
    func chapterRange(of entry: OutlineEntry) -> Range<Int>? {
        guard let start = entry.pageIndex, let index = outline.firstIndex(where: { $0.id == entry.id }) else { return nil }
        let end = outline[(index + 1)...].compactMap(\.pageIndex).first { $0 > start } ?? (document?.pageCount ?? start + 1)
        return start..<max(start + 1, end)
    }

    /// Fraction of a chapter's pages read, when anything has been recorded for this book.
    func chapterProgress(of entry: OutlineEntry) -> Double? {
        guard let log = workspace?.readingLog, !log.pageSeconds.isEmpty, let range = chapterRange(of: entry) else { return nil }
        return Double(log.readCount(in: range)) / Double(max(range.count, 1))
    }

    /// Seconds read today in this book, including time not yet written.
    var secondsToday: Double {
        guard let workspace else { return 0 }
        return workspace.readingLog.seconds(on: .now) + (tracker?.pendingSeconds(for: workspace.id) ?? 0)
    }
}

/// A small ring showing how much of a chapter has been read.
struct ProgressRing: View {
    let value: Double
    var size: CGFloat = 11

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1.6)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(value >= 0.995 ? Color.green : Color.lemmaOlive, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(Int((value * 100).rounded())) percent read")
    }
}

/// Reading time for the last two weeks, the streak and this book's progress.
struct ReadingStatsView: View {
    @Bindable var store: StudyStore

    var body: some View {
        let log = store.workspace?.readingLog ?? ReadingLog()
        let days = log.days(14)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading").font(.headline)
                Spacer()
                Text(store.workspace?.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 18) {
                stat(ReadingLog.describe(store.secondsToday), "today")
                stat("\(log.streak()) \(log.streak() == 1 ? "day" : "days")", "streak")
                stat(ReadingLog.describe(log.totalSeconds), "in this book")
            }
            ReadingBarChart(days: days).frame(height: 90)
            if let count = store.document?.pageCount, count > 0 {
                let read = log.pagesRead
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(read), total: Double(count)).tint(Color.lemmaOlive)
                    Text("\(read) of \(count) pages read (\(Int((Double(read) / Double(count) * 100).rounded())) %) · a page counts after \(Int(ReadingLog.readThreshold)) s of attention")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Counted only while Lemma is in front and you are active. Stored with the book, on this Mac.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 340)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Minutes per day as bars; today in olive.
struct ReadingBarChart: View {
    let days: [(date: Date, seconds: Double)]

    var body: some View {
        Chart {
            ForEach(Array(days.enumerated()), id: \.offset) { offset, day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.seconds / 60))
                    .foregroundStyle(offset == days.count - 1 ? Color.lemmaOlive : Color.lemmaOlive.opacity(0.45))
                    .cornerRadius(2)
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
            AxisValueLabel { if let minutes = value.as(Double.self) { Text("\(Int(minutes))m").font(.system(size: 9)) } }
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: days.count > 7 ? 2 : 1)) { value in
            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true).font(.system(size: 9))
        } }
        .accessibilityLabel("Reading time per day")
    }
}
