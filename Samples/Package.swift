// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "actor-edge-samples",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11)
    ],
    products: [
        .executable(
            name: "SampleChatServer",
            targets: ["SampleChatServer"]
        ),
        .executable(
            name: "SampleChatClient",
            targets: ["SampleChatClient"]
        )
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        // Shared API for the chat sample
        .target(
            name: "SampleChatShared",
            dependencies: [
                .product(name: "ActorEdge", package: "actor-edge")
            ],
            swiftSettings: [
                .unsafeFlags(["-Onone"]), // Disable optimization for better type retention
                .define("DEBUG")
            ]
        ),
        
        // Chat server executable
        .executableTarget(
            name: "SampleChatServer",
            dependencies: [
                "SampleChatShared",
                .product(name: "ActorEdgeServer", package: "actor-edge")
            ],
            swiftSettings: [
                .unsafeFlags(["-Onone"]), // Disable optimization for better type retention
                .define("DEBUG")
            ]
        ),
        
        // Chat client executable
        .executableTarget(
            name: "SampleChatClient",
            dependencies: [
                "SampleChatShared",
                .product(name: "ActorEdgeClient", package: "actor-edge")
            ],
            swiftSettings: [
                .unsafeFlags(["-Onone"]), // Disable optimization for better type retention
                .define("DEBUG")
            ]
        ),
        
        // Noop test target to prevent swift test from failing
        .testTarget(
            name: "NoopTests",
            dependencies: []
        )
    ]
)