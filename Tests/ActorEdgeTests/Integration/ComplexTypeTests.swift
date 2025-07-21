import Testing
@testable import ActorEdgeCore
import Distributed
import Foundation

@Suite("Complex Type Tests", .tags(.integration, .serialization))
struct ComplexTypeTests {
    
    // MARK: - Complex Type Definitions
    
    struct NestedComplexType: Codable, Sendable, Equatable {
        let id: UUID
        let matrix: [[Double]]
        let metadata: [String: [String: Any]]
        let timestamps: [String: Date]
        let optionalData: Data?
        
        enum CodingKeys: String, CodingKey {
            case id, matrix, metadata, timestamps, optionalData
        }
        
        init(
            id: UUID = UUID(),
            matrix: [[Double]] = [[1.0, 2.0], [3.0, 4.0]],
            metadata: [String: [String: Any]] = ["info": ["version": 1, "beta": true]],
            timestamps: [String: Date] = ["created": Date(), "modified": Date()],
            optionalData: Data? = "test".data(using: .utf8)
        ) {
            self.id = id
            self.matrix = matrix
            self.metadata = metadata
            self.timestamps = timestamps
            self.optionalData = optionalData
        }
        
        // Custom encoding/decoding for Any type
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(matrix, forKey: .matrix)
            
            // Convert metadata to JSON-safe format
            var jsonMetadata: [String: [String: String]] = [:]
            for (key, value) in metadata {
                var innerDict: [String: String] = [:]
                for (innerKey, innerValue) in value {
                    if let string = innerValue as? String {
                        innerDict[innerKey] = string
                    } else if let int = innerValue as? Int {
                        innerDict[innerKey] = String(int)
                    } else if let bool = innerValue as? Bool {
                        innerDict[innerKey] = String(bool)
                    }
                }
                jsonMetadata[key] = innerDict
            }
            try container.encode(jsonMetadata, forKey: .metadata)
            
            try container.encode(timestamps, forKey: .timestamps)
            try container.encodeIfPresent(optionalData, forKey: .optionalData)
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            matrix = try container.decode([[Double]].self, forKey: .matrix)
            
            // Decode metadata back to Any format
            let jsonMetadata = try container.decode([String: [String: String]].self, forKey: .metadata)
            var decodedMetadata: [String: [String: Any]] = [:]
            for (key, value) in jsonMetadata {
                var innerDict: [String: Any] = [:]
                for (innerKey, innerValue) in value {
                    // Try to convert back to original types
                    if let int = Int(innerValue) {
                        innerDict[innerKey] = int
                    } else if innerValue == "true" {
                        innerDict[innerKey] = true
                    } else if innerValue == "false" {
                        innerDict[innerKey] = false
                    } else {
                        innerDict[innerKey] = innerValue
                    }
                }
                decodedMetadata[key] = innerDict
            }
            metadata = decodedMetadata
            
            timestamps = try container.decode([String: Date].self, forKey: .timestamps)
            optionalData = try container.decodeIfPresent(Data.self, forKey: .optionalData)
        }
        
