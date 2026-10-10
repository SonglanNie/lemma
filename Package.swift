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
    targets: [
        .target(name: "LemmaCore"),
        .executableTarget(name: "Lemma", dependencies: ["LemmaCore"], resources: [.copy("Resources/Math"), .copy("Resources/Themes"), .copy("Resources/Codicons"), .copy("Resources/Assistant"), .copy("Resources/Sample")]),
        .executableTarget(name: "LemmaBrowserHost", dependencies: ["LemmaCore"]),
        .executableTarget(name: "LemmaIndexer", dependencies: ["LemmaCore"]),
        // Fixtures: small PDFs compiled from the LaTeX sources beside them (tectonic), typeset unlike ESL.
        .testTarget(name: "LemmaCoreTests", dependencies: ["LemmaCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "LemmaAppTests", dependencies: ["Lemma", "LemmaCore"], resources: [.copy("Fixtures")])
    ]
)
