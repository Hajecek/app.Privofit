#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Vyžadován macOS a Xcode 27.' >&2; exit 1; }
xcodebuild -version
xcodebuild -list -project Privofit.xcodeproj
xcodebuild -project Privofit.xcodeproj -scheme Privofit -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Privofit.xcodeproj -scheme Privofit -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
if [[ -z "${PRIVOFIT_SIMULATOR_ID:-}" ]]; then
    echo 'Build dokončen. Pro testy vyber UUID pomocí xcrun simctl list devices available.'
    echo 'Potom spusť: PRIVOFIT_SIMULATOR_ID=<UUID> ./Scripts/validate_on_mac.sh'
    exit 0
fi
xcodebuild -project Privofit.xcodeproj -scheme 'Privofit Demo' -configuration Debug -destination "platform=iOS Simulator,id=${PRIVOFIT_SIMULATOR_ID}" -parallel-testing-enabled NO -resultBundlePath "TestResults-$(date +%Y%m%d-%H%M%S).xcresult" CODE_SIGNING_ALLOWED=NO test
