// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortspyBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PortspyBar",
            path: "Sources/PortspyBar"
        )
    ]
)
