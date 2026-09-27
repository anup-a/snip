// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LarkScreenshot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "LarkScreenshot", path: "Sources/LarkScreenshot")
    ]
)
