import SwiftUI
import AppKit
import LemmaCore

/// Lemma's sample book: a short text on least squares written to show what Lemma does with a mathematical PDF
/// (numbered statements and equations citing each other, proofs, a figure, citations, notation, an index, a step the
/// text calls "easily seen"). It ships inside the app and is copied into the Books library when first opened, so it
/// behaves like any other book and keeps its notes.
@MainActor
extension StudyStore {
    static let sampleBookName = "Least Squares in Twelve Pages"

    var sampleBookFile: URL { downloadedBooksFolder.appendingPathComponent("\(Self.sampleBookName) (Lemma sample).pdf") }

    func openSampleBook() {
        let destination = sampleBookFile
        do {
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let bundled = Codicons.resource("Sample/\(Self.sampleBookName).pdf") else {
                    notify("The sample book is missing from this copy of Lemma.", severity: .warning, source: "Sample Book"); return
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: destination)
                // The Books library watches this folder; it may not have existed when watching began.
                libraries.refresh()
            }
            open(destination)
        } catch {
            notify("Could not open the sample book: \(error.localizedDescription)", severity: .error, source: "Sample Book")
        }
    }
}
