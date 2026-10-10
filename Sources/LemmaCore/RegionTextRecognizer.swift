import Foundation
import ImageIO
import Vision

/// Marks text derived from a source image and subsequently reviewed by the reader.
public enum SourceTextOrigin: String, Codable, Sendable {
    case ocr
}

public enum RegionTextRecognitionError: Error, LocalizedError {
    case invalidImage

    public var errorDescription: String? {
        "The source image could not be read. Capture the passage again."
    }
}

public enum RegionTextRecognizer {
    /// Recognizes prose in an already oriented source PNG, without changing the PDF.
    /// The caller must review symbols, equations, and reading order against the image.
    public static func recognize(png: Data) async throws -> String {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw RegionTextRecognitionError.invalidImage
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        // The reader's own languages first (as set in System Settings), then English, the language of most
        // mathematics; Vision's automatic detection still runs. Only languages Vision supports are passed.
        let supportedLanguages = request.supportedRecognitionLanguages
        var wanted = Locale.preferredLanguages.map { Locale.Language(identifier: $0) }
        wanted.append(Locale.Language(identifier: "en-US"))
        var languages: [Locale.Language] = []
        for language in wanted {
            let match = supportedLanguages.first { $0 == language }
                ?? supportedLanguages.first { $0.languageCode == language.languageCode && $0.script == language.script }
                ?? supportedLanguages.first { $0.languageCode == language.languageCode }
            if let match, !languages.contains(match) { languages.append(match) }
        }
        if !languages.isEmpty { request.recognitionLanguages = Array(languages.prefix(6)) }

        let observations = try await request.perform(on: png, orientation: .up)
        try Task.checkCancellation()
        // Retain Vision's observation order and line breaks. Do not infer paragraphs
        // or mathematical structure that are absent from the recognition result.
        return observations.compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
