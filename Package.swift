// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftLingo",
    products: [
        .executable(name: "SwiftLingo", targets: ["SwiftLingo"]),
        .library(name: "LingoAST", targets: ["LingoAST"]),
        .library(name: "LingoLexer", targets: ["LingoLexer"]),
        .library(name: "LingoParser", targets: ["LingoParser"]),
    ],
    targets: [
        // AST
        .target(
            name: "LingoAST",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Lexer
        .target(
            name: "LingoLexer",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "LingoLexerTests",
            dependencies: ["LingoLexer"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Parser
        .target(
            name: "LingoParser",
            dependencies: ["LingoAST", "LingoLexer"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "LingoParserTests",
            dependencies: ["LingoParser"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        // Main integration executable
        .executableTarget(
            name: "SwiftLingo",
            dependencies: ["LingoAST", "LingoLexer", "LingoParser"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
        .testTarget(
            name: "SwiftLingoTests",
            dependencies: ["SwiftLingo"],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),
    ]
)
