// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Snip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Snip", targets: ["Snip"]),
        // Built as SnipCLI (the app binary is "Snip" and the file system ignores case); installed as `snip`.
        .executable(name: "SnipCLI", targets: ["SnipCLI"]),
    ],
    targets: [
        .target(name: "SnipKit", path: "Sources/SnipKit"),
        .executableTarget(name: "Snip", dependencies: ["SnipKit"], path: "Sources/Snip"),
        .executableTarget(name: "SnipCLI", dependencies: ["SnipKit"], path: "Sources/SnipCLI"),
    ]
)
