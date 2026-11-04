// swift-tools-version: 6.0
import PackageDescription

// The engine as a library with a C interface, for the Windows app (docs/adr/0003-windows-shared-engine.md):
// PresenterBridge.dll on Windows, libPresenterBridge.dylib on a Mac.
let package = Package(
    name: "PresenterBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PresenterBridge", type: .dynamic, targets: ["PresenterBridge"]),
    ],
    dependencies: [
        .package(path: "../PresenterCore"),
    ],
    targets: [
        .target(name: "PresenterBridge", dependencies: [.product(name: "PresenterCore", package: "PresenterCore")]),
        .testTarget(name: "PresenterBridgeTests", dependencies: ["PresenterBridge"]),
    ]
)
