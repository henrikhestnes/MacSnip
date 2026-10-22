// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacSnip",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacSnip", targets: ["MacSnip"])],
    targets: [
        .target(name: "MacSnipCore"),
        .executableTarget(name: "MacSnip", dependencies: ["MacSnipCore"]),
        .testTarget(name: "MacSnipCoreTests", dependencies: ["MacSnipCore"])
    ]
)
