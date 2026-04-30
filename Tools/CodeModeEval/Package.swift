// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodeModeEvalTool",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .executable(
            name: "codemode-eval",
            targets: ["CodeModeEvalCLI"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/velos/wavelike-ios.git", branch: "main"),
        .package(url: "https://github.com/velos/CallableFunction.git", branch: "feature/function-updates"),
    ],
    targets: [
        .executableTarget(
            name: "CodeModeEvalCLI",
            dependencies: [
                .product(name: "CodeMode", package: "codemode-ios"),
                .product(name: "CodeModeEvaluation", package: "codemode-ios"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Wavelike", package: "wavelike-ios"),
                .product(name: "CallableFunction", package: "CallableFunction"),
            ]
        ),
    ]
)
