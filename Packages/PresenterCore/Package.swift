// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PresenterCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PresenterCore", targets: ["PresenterCore"]),
    ],
    targets: [
        .target(name: "PresenterCore"),
        .testTarget(name: "PresenterCoreTests", dependencies: ["PresenterCore"]),
    ]
)
