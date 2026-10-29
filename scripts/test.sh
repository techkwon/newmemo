#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -warnings-as-errors Sources/Core/*.swift Tests/CoreTests.swift -o build/CoreTests
build/CoreTests
swiftc -swift-version 5 -warnings-as-errors Sources/Core/*.swift Tests/ActionTests.swift -o build/ActionTests
build/ActionTests
swiftc -swift-version 5 -warnings-as-errors Sources/Core/FinderTarget.swift Tests/FinderTargetTests.swift -o build/FinderTargetTests
build/FinderTargetTests
swiftc -swift-version 5 -warnings-as-errors Sources/Core/*.swift Tests/RequestAuthorizationTests.swift -o build/RequestAuthorizationTests
build/RequestAuthorizationTests
swiftc -swift-version 5 -warnings-as-errors -framework AppKit -framework ImageIO Sources/Core/*.swift Sources/App/UtilityActions.swift Tests/UtilityTests.swift -o build/UtilityTests
build/UtilityTests
swiftc -swift-version 5 -warnings-as-errors -framework AppKit Sources/App/MarkdownRenderer.swift Sources/App/PlainTextDocument.swift Tests/DocumentTests.swift -o build/DocumentTests
build/DocumentTests
swiftc -swift-version 5 -warnings-as-errors -O -framework AppKit Sources/App/MarkdownRenderer.swift Tests/MarkdownTests.swift -o build/MarkdownTests
build/MarkdownTests
