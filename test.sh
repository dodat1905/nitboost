#!/bin/zsh
set -euo pipefail
cd "${0:a:h}"
mkdir -p build.noindex/tests
swiftc -swift-version 5 -target arm64-apple-macos13.0 Sources/BrightnessController.swift Tests/Hardware.swift Tests/main.swift -o build.noindex/tests/brightness
build.noindex/tests/brightness
