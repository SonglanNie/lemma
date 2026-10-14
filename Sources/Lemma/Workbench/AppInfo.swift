import SwiftUI
import AppKit
import LemmaCore

/// Where Lemma lives on the web, and what version this is. One place to change when the repository moves.
enum LemmaLinks {
    /// The GitHub repository (owner/name) that hosts the source, the issue tracker and the releases.
    static let repository = "fus3r/lemma"
    static let site = URL(string: "https://github.com/\(repository)")!
    static let releases = URL(string: "https://github.com/\(repository)/releases")!
    static let latestRelease = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let privacy = URL(string: "https://github.com/\(repository)/blob/main/PRIVACY.md")!

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0.0" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }

    /// A new issue on GitHub, its body prefilled with what helps diagnose a problem; nothing is sent until the reader
    /// submits it in the browser.
    @MainActor static func newIssue(title: String = "") -> URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let style = ThemeManager.shared.style == .classic ? "Classic" : "Workbench"
        let body = """
        **What happened**


        **What you expected**


        **Steps to reproduce**
        1.

        ---
        Lemma \(version) (\(build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(String(cString: model)) · \(style) interface
        """
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
        components.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        return components.url ?? site
    }

    /// GitHub's "Book report" form (`.github/ISSUE_TEMPLATE/book_report.yml`), its fields prefilled with the book and
    /// what Lemma found in it; the reader says what went wrong. Nothing is sent until they submit it in the browser.
    static func bookReport(book: String, found: String) -> URL {
        var components = URLComponents(string: "https://github.com/\(repository)/issues/new")!
        components.queryItems = [URLQueryItem(name: "template", value: "book_report.yml"),
                                 URLQueryItem(name: "title", value: "Book report: \(book)"),
                                 URLQueryItem(name: "book", value: book), URLQueryItem(name: "right", value: found),
                                 URLQueryItem(name: "version", value: build.isEmpty ? version : "\(version) (\(build))")]
        return components.url ?? site
    }

    /// The About panel with credits for the code and assets Lemma bundles.
    @MainActor static func showAbout() {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.paragraphSpacing = 4
        func add(_ text: String, bold: Bool = false, link: URL? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: bold ? .semibold : .regular),
                                                              .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }
        add("An IDE for reading mathematics.\n", bold: true)
        add("Free software under the GNU General Public License, version 3. Your books and notes stay on this Mac.\n\n")
        add("Source code, issues and releases on GitHub\n", link: site)
        add("\nIcons: Codicons by Microsoft (CC BY 4.0). Colour themes: VS Code's (MIT) and their community authors' (MIT, Apache 2.0). Mathematics: KaTeX (MIT) with its fonts (SIL Open Font License 1.1), Marked (MIT), DOMPurify (Apache 2.0). Help › Acknowledgements lists every licence.")
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Lemma",
            .applicationVersion: version,
            .version: build.isEmpty ? "" : "build \(build)",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension StudyStore {
    /// Help › Report How Lemma Read This Book…: the book report form for the book in front, with its title and what the
    /// analysis found, so telling how Lemma did on a book takes a sentence.
    func reportBook() {
        guard let workspace else { return }
        var found: [String] = []
        if let model = analysis, let book = model.analysis {
            func count(_ n: Int, _ one: String, _ many: String) { if n > 0 { found.append("\(n) \(n == 1 ? one : many)") } }
            count(model.definitionCounts[.equation] ?? 0, "numbered equation", "numbered equations")
            count(model.definitionCounts[.figure] ?? 0, "figure", "figures")
            count(model.definitionCounts[.table] ?? 0, "table", "tables")
            count(book.structure.statements.count, "statement (theorem, lemma…)", "statements (theorems, lemmas…)")
            count(book.structure.statements.filter { book.structure.proof(of: $0.key) != nil }.count, "proof", "proofs")
            count(book.bibliography.count, "bibliography entry", "bibliography entries")
            count(book.index.count, "index entry", "index entries")
        }
        let pages = document.map { "\($0.pageCount) pages" }
        let summary = found.isEmpty ? "Lemma has not finished reading this PDF\(pages.map { " (\($0))" } ?? "")."
            : "Lemma found \(found.joined(separator: ", "))\(pages.map { " in \($0)" } ?? "")."
        NSWorkspace.shared.open(LemmaLinks.bookReport(book: workspace.title, found: summary))
    }
}

