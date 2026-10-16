// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bare",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Bare", path: "Sources/Bare")
    ]
)
