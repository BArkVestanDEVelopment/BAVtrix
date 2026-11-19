// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BAVtrixCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "BAVtrixCore", targets: ["BAVtrixCore"]),
    ],
    targets: [
        .target(name: "BAVtrixCore"),
        .testTarget(name: "BAVtrixCoreTests", dependencies: ["BAVtrixCore"]),
    ]
)
