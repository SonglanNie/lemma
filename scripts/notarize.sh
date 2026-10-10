#!/bin/zsh
# notarize.sh <file.dmg>: sends a Developer ID-signed disk image to Apple's notary service, waits, staples the ticket
# and checks that Gatekeeper accepts it. Needs a paid Apple Developer membership and, once:
#   xcrun notarytool store-credentials lemma-notary --apple-id <apple id> --team-id <team id> --password <app-specific password>
set -eu
dmg=${1:?usage: notarize.sh build/Lemma-<version>.dmg}
xcrun notarytool submit "$dmg" --keychain-profile "${LEMMA_NOTARY_PROFILE:-lemma-notary}" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
