#!/bin/bash

# Generate gRPC Swift code from protobuf definitions

# Install protoc-gen-grpc-swift if needed
if ! command -v protoc-gen-grpc-swift &> /dev/null; then
    echo "Installing protoc-gen-grpc-swift..."
    brew install swift-protobuf grpc-swift
fi

# Create Generated directory if it doesn't exist
mkdir -p Sources/ActorEdgeCore/Generated

# Generate Swift Protobuf code only (not gRPC service code for v2.0)
echo "Generating Swift Protobuf code..."
protoc \
    --proto_path=Sources/ActorEdgeCore/Protobuf \
    --swift_out=Sources/ActorEdgeCore/Generated \
    --swift_opt=Visibility=Public \
    distributed_actor.proto

echo "Done!"