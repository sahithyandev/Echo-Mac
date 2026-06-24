// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoCore", targets: ["EchoCore"]),
    ],
    targets: [
        .binaryTarget(
            name: "CChromaprint",
            path: "vendor/Chromaprint.xcframework"
        ),
        .target(
            name: "EchoCore",
            dependencies: ["CChromaprint"],
            path: "Sources/EchoCore",
            linkerSettings: [
                .linkedLibrary("c++")  // Chromaprint is C++; link the standard lib
            ]
        ),
        .testTarget(
            name: "EchoCoreTests",
            dependencies: ["EchoCore"],
            path: "Tests/EchoCoreTests"
        ),
    ]
)
