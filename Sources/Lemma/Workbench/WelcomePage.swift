import SwiftUI
import AppKit
import LemmaCore

/// The Welcome editor: what Lemma is, the way in (open, drop, a free textbook, a folder), the books being read with
/// their covers and progress, free textbooks to start with, the Get Started checklist and the tour. It lays itself
/// out in two columns when the editor is wide and in one when side bars make it narrow.
struct WelcomeEditor: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    @State private var themes = ThemeManager.shared
    @State private var selectedStep: WalkthroughStep?
    @AppStorage("workbench.startupEditor") private var startupEditor = "welcomePage"

    /// Books chosen to show what Lemma does: well-typeset, freely distributed, across the catalog's subjects.
    static let featuredBookIDs = ["mml", "book-of-proof", "ladr", "isl-python", "convex-optimization", "grinstead-snell"]

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            let padding: CGFloat = geometry.size.width >= 700 ? 56 : 28
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    hero
                    if store.library.isEmpty { dropZone } else { continueReading(width: geometry.size.width - padding * 2) }
                    featuredShelf(width: geometry.size.width - padding * 2)
                    if wide {
                        HStack(alignment: .top, spacing: 48) {
                            gettingStarted.frame(maxWidth: .infinity, alignment: .leading)
                            sidebar.frame(width: 340, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 32) { gettingStarted; sidebar }
                    }
                    footer
                }
                .padding(.horizontal, padding).padding(.top, 52).padding(.bottom, 40)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(theme[.welcomePageBackground])
        .onAppear { if selectedStep == nil { selectedStep = WalkthroughStep.allCases.first { !$0.isDone(store) } } }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Lemma").font(.system(size: 44, weight: .semibold, design: .serif)).foregroundStyle(theme[.foreground])
                        Text(Self.version).font(.ui(12, weight: .medium)).foregroundStyle(theme[.descriptionForeground])
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(theme[.badgeBackground].opacity(0.6)))
                    }
                    Text("An IDE for reading mathematics.").font(.system(size: 18)).foregroundStyle(theme[.descriptionForeground])
                }
            }
            // The actions wrap onto a second row when side bars make the editor narrow.
            FlowLayout(spacing: 10) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        WelcomeActionButton(icon: "file-pdf", title: "Open a PDF…", shortcut: "⌘O", primary: true) { store.choosePDF() }
        WelcomeActionButton(icon: "extensions", title: "Get a Free Textbook", shortcut: "⇧⌘X") { store.catalogMode = .books; store.reveal(.catalog) }
        WelcomeActionButton(icon: "new-folder", title: "Add a Folder of PDFs…", shortcut: nil) { store.chooseFolderForNewLibrary() }
        WelcomeActionButton(icon: "cloud-download", title: "Open an arXiv Paper…", shortcut: nil) { store.catalogMode = .arxiv; store.reveal(.catalog) }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Codicon("file-pdf", size: 30).foregroundStyle(theme.accent)
            Text("Drop a book or a paper here, or anywhere on this window.")
                .font(.ui(15, weight: .medium)).foregroundStyle(theme[.foreground])
            Text("Lemma reads it once, on this Mac: references, equations and citations become links, statements and proofs become navigable, and nothing leaves your computer.")
                .font(.ui(12.5)).foregroundStyle(theme[.descriptionForeground]).multilineTextAlignment(.center)
                .frame(maxWidth: 560).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("No PDF at hand?").font(.ui(12.5)).foregroundStyle(theme[.descriptionForeground])
                VSLinkButton(title: "Open the sample book", icon: "book") { store.openSampleBook() }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 30).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent.opacity(theme.isDark ? 0.05 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6])))
        .contentShape(Rectangle())
        .onTapGesture { store.choosePDF() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens a PDF")
    }

    // MARK: Books

    private func continueReading(width: CGFloat) -> some View {
        let cardWidth: CGFloat = 112
        let fit = max(2, Int((width + 18) / (cardWidth + 18)))
        let books = Array(store.library.prefix(fit))
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Continue Reading", trailing: store.library.count > books.count ? "All \(store.library.count) Books" : nil) {
                store.reveal(.library)
            }
            HStack(alignment: .top, spacing: 18) {
                ForEach(books) { book in
                    ContinueReadingCard(book: book, folder: store.repository.root, width: cardWidth, isOpen: store.workspace?.id == book.id) {
                        store.reopen(book)
                    }
                }
            }
        }
    }

    private func featuredShelf(width: CGFloat) -> some View {
        let cardWidth: CGFloat = 104
        let fit = max(2, Int((width + 18) / (cardWidth + 18)))
        let books = Self.featuredBookIDs.compactMap { id in BookCatalog.books.first { $0.id == id } }.prefix(fit)
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(store.library.isEmpty ? "Start with a Free Textbook" : "Free Textbooks", trailing: "All \(BookCatalog.books.count) Books") {
                store.catalogMode = .books; store.reveal(.catalog)
            }
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(books)) { book in FeaturedBookCard(store: store, book: book, width: cardWidth) }
            }
            Text("Their authors or publishers give these books away as PDFs. Lemma downloads one only when you click Get, from its official address.")
                .font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(_ title: String, trailing: String?, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(theme[.foreground])
            Spacer(minLength: 12)
            if let trailing { VSLinkButton(title: trailing + " →", action: action) }
        }
    }

    // MARK: Get started

    private var gettingStarted: some View {
        let done = WalkthroughStep.allCases.filter { $0.isDone(store) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Get Started").font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(theme[.foreground])
                Spacer()
                Text("\(done) of \(WalkthroughStep.allCases.count) done").font(.ui(12)).monospacedDigit().foregroundStyle(theme[.descriptionForeground])
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme[.welcomePageProgressBackground])
                    Capsule().fill(theme[.welcomePageProgressForeground])
                        .frame(width: max(4, geometry.size.width * CGFloat(done) / CGFloat(WalkthroughStep.allCases.count)))
                }
            }.frame(height: 4)
            VStack(spacing: 2) {
                ForEach(WalkthroughStep.allCases) { step in stepRow(step) }
            }
        }
    }

    private func stepRow(_ step: WalkthroughStep) -> some View {
        let isDone = step.isDone(store)
        let selected = selectedStep == step
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Codicon(isDone ? "pass-filled" : "circle-large-outline", size: 16)
                    .foregroundStyle(isDone ? theme[.testingIconPassed] : theme[.descriptionForeground])
                Codicon(step.icon, size: 15).foregroundStyle(selected ? theme.accent : theme[.iconForeground])
                Text(step.title).font(.ui(13.5, weight: selected ? .semibold : .regular)).foregroundStyle(theme[.walkthroughStepTitleForeground])
                Spacer()
                if !selected { Codicon("chevron-right", size: 12).foregroundStyle(theme[.descriptionForeground].opacity(0.7)) }
            }
            if selected {
                VStack(alignment: .leading, spacing: 12) {
                    Text(step.detail).font(.ui(13)).foregroundStyle(theme[.descriptionForeground]).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if step == .theme { themeTiles }
                    Button(step.actionTitle) { step.perform(store) }.buttonStyle(.vsPrimary)
                }
                .padding(.leading, 56)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? theme[.welcomePageTileBackground] : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? theme.border(.welcomePageTileBorder) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { selectedStep = selected ? nil : step } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.title)\(isDone ? ", done" : "")")
    }

    private var themeTiles: some View {
        let picks = (["lemma-dark", "lemma-light", "dark-2026", "light-2026", "lemma-midnight", "moonlight-ii"]
                     + (themes.vscodeThemeID.map { [$0] } ?? [])).compactMap { themes.entry($0) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(picks) { entry in
                ThemeTile(entry: entry, selected: themes.effectiveID == entry.id) { themes.choose(entry.id); WalkthroughStep.markDone(.theme) }
            }
        }
    }

    // MARK: Side column

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            TutorialPromoCard(store: store)
            VStack(alignment: .leading, spacing: 10) {
                Text("This Week").font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(theme[.foreground])
                WeekReadingView(store: store)
            }
            HStack(alignment: .top, spacing: 10) {
                Codicon("lock", size: 14).foregroundStyle(theme[.descriptionForeground])
                Text("Lemma reads your books on this Mac. Nothing is sent anywhere unless you click a button that says where it goes.")
                    .font(.ui(12)).foregroundStyle(theme[.descriptionForeground]).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            VSCheckbox(isOn: Binding(get: { startupEditor == "welcomePage" }, set: { startupEditor = $0 ? "welcomePage" : "none" }),
                       label: "Show the Welcome page when no book is open")
            Spacer(minLength: 0)
            VSLinkButton(title: "What’s New", icon: "sparkle") { store.openSpecial(.releaseNotes) }
            VSLinkButton(title: "Keyboard Shortcuts", icon: "keyboard") { store.openShortcutsEditor() }
        }
        .padding(.top, 4)
    }

    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        return short.split(separator: ".").prefix(2).joined(separator: ".")
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = (path as NSString).deletingLastPathComponent
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }
}

/// A large welcome action: an icon, a title and its shortcut, primary in the theme's button colour.
private struct WelcomeActionButton: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let shortcut: String?
    var primary = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Codicon(icon, size: 15)
                Text(title).font(.ui(13, weight: .medium)).lineLimit(1)
                if let shortcut {
                    Text(shortcut).font(.ui(11.5)).opacity(0.65)
                }
            }
            .foregroundStyle(primary ? theme[.buttonForeground] : theme[.foreground])
            .padding(.horizontal, 14).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(primary ? .clear : theme.border(.welcomePageTileBorder), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }

    private var background: Color {
        if primary { return theme[hovering ? .buttonHoverBackground : .buttonBackground] }
        return hovering ? theme[.welcomePageTileHoverBackground] : theme[.welcomePageTileBackground]
    }
}

/// A book being read: its cover, title and how far the reader got.
private struct ContinueReadingCard: View {
    @Environment(\.theme) private var theme
    let book: StudyWorkspace
    let folder: URL
    let width: CGFloat
    let isOpen: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                LibraryBookCover(book: book, folder: folder, width: width)
                    .scaleEffect(hovering ? 1.03 : 1, anchor: .bottom)
                    .animation(.easeOut(duration: 0.14), value: hovering)
                Text(book.title).font(.ui(12, weight: .semibold)).foregroundStyle(theme[.foreground])
                    .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).frame(width: width, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(theme[.welcomePageProgressBackground]).frame(width: width, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule().fill(theme.accent).frame(width: max(3, width * (book.progress ?? 0)), height: 3)
                        }
                    Text(caption).font(.ui(11)).monospacedDigit().foregroundStyle(theme[.descriptionForeground]).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(book.sourcePath)
        .accessibilityLabel("\(book.title), \(caption)")
    }

    private var caption: String {
        if isOpen { return "Open now" }
        guard let count = book.pageCount, count > 0 else { return "Not started" }
        let page = book.reading.pageIndex + 1
        return page <= 1 ? "\(count) pages" : "Page \(page) of \(count)"
    }
}

/// A free textbook: its generated cover, title and authors, and Get, Open or the download's progress.
private struct FeaturedBookCard: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    let book: CatalogBook
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        let downloaded = store.isInLibrary(book)
        let progress = store.downloads.progress[book.id]
        VStack(alignment: .leading, spacing: 8) {
            GeneratedBookCover(title: book.title, subtitle: book.subtitle, authors: book.authorLine, subject: book.subject, width: width)
                .scaleEffect(hovering ? 1.03 : 1, anchor: .bottom)
                .animation(.easeOut(duration: 0.14), value: hovering)
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressView(value: progress).progressViewStyle(.linear).tint(.white).padding(8)
                    }
                }
            // Two lines are always reserved for the title, so the Get buttons of a shelf line up.
            Text(book.title).font(.ui(12, weight: .semibold)).foregroundStyle(theme[.foreground])
                .lineLimit(2, reservesSpace: true).frame(width: width, alignment: .topLeading)
            Text(book.authorLine).font(.ui(11)).foregroundStyle(theme[.descriptionForeground]).lineLimit(1).frame(width: width, alignment: .leading)
            Group {
                if progress != nil {
                    Button("Cancel") { store.downloads.cancel(book.id) }.buttonStyle(VSButtonStyle(kind: .secondary, compact: true))
                } else if downloaded {
                    Button("Open") { store.open(store.catalogFile(book)) }.buttonStyle(VSButtonStyle(kind: .secondary, compact: true))
                } else {
                    Button("Get") { store.getCatalogBook(book) }.buttonStyle(VSButtonStyle(kind: .primary, compact: true))
                        .help("Download the PDF from \(book.pdf.host ?? "the authors' site") (\(book.sizeText ?? "PDF")) and open it")
                }
            }
            if let failure = store.downloads.failures[book.id] {
                Text(failure).font(.ui(10.5)).foregroundStyle(theme[.errorForeground]).frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width, alignment: .leading)
        .onHover { hovering = $0 }
        .help("\(book.title)\(book.subtitle.map { ": " + $0 } ?? "")\n\(book.summary)\n\(book.license)")
    }
}

/// Reading time this week across books, as small bars.
struct WeekReadingView: View {
    @Bindable var store: StudyStore
    @Environment(\.theme) private var theme
    var body: some View {
        let days = ReadingSummary.days(store.library.map(\.readingLog), count: 7)
        let maximum = max(days.map(\.seconds).max() ?? 0, 60)
        let total = days.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(index == days.count - 1 ? theme.accent : theme.accent.opacity(0.45))
                            .frame(width: 20, height: max(3, 48 * day.seconds / maximum))
                        Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.ui(10)).foregroundStyle(theme[.descriptionForeground])
                    }
                }
            }
            Text(total > 0 ? "\(ReadingLog.describeShort(total)) of reading this week" : "No reading recorded this week yet.")
                .font(.ui(12)).foregroundStyle(theme[.descriptionForeground])
        }
    }
}
