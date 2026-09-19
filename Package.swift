// swift-tools-version:5.9
import PackageDescription

// Inkline — "Elke taal. Elk bestand. Meteen open."
//
// This package contains the *headless* part of Inkline: everything that can be
// built, unit-tested and reasoned about without AppKit, SwiftUI or an Xcode
// project. The macOS application itself lives in `App/` (XcodeGen project) and
// consumes these libraries as a local Swift package.
//
// Deliberately free of external dependencies so `swift test` works offline and
// runs in a couple of seconds during a release.
let package = Package(
    name: "Inkline",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "InklineCore", targets: ["InklineCore"]),
        .library(name: "InklineSyntax", targets: ["InklineSyntax"]),
        .library(name: "InklinePluginAPI", targets: ["InklinePluginAPI"])
    ],
    targets: [
        .target(
            name: "InklineCore",
            path: "Sources/InklineCore"
        ),
        .target(
            name: "InklineSyntax",
            dependencies: ["InklineCore"],
            path: "Sources/InklineSyntax",
            resources: [
                .copy("Resources/Languages"),
                .copy("Resources/Themes")
            ]
        ),
        .target(
            name: "InklinePluginAPI",
            dependencies: ["InklineCore"],
            path: "Sources/InklinePluginAPI"
        ),
        .testTarget(
            name: "InklineCoreTests",
            dependencies: ["InklineCore"],
            path: "Tests/InklineCoreTests"
        ),
        .testTarget(
            name: "InklineSyntaxTests",
            dependencies: ["InklineSyntax", "InklineCore"],
            path: "Tests/InklineSyntaxTests"
        ),
        .testTarget(
            name: "InklinePluginAPITests",
            dependencies: ["InklinePluginAPI", "InklineCore"],
            path: "Tests/InklinePluginAPITests"
        )
    ]
)
