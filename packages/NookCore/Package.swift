// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NookCore", targets: ["NookCore"]),
    ],
    targets: [
        .target(name: "NookCore"),
        .testTarget(name: "NookCoreTests", dependencies: ["NookCore"]),
    ]
)
