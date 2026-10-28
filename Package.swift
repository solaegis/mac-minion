// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacMinion",
    platforms: [.macOS(.v26)],
    dependencies: [
        // App updates. Pinned: bump on purpose, after reading Sparkle's changelog.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "MacMinionKit"),
        .executableTarget(
            name: "MacMinion",
            dependencies: ["MacMinionKit", .product(name: "Sparkle", package: "Sparkle")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // build.sh copies Sparkle.framework into Contents/Frameworks; find it there.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MacMinionKitTests", dependencies: ["MacMinionKit"]),
    ]
)
