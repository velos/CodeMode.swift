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
        .executable(
            name: "codemode-eval",
            targets: ["CodeModeEvalCLI"]
        ),
    ],
    dependencies: [
        .package(path: "../../collab/collab-proxy/packages/ios/Wavelike"),
        .package(path: "../../collab/collab-proxy/packages/ios/WavelikeEngineApple"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CodeMode"
        ),
        .executableTarget(
            name: "CodeModeEvalCLI",
            dependencies: [
                "CodeMode",
                .product(name: "Wavelike", package: "Wavelike"),
                .product(name: "WavelikeEngineApple", package: "WavelikeEngineApple"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "CodeModeTests",
            dependencies: ["CodeMode"]
        ),
    ]
)
