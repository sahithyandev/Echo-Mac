// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoCore", targets: ["EchoCore"]),
    ],
    targets: [
        .target(
            name: "EchoCore",
            path: "Sources/EchoCore"
        ),
        .testTarget(
            name: "EchoCoreTests",
            dependencies: ["EchoCore"],
            path: "Tests/EchoCoreTests"
        ),
    ]
)
