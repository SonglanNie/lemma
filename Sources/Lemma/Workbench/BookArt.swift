import SwiftUI
import AppKit
import PDFKit
import LemmaCore

// Book art shared by the Welcome page, the Catalog and the library: typographic covers for books Lemma has not
// downloaded yet, and page-one thumbnails of the reader's own books, rendered off the main thread.

/// A cover drawn for a catalog book: the subject's colour, the title in the serif face, the authors in small capitals
/// and the subject's sign in the corner, as a series of textbooks would be dressed.
struct GeneratedBookCover: View {
    let title: String
    var subtitle: String? = nil
    let authors: String
    let subject: String
    var width: CGFloat = 96

    var body: some View {
        let palette = CoverPalette(subject: subject)
        let height = width * 4 / 3
        let scale = width / 96
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            // The subject's sign, large and faint, bleeding off the lower right corner.
            Text(palette.sign)
                .font(.system(size: 78 * scale, weight: .regular, design: .serif))
                .foregroundStyle(palette.ink.opacity(0.14))
                .frame(width: width, height: height, alignment: .bottomTrailing)
                .offset(x: 10 * scale, y: 14 * scale)
            // A band, as on a series' spine.
            Rectangle().fill(palette.ink.opacity(0.85)).frame(width: width, height: 2.5 * scale).offset(y: height * 0.64)
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text(subject.uppercased())
                    .font(.system(size: 5.6 * scale, weight: .semibold)).tracking(0.8 * scale)
                    .foregroundStyle(palette.ink.opacity(0.75)).lineLimit(1)
                Text(title)
                    .font(.system(size: 11.5 * scale, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.ink).lineLimit(4).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 7.2 * scale, weight: .regular, design: .serif)).italic()
                        .foregroundStyle(palette.ink.opacity(0.8)).lineLimit(2).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Text(authors)
                    .font(.system(size: 6.4 * scale, weight: .medium, design: .serif)).textCase(.uppercase).tracking(0.3 * scale)
                    .foregroundStyle(palette.ink.opacity(0.85)).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 9 * scale).padding(.top, 10 * scale).padding(.bottom, 8 * scale)
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3 * scale, style: .continuous).strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
        .overlay(alignment: .leading) {
            // The spine's crease catches the light.
            LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 5 * scale)
        }
        .shadow(color: .black.opacity(0.22), radius: 3 * scale, y: 2 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)\(subtitle.map { ": " + $0 } ?? ""), \(authors)")
    }
}

/// The colours and sign of a subject's covers.
struct CoverPalette {
    let top: Color
    let bottom: Color
    let ink: Color
    let sign: String

    init(subject: String) {
        // Hue, and the sign of the field, in the serif face.
        let (hue, sign): (Double, String) = switch subject {
        case "Machine Learning": (0.43, "θ")
        case "Deep Learning": (0.70, "σ")
        case "Statistics": (0.58, "Σ")
        case "Probability": (0.78, "ℙ")
        case "Linear Algebra": (0.02, "λ")
        case "Analysis": (0.96, "∫")
        case "Optimization": (0.50, "∇")
        case "Information Theory": (0.86, "H")
        case "Causal Inference": (0.18, "→")
        case "Computer Science": (0.62, "∀")
        case "Proofs & Algebra": (0.08, "∎")
        case "Reference": (0.13, "≡")
        default: (0.22, "∂")
        }
        top = Color(hue: hue, saturation: 0.42, brightness: 0.50)
        bottom = Color(hue: hue, saturation: 0.55, brightness: 0.30)
        ink = Color(red: 0.98, green: 0.96, blue: 0.90)
        self.sign = sign
    }
}

/// Page-one thumbnails of library books: memory, then the Covers folder, then PDFKit off the main thread.
@MainActor @Observable
final class CoverThumbnails {
    static let shared = CoverThumbnails()
    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var missing: Set<String> = []

    func image(for book: StudyWorkspace, folder: URL) -> NSImage? {
        if let image = images[book.id] { return image }
        load(book, folder: folder)
        return nil
    }

    /// Drops a book's cover, for instance when its PDF changed on disk; the next request renders it again.
    func forget(_ id: String) {
        images[id] = nil
        missing.remove(id)
    }

    private func load(_ book: StudyWorkspace, folder: URL) {
        guard !pending.contains(book.id), !missing.contains(book.id) else { return }
        pending.insert(book.id)
        let id = book.id, source = book.sourcePath
        let file = folder.appendingPathComponent("Covers", isDirectory: true).appendingPathComponent("\(id).png")
        Task.detached(priority: .utility) {
            let data = CoverThumbnails.render(file: file, source: source)
            await MainActor.run {
                self.pending.remove(id)
                if let data, let image = NSImage(data: data) { self.images[id] = image } else { self.missing.insert(id) }
            }
        }
    }

    /// The cached PNG, or a new one rendered from the PDF's first page and saved beside the others.
    nonisolated static func render(file: URL, source: String) -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        guard FileManager.default.fileExists(atPath: source),
              let page = PDFDocument(url: URL(fileURLWithPath: source))?.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: file, options: .atomic)
        return png
    }
}

/// A library book's cover: its first page, or a quiet placeholder while it renders.
struct LibraryBookCover: View {
    let book: StudyWorkspace
    let folder: URL
    var width: CGFloat = 96
    @State private var thumbnails = CoverThumbnails.shared
    @Environment(\.theme) private var theme

    var body: some View {
        let height = width * 4 / 3
        Group {
            if let image = thumbnails.image(for: book, folder: folder) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white
                    Text("λ").font(.system(size: width * 0.34, weight: .semibold, design: .serif)).foregroundStyle(Color.black.opacity(0.12))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.16), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}
