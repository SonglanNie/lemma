# Homebrew cask for Lemma, for a personal tap (github.com/fus3r/homebrew-lemma) until the official cask
# requirements are met. Update `version` and `sha256` (printed by scripts/make-dmg.sh) for each release.
cask "lemma" do
  version "3.3.1"
  sha256 "a71f26dac68193b1d56decf7c3199958b9f4b3084a6151b712810374f8581b50"

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
