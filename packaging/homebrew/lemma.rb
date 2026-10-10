# Homebrew cask for Lemma, for a personal tap (github.com/fus3r/homebrew-lemma) until the official cask
# requirements are met. Update `version` and `sha256` (printed by scripts/make-dmg.sh) for each release.
cask "lemma" do
  version "3.0.0"
  sha256 "e3ab554428eaa8911a03f7c6d8cef183abac99dceba0cf09034311ed37c13f0a"

  url "https://github.com/fus3r/lemma/releases/download/v#{version}/Lemma-#{version}.dmg"
  name "Lemma"
  desc "IDE for reading mathematics: references as links, proofs as steps, derivations checked"
  homepage "https://github.com/fus3r/lemma"

  depends_on macos: ">= :sequoia"

  app "Lemma.app"

  zap trash: [
    "~/Library/Application Support/Lemma",
    "~/Library/Preferences/com.lemma.app.plist",
    "~/Library/WebKit/com.lemma.app",
    "~/Library/Caches/com.lemma.app",
  ]
end