        // Custom equality for Any type
        static func == (lhs: NestedComplexType, rhs: NestedComplexType) -> Bool {
            guard lhs.id == rhs.id,
                  lhs.matrix == rhs.matrix,
                  lhs.timestamps.count == rhs.timestamps.count,
                  lhs.optionalData == rhs.optionalData else {
                return false
            }
            
            // Compare metadata
            guard lhs.metadata.count == rhs.metadata.count else { return false }
            for (key, value) in lhs.metadata {
                guard let rhsValue = rhs.metadata[key],
                      value.count == rhsValue.count else {
                    return false
                }
                // Compare inner dictionaries
                for (innerKey, innerValue) in value {
                    guard let rhsInnerValue = rhsValue[innerKey] else { return false }
                    // Compare as strings since Any isn't Equatable
                    if String(describing: innerValue) != String(describing: rhsInnerValue) {
                        return false
                    }
                }
            }
            
            return true
        }
    }
    
    struct RecursiveType: Codable, Sendable, Equatable {
        let name: String
        let children: [RecursiveType]
        let data: Data
        let attributes: [String: String]
        
        init(name: String, children: [RecursiveType] = [], data: Data = Data(), attributes: [String: String] = [:]) {
            self.name = name
            self.children = children
            self.data = data
            self.attributes = attributes
        }
        
        static func makeTree(depth: Int, breadth: Int = 2) -> RecursiveType {
            guard depth > 0 else {
                return RecursiveType(
                    name: "leaf",
                    data: "leaf data".data(using: .utf8)!,
                    attributes: ["type": "leaf", "depth": "0"]
                )
            }
            
            let children = (0..<breadth).map { index in
                makeTree(depth: depth - 1, breadth: breadth)
            }
            
            return RecursiveType(
                name: "node-\(depth)",
                children: children,
                data: "node data at depth \(depth)".data(using: .utf8)!,
                attributes: ["type": "node", "depth": String(depth)]
            )
        }
    }
    
    // MARK: - Test Actor for Complex Types
    
    @Resolvable
    protocol ComplexTypeActor: DistributedActor where ActorSystem == ActorEdgeSystem {
        distributed func processNestedType(_ input: NestedComplexType) async throws -> NestedComplexType
        distributed func processRecursiveType(_ input: RecursiveType) async throws -> RecursiveType
        distributed func processMixedArray(_ items: [Any]) async throws -> [String]
        distributed func processLargeCollection(_ count: Int) async throws -> [TestMessage]
        distributed func processDeepNesting(_ depth: Int) async throws -> RecursiveType
    }
    
    distributed actor ComplexTypeActorImpl: ComplexTypeActor {
        typealias ActorSystem = ActorEdgeSystem
        
        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }
        
        distributed func processNestedType(_ input: NestedComplexType) async throws -> NestedComplexType {
            // Transform the input
            var newMatrix = input.matrix
            for i in 0..<newMatrix.count {
                for j in 0..<newMatrix[i].count {
                    newMatrix[i][j] *= 2.0
                }
            }
            
            var newTimestamps = input.timestamps
            newTimestamps["processed"] = Date()
            
            return NestedComplexType(
                id: input.id,
                matrix: newMatrix,
                metadata: input.metadata,
                timestamps: newTimestamps,
                optionalData: input.optionalData.map { Data($0.reversed()) }
            )
        }
        
        distributed func processRecursiveType(_ input: RecursiveType) async throws -> RecursiveType {
            // Add a processing marker to each node
            let processedChildren = try await withThrowingTaskGroup(of: RecursiveType.self) { group in
                for child in input.children {
                    group.addTask {
                        try await self.processRecursiveType(child)
                    }
                }
                
                var results: [RecursiveType] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            var newAttributes = input.attributes
            newAttributes["processed"] = "true"
            newAttributes["timestamp"] = ISO8601DateFormatter().string(from: Date())
            
            return RecursiveType(
                name: "processed-\(input.name)",
                children: processedChildren,
                data: input.data,
                attributes: newAttributes
            )
        }
        
        distributed func processMixedArray(_ items: [Any]) async throws -> [String] {
            // This would normally require custom serialization
            // For testing, we'll simulate it
            return items.map { String(describing: $0) }
        }
        
        distributed func processLargeCollection(_ count: Int) async throws -> [TestMessage] {
            return (0..<count).map { index in
                TestMessage(
                    id: "large-\(index)",
                    content: "Message \(index) in large collection"
                )
            }
        }
        
        distributed func processDeepNesting(_ depth: Int) async throws -> RecursiveType {
            return RecursiveType.makeTree(depth: depth)
        }
    }
    
    // MARK: - Tests
    
    @Test("Nested complex type serialization")
    func nestedComplexTypeSerialization() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["complex-type-actor"])
        
        let actor = ComplexTypeActorImpl(actorSystem: server)
        let remoteActor = try $ComplexTypeActor.resolve(id: actor.id, using: client)
        
        let input = NestedComplexType(
            matrix: [[1.5, 2.5, 3.5], [4.5, 5.5, 6.5]],
            metadata: [
                "config": ["version": 2, "enabled": true, "name": "test"],
                "stats": ["count": 100, "active": false]
            ],
            timestamps: [
                "start": Date(timeIntervalSince1970: 1000000),
                "end": Date(timeIntervalSince1970: 2000000)
            ],
            optionalData: "complex data".data(using: .utf8)
        )
        
        let result = try await remoteActor.processNestedType(input)
        
        // Verify matrix was doubled
        #expect(result.matrix[0][0] == 3.0)
        #expect(result.matrix[1][2] == 13.0)
        
        // Verify metadata preserved
        #expect(result.metadata.count == input.metadata.count)
        
        // Verify new timestamp added
        #expect(result.timestamps.count == 3)
        #expect(result.timestamps["processed"] != nil)
        
        // Verify optional data was reversed
        if let resultData = result.optionalData,
           let originalData = input.optionalData {
            #expect(resultData == Data(originalData.reversed()))
        }
    }
    
    @Test("Recursive type processing")
    func recursiveTypeProcessing() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["recursive-actor"])
        
        let actor = ComplexTypeActorImpl(actorSystem: server)
        let remoteActor = try $ComplexTypeActor.resolve(id: actor.id, using: client)
        
        let tree = RecursiveType.makeTree(depth: 3, breadth: 2)
        let processed = try await remoteActor.processRecursiveType(tree)
        
        // Verify processing
        #expect(processed.name == "processed-node-3")
        #expect(processed.attributes["processed"] == "true")
        #expect(processed.attributes["timestamp"] != nil)
        
        // Check children were processed
        #expect(processed.children.count == 2)
        #expect(processed.children[0].name == "processed-node-2")
        
        // Check leaf nodes
        let leaf = processed.children[0].children[0].children[0]
        #expect(leaf.name == "processed-leaf")
        #expect(leaf.attributes["processed"] == "true")
    }
    
    @Test("Large collection handling")
    func largeCollectionHandling() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["large-collection-actor"])
        
        let actor = ComplexTypeActorImpl(actorSystem: server)
        let remoteActor = try $ComplexTypeActor.resolve(id: actor.id, using: client)
        
        let largeCount = 1000
        let results = try await remoteActor.processLargeCollection(largeCount)
        
        #expect(results.count == largeCount)
        #expect(results[0].id == "large-0")
        #expect(results[999].id == "large-999")
        
        // Verify all messages are unique
        let uniqueIDs = Set(results.map { $0.id })
        #expect(uniqueIDs.count == largeCount)
    }
    
    @Test("Deep nesting limits")
    func deepNestingLimits() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["deep-nesting-actor"])
        
        let actor = ComplexTypeActorImpl(actorSystem: server)
        let remoteActor = try $ComplexTypeActor.resolve(id: actor.id, using: client)
        
        // Test various depths
        for depth in [5, 10, 15] {
            let tree = try await remoteActor.processDeepNesting(depth)
            
            // Verify tree structure
            var currentNode = tree
            var actualDepth = 0
            
            while !currentNode.children.isEmpty {
                actualDepth += 1
                currentNode = currentNode.children[0]
            }
            
            #expect(actualDepth == depth)
        }
    }
    
    @Test("Serialization performance with complex types", .timeLimit(.minutes(1)))
    func serializationPerformanceComplexTypes() async throws {
        let serialization = SerializationSystem()
        
        let complexData = NestedComplexType(
            matrix: Array(repeating: Array(repeating: 1.5, count: 100), count: 100),
            metadata: Dictionary(uniqueKeysWithValues: (0..<50).map { 
                ("key\($0)", ["value": $0, "enabled": $0 % 2 == 0])
            }),
            timestamps: Dictionary(uniqueKeysWithValues: (0..<20).map {
                ("time\($0)", Date(timeIntervalSince1970: Double($0 * 1000)))
            })
        )
        
        let iterations = 100
        let startTime = ContinuousClock.now
        
        for _ in 0..<iterations {
            let serialized = try serialization.serialize(complexData)
            let deserialized = try serialization.deserialize(
                serialized.data,
                as: NestedComplexType.self,
                using: serialized.manifest
            )
            
            // Basic validation
            #expect(deserialized.matrix.count == complexData.matrix.count)
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let operationsPerSecond = Double(iterations * 2) / duration.timeInterval
        
        // Complex types should still maintain reasonable performance
        #expect(operationsPerSecond > 100, "Complex type serialization too slow: \(operationsPerSecond) ops/sec")
    }
    
    @Test("Edge cases in complex types")
    func edgeCasesInComplexTypes() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["edge-case-actor"])
        
        let actor = ComplexTypeActorImpl(actorSystem: server)
        let remoteActor = try $ComplexTypeActor.resolve(id: actor.id, using: client)
        
        // Test with empty structures
        let emptyNested = NestedComplexType(
            matrix: [],
            metadata: [:],
            timestamps: [:],
            optionalData: nil
        )
        
        let result1 = try await remoteActor.processNestedType(emptyNested)
        #expect(result1.matrix.isEmpty)
        #expect(result1.metadata.isEmpty)
        #expect(result1.optionalData == nil)
        
        // Test with single-node recursive type
        let singleNode = RecursiveType(name: "single", data: Data())
        let result2 = try await remoteActor.processRecursiveType(singleNode)
        #expect(result2.name == "processed-single")
        #expect(result2.children.isEmpty)
        
        // Test with very large collection
        let veryLarge = try await remoteActor.processLargeCollection(10000)
        #expect(veryLarge.count == 10000)
    }
}