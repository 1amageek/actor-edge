// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "actor-edge",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "ActorEdge",
            targets: ["ActorEdge"]),
        .library(
            name: "ActorEdgeCore",
            targets: ["ActorEdgeCore"]),
        .library(
            name: "ActorEdgeServer",
            targets: ["ActorEdgeServer"]),
        .library(
            name: "ActorEdgeClient",
            targets: ["ActorEdgeClient"]),
    ],
    dependencies: [
        // Networking
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.70.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.28.0"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", exact: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.0.0"),
        // .package(url: "https://github.com/grpc/grpc-swift-extras.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        
        // Logging and Lifecycle
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
        
        // Tracing and Context
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-service-context.git", from: "1.1.0"),
    ],
    targets: [
        // Main public API
        .target(
            name: "ActorEdge",
            dependencies: ["ActorEdgeCore", "ActorEdgeServer", "ActorEdgeClient"]
        ),
        
        // Core functionality
        .target(
            name: "ActorEdgeCore",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
            ],
            exclude: [],
            plugins: [
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")
            ]
        ),
        
        // Server-specific
        .target(
            name: "ActorEdgeServer",
            dependencies: [
                "ActorEdgeCore",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                // .product(name: "GRPCServiceLifecycle", package: "grpc-swift-extras"),
            ]
        ),
        
        // Client-specific
        .target(
            name: "ActorEdgeClient",
            dependencies: ["ActorEdgeCore"]
        ),
        
        // Tests
        .testTarget(
            name: "ActorEdgeTests",
            dependencies: [
                "ActorEdge",
                "ActorEdgeCore",
                "ActorEdgeServer",
                "ActorEdgeClient"
            ]
        ),
    ]
)
