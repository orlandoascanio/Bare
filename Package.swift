// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HideDesktop",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "HideDesktop", path: "Sources/HideDesktop")
    ]
)
