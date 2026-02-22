// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeMode",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "CodeMode",
            targets: ["CodeMode"]
        ),
    ],
    targets: [
        .target(
            name: "CodeMode"
        ),
        .testTarget(
            name: "CodeModeTests",
            dependencies: ["CodeMode"]
        ),
    ]
)
