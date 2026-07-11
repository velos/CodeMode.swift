// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CodeMode",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "CodeMode",
            targets: ["CodeMode"]
        ),
        .library(
            name: "CodeModeEvaluation",
            targets: ["CodeModeEvaluation"]
        ),
    ],
    targets: [
        .target(
            name: "CCodeModeJSC",
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .target(
            name: "CodeMode",
            dependencies: ["CCodeModeJSC"]
        ),
        .target(
            name: "CodeModeEvaluation",
            dependencies: ["CodeMode"]
        ),
        .testTarget(
            name: "CodeModeTests",
            dependencies: ["CodeMode"]
        ),
        .testTarget(
            name: "CodeModeEvalTests",
            dependencies: ["CodeModeEvaluation"]
        ),
    ]
)
