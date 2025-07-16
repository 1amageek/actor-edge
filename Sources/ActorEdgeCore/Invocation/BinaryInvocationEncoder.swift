import Distributed
import Foundation

/// Binary encoder for distributed actor method invocations
/// Uses a compact binary format for better performance
public struct BinaryInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    private var buffer = Data()
    private var argumentCount: UInt32 = 0
    private var genericSubstitutionCount: UInt32 = 0
    
    public init() {}
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        let typeName = String(reflecting: type)
        try writeString(typeName)
        genericSubstitutionCount += 1
    }
    
    public mutating func recordArgument<Argument>(
        _ argument: RemoteCallArgument<Argument>
    ) throws where Argument: SerializationRequirement {
        // Write argument label if present
        if let label = argument.label {
            try writeBool(true)
            try writeString(label)
        } else {
            try writeBool(false)
        }
        
        // Write argument name
        try writeString(argument.name)
        
        // Write argument value
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let valueData = try encoder.encode(argument.value)
        try writeData(valueData)
        
        argumentCount += 1
    }
    
    public mutating func recordReturnType<R>(
        _ returnType: R.Type
    ) throws where R: SerializationRequirement {
        let typeName = String(reflecting: returnType)
        try writeString(typeName)
    }
    
    public mutating func recordErrorType<E: Error>(_ errorType: E.Type) throws {
        let typeName = String(reflecting: errorType)
        try writeString(typeName)
    }
    
    public mutating func doneRecording() throws {
        // Nothing to do here for binary format
    }
    
    /// Get the encoded binary data
    public func getEncodedData() throws -> Data {
        var finalBuffer = Data()
        
        // Write header
        finalBuffer.append(contentsOf: "AEDG".utf8) // Magic bytes: ActorEDGe
        finalBuffer.append(UInt8(1)) // Version
        
        // Write counts
        finalBuffer.append(contentsOf: withUnsafeBytes(of: argumentCount.littleEndian) { Data($0) })
        finalBuffer.append(contentsOf: withUnsafeBytes(of: genericSubstitutionCount.littleEndian) { Data($0) })
        
        // Write the actual data
        finalBuffer.append(buffer)
        
        return finalBuffer
    }
    
    // MARK: - Binary Writing Helpers
    
    private mutating func writeBool(_ value: Bool) throws {
        buffer.append(value ? 1 : 0)
    }
    
    private mutating func writeString(_ string: String) throws {
        let data = Data(string.utf8)
        try writeUInt32(UInt32(data.count))
        buffer.append(data)
    }
    
    private mutating func writeData(_ data: Data) throws {
        try writeUInt32(UInt32(data.count))
        buffer.append(data)
    }
    
    private mutating func writeUInt32(_ value: UInt32) throws {
        buffer.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }
}

// MARK: - Wire Format Documentation
/*
 Binary Wire Format:
 
 Header (9 bytes):
 - Magic: 4 bytes "AEDG"
 - Version: 1 byte (currently 0x01)
 - Argument count: 4 bytes (little-endian UInt32)
 - Generic substitution count: 4 bytes (little-endian UInt32)
 
 Body:
 - Generic substitutions (repeated):
   - Type name length: 4 bytes (little-endian UInt32)
   - Type name: N bytes UTF-8
 
 - Arguments (repeated):
   - Has label: 1 byte (0x00 or 0x01)
   - Label (if has label):
     - Label length: 4 bytes (little-endian UInt32)
     - Label: N bytes UTF-8
   - Name length: 4 bytes (little-endian UInt32)
   - Name: N bytes UTF-8
   - Value data length: 4 bytes (little-endian UInt32)
   - Value data: N bytes (JSON encoded)
 
 - Return type (optional):
   - Type name length: 4 bytes (little-endian UInt32)
   - Type name: N bytes UTF-8
 
 - Error type (optional):
   - Type name length: 4 bytes (little-endian UInt32)
   - Type name: N bytes UTF-8
 */