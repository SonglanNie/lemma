// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lemma",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lemma", targets: ["Lemma"]),
        .executable(name: "LemmaBrowserHost", targets: ["LemmaBrowserHost"]),
        .executable(name: "LemmaIndexer", targets: ["LemmaIndexer"])
    ],
    dependencies: [
        // In-app updates. The appcast and each update are signed with the project's EdDSA key, so an update installs only
        // if it was published by Lemma's maintainers.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "LemmaCore"),
        .executableTarget(name: "Lemma", dependencies: ["LemmaCore", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.copy("Resources/Math"), .copy("Resources/Themes"), .copy("Resources/Codicons"),
                                      .copy("Resources/Assistant"), .copy("Resources/Sample"), .copy("Resources/Licenses")],
                          // In the app bundle Sparkle.framework sits in Contents/Frameworks (scripts/build-app.sh puts it there).
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "LemmaBrowserHost", dependencies: ["LemmaCore"]),
        .executableTarget(name: "LemmaIndexer", dependencies: ["LemmaCore"]),
        // Fixtures: small PDFs compiled from the LaTeX sources beside them (tectonic), typeset unlike ESL.
        .testTarget(name: "LemmaCoreTests", dependencies: ["LemmaCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "LemmaAppTests", dependencies: ["Lemma", "LemmaCore"], resources: [.copy("Fixtures")])
    ]
)
