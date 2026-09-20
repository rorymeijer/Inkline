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
        // One dynamic library holding all three modules, so the app and the
        // plugin bundles share a single copy of these types at runtime: a
        // plugin compiled against a *static* copy would produce a second,
        // incompatible `InklinePlugin` protocol and every `as? InklinePlugin`
        // cast would fail. The product name deliberately differs from every
        // target name: Xcode refuses to build a target dynamically when a
        // same-named product exists and the target is also linked statically
        // (as the in-package target dependencies do).
        .library(
            name: "InklineKit",
            type: .dynamic,
            targets: ["InklineCore", "InklineSyntax", "InklinePluginAPI"]
        )
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
