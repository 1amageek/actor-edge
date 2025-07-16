import Distributed
import Foundation

/// Binary decoder for distributed actor method invocations
public struct BinaryInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    private var buffer: Data
    private var offset: Int = 0
    private var argumentCount: UInt32 = 0
    private var genericSubstitutionCount: UInt32 = 0
    private var currentArgumentIndex: UInt32 = 0
    private var currentGenericIndex: UInt32 = 0
    
    /// Initialize decoder with binary data
    public init(data: Data) throws {
        self.buffer = data
        try parseHeader()
    }
    
    /// Initialize with system and payload for server-side decoding
    public init(system: ActorEdgeSystem, payload: Data) {
        self.buffer = payload
        do {
            try parseHeader()
        } catch {
            // If parsing fails, reset to empty state
            self.offset = 0
            self.argumentCount = 0
            self.genericSubstitutionCount = 0
        }
    }
    
    private mutating func parseHeader() throws {
        // Check magic bytes
        guard buffer.count >= 13 else {
            throw ActorEdgeError.invalidFormat("Buffer too small for header")
        }
        
        let magic = String(data: buffer[0..<4], encoding: .utf8)
        guard magic == "AEDG" else {
            throw ActorEdgeError.invalidFormat("Invalid magic bytes")
        }
        offset += 4
        
        // Check version
        let version = buffer[offset]
        guard version == 1 else {
            throw ActorEdgeError.invalidFormat("Unsupported version: \(version)")
        }
        offset += 1
        
        // Read counts
        argumentCount = try readUInt32()
        genericSubstitutionCount = try readUInt32()
    }
    
    public mutating func decodeGenericSubstitutions() throws -> [any Any.Type] {
        var types: [any Any.Type] = []
        
        for _ in 0..<genericSubstitutionCount {
            _ = try readString()
            // In a real implementation, you'd use a type registry
            // For now, we return nil types
            types.append(type(of: () as Any).self)
        }
        
        return types
    }
    
    public mutating func decodeNextArgument<Argument>() throws -> Argument where Argument: SerializationRequirement {
        guard currentArgumentIndex < argumentCount else {
            throw ActorEdgeError.missingArgument
        }
        
        // Read has label flag
        let hasLabel = try readBool()
        
        // Read label if present
        if hasLabel {
            _ = try readString() // Discard label for now
        }
        
        // Read name
        _ = try readString() // Discard name for now
        
        // Read value data
        let valueData = try readData()
        
        // Decode using JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Argument.self, from: valueData)
        
        currentArgumentIndex += 1
        return value
    }
    
    public mutating func decodeReturnType() throws -> Any.Type? {
        // Skip return type if present
        if offset < buffer.count {
            _ = try? readString()
        }
        return nil
    }
    
    public mutating func decodeErrorType() throws -> Any.Type? {
        // Skip error type if present
        if offset < buffer.count {
            _ = try? readString()
        }
        return nil
    }
    
    // MARK: - Binary Reading Helpers
    
    private mutating func readBool() throws -> Bool {
        guard offset < buffer.count else {
            throw ActorEdgeError.invalidFormat("Unexpected end of buffer")
        }
        let value = buffer[offset] != 0
        offset += 1
        return value
    }
    
    private mutating func readString() throws -> String {
        let length = try readUInt32()
        guard offset + Int(length) <= buffer.count else {
            throw ActorEdgeError.invalidFormat("String length exceeds buffer")
        }
        
        let data = buffer[offset..<(offset + Int(length))]
        guard let string = String(data: data, encoding: .utf8) else {
            throw ActorEdgeError.invalidFormat("Invalid UTF-8 string")
        }
        
        offset += Int(length)
        return string
    }
    
    private mutating func readData() throws -> Data {
        let length = try readUInt32()
        guard offset + Int(length) <= buffer.count else {
            throw ActorEdgeError.invalidFormat("Data length exceeds buffer")
        }
        
        let data = buffer[offset..<(offset + Int(length))]
        offset += Int(length)
        return data
    }
    
    private mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= buffer.count else {
            throw ActorEdgeError.invalidFormat("Cannot read UInt32")
        }
        
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { valueBytes in
            buffer[offset..<(offset + 4)].copyBytes(to: valueBytes)
        }
        value = value.littleEndian
        
        offset += 4
        return value
    }
}