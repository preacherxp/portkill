// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "portkill",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PortkillCore"),
        .executableTarget(name: "portkill", dependencies: ["PortkillCore"]),
        .testTarget(name: "PortkillCoreTests", dependencies: ["PortkillCore"]),
    ]
)