/// Checks GitHub for a newer release, only when the reader asks or has turned on automatic checks (once a day).
/// Nothing but a request for the latest release's public metadata is sent.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let automaticKey = "updates.automatic"
    static let lastCheckKey = "updates.lastCheck"

    private(set) var isChecking = false
    @ObservationIgnored weak var store: StudyStore?

    var automatic: Bool {
        get { UserDefaults.standard.bool(forKey: Self.automaticKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticKey) }
    }

    /// At launch, if automatic checks are on and a day has passed.
    func checkIfDue(store: StudyStore) {
        self.store = store
        guard automatic else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date.now.timeIntervalSince1970 - last > 86_400 else { return }
        Task { try? await Task.sleep(for: .seconds(20)); await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastCheckKey)
        var request = URLRequest(url: LemmaLinks.latestRelease, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Lemma/\(LemmaLinks.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                if userInitiated {
                    store?.notify(status == 404 ? "No release of Lemma has been published yet." : "GitHub answered with status \(status). Try again later.",
                                  source: "Updates")
                }
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.isNewer(latest, than: LemmaLinks.version) {
                let page = URL(string: release.page) ?? LemmaLinks.releases
                store?.notify("Lemma \(latest) is available. You have \(LemmaLinks.version).", source: "Updates",
                              actions: [LemmaNotification.Action(title: "Download", primary: true) { NSWorkspace.shared.open(page) }], timeout: nil)
            } else if userInitiated {
                store?.notify("Lemma \(LemmaLinks.version) is the latest version.", source: "Updates")
            }
        } catch {
            if userInitiated { store?.notify("Could not reach GitHub: \(error.localizedDescription)", severity: .warning, source: "Updates") }
        }
    }

    private struct Release: Decodable {
        let tag: String
        let page: String
        enum CodingKeys: String, CodingKey { case tag = "tag_name", page = "html_url" }
    }

    /// Compares dotted version numbers numerically ("3.10.0" is newer than "3.9.2").
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            text.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Every licence of the code, fonts, icons and themes Lemma bundles, read from the files shipped with the app.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var selection = 7

    private struct Entry: Identifiable { let id: Int; let title: String; let detail: String; let file: String }
    private let entries: [Entry] = [
        Entry(id: 7, title: "Lemma", detail: "GNU General Public License, version 3", file: "LICENSE.txt"),
        Entry(id: 0, title: "Codicons", detail: "Icons by Microsoft · CC BY 4.0 (icons), MIT (code)", file: "Codicons/LICENSE"),
        Entry(id: 1, title: "Colour themes", detail: "VS Code's themes and community themes · MIT, Apache 2.0", file: "Themes/THIRD_PARTY_NOTICES.txt"),
        Entry(id: 2, title: "Theme sources", detail: "Where each bundled theme comes from", file: "Themes/LICENSES.md"),
        Entry(id: 3, title: "KaTeX", detail: "Mathematics typesetting · MIT", file: "Math/KaTeX-LICENSE.txt"),
        Entry(id: 4, title: "KaTeX fonts", detail: "SIL Open Font License 1.1", file: "Math/KaTeX-Fonts-OFL.txt"),
        Entry(id: 5, title: "Marked", detail: "Markdown · MIT", file: "Math/Marked-LICENSE.txt"),
        Entry(id: 6, title: "DOMPurify", detail: "HTML sanitizer · Apache 2.0 or MPL 2.0", file: "Math/DOMPurify-LICENSE.txt"),
        Entry(id: 8, title: "Sparkle", detail: "Software updates · MIT", file: "Licenses/Sparkle-LICENSE.txt")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Acknowledgements").font(.system(size: 20, weight: .semibold, design: .serif))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 0) {
                List(entries, selection: Binding(get: { selection }, set: { selection = $0 ?? 7 })) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.system(size: 13, weight: .medium))
                        Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.vertical, 3).tag(entry.id)
                }
                .listStyle(.sidebar).frame(width: 240)
                ScrollView {
                    Text(text(entries.first { $0.id == selection }?.file ?? ""))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(width: 820, height: 560)
    }

    private func text(_ file: String) -> String {
        guard let url = Codicons.resource(file), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The licence file \(file) is missing from this copy of Lemma."
        }
        return text
    }
}
