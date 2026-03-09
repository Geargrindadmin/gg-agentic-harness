// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GGHarnessControlSurface",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.1"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "6.2.4"),
    ],
    targets: [
        .executableTarget(
            name: "GGHarnessControlSurface",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources/GGASConsole"
        ),
        .testTarget(
            name: "GGHarnessControlSurfaceTests",
            dependencies: [
                "GGHarnessControlSurface",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/GGHarnessControlSurfaceTests",
            exclude: [
                "A2AClientTests 2.swift",
                "CoordinatorRuntimeSettingsTests 2.swift"
            ]
        ),
    ]
)
