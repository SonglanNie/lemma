# Releasing Lemma

1. **Version.** Raise `CFBundleShortVersionString` and `CFBundleVersion` in `scripts/package-app.py`, add the release to `CHANGELOG.md` and to **What's New** (`ReleaseNotesEditor` in `Sources/Lemma/Workbench/SpecialEditors.swift`).
2. **Check.** `swift test` passes; open the app in light and dark, both interface styles; CPU at rest stays near zero (`ps -o time= -p <pid>` twice, ten seconds apart).
3. **Build.** `scripts/build-app.sh --universal` (Apple silicon and Intel).
   - With a paid Apple Developer membership: `LEMMA_SIGN_IDENTITY="Developer ID Application: <name> (<team>)" scripts/build-app.sh --universal`, which signs with the hardened runtime and a timestamp.
4. **Package.** `scripts/make-dmg.sh` writes `build/Lemma-<version>.dmg` and prints its SHA-256. Without a Developer ID it adds a note on opening an app macOS cannot verify.
   - With a Developer ID: `scripts/notarize.sh build/Lemma-<version>.dmg` (once: `xcrun notarytool store-credentials lemma-notary …`).
5. **Publish.** `gh release create v<version> build/Lemma-<version>.dmg --title "Lemma <version>" --notes-file <notes>`. Lemma's **Check for Updates…** reads the latest release's tag (`v3.0.1` → 3.0.1).
6. **Homebrew.** Update `version` and `sha256` in `packaging/homebrew/lemma.rb` and copy it to the tap repository (`fus3r/homebrew-lemma`, `Casks/lemma.rb`). Users install with `brew install --cask fus3r/lemma/lemma`.
