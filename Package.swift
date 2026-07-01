// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftLingo",
    products: [
        .executable(name: "swiftlingoc", targets: ["swiftlingoc"]),
        .plugin(name: "LingoTranspilerPlugin", targets: ["LingoTranspilerPlugin"]),
        .library(name: "LingoTranspiler", targets: ["LingoTranspiler"]),
        .library(name: "LingoRuntime", targets: ["LingoRuntime"]),
        .library(name: "LingoAST", targets: ["LingoAST"]),
        .library(name: "LingoParser", targets: ["LingoParser"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/apple/swift-system", from: "1.5.0")
    ],
    targets: [
        // AST
        .target(
            name: "LingoAST",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Parser
        .target(
            name: "LingoParser",
            dependencies: ["LingoAST"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "LingoParserTests",
            dependencies: ["LingoParser", "LingoAST"],
            resources: [.copy("Resources")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Transpiler (Library)
        .target(
            name: "LingoTranspiler",
            dependencies: ["LingoAST", "LingoParser"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "LingoTranspilerTests",
            dependencies: [
                "LingoTranspiler",
                "LingoAST",
                "LingoParser",
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system")
            ],
            resources: [.copy("../LingoParserTests/Resources")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Compiler CLI (Executable)
        .executableTarget(
            name: "swiftlingoc",
            dependencies: [
                "LingoTranspiler",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Build Tool Plugin
        .plugin(
            name: "LingoTranspilerPlugin",
            capability: .buildTool(),
            dependencies: ["swiftlingoc"]
        ),
        // Embedded Runtime (Library)
        .target(
            name: "LingoRuntime",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "LingoRuntimeTests",
            dependencies: ["LingoRuntime"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        )
    ]
)
