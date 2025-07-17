import Foundation

/// An abstraction for byte containers to minimize allocations and copies
/// Based on swift-distributed-actors Serialization.Buffer
public enum SerializationBuffer: Sendable {
    /// Store serialized data as Foundation.Data
    case data(Data)
    
    // Future extension: ByteBuffer support
    // case byteBuffer(ByteBuffer)
    
    /// The number of readable bytes in the buffer
    public var count: Int {
        switch self {
        case .data(let data):
            return data.count
        }
    }
    
    /// Read the buffer as Data
    /// - Returns: The buffer contents as Data
    public func readData() -> Data {
        switch self {
        case .data(let data):
            return data
        }
    }
    
    /// Check if the buffer is empty
    public var isEmpty: Bool {
        count == 0
    }
}

// MARK: - Equatable
extension SerializationBuffer: Equatable {}

// MARK: - Initialization Convenience
extension SerializationBuffer {
    /// Create a buffer from a Codable value using JSON encoding
    /// - Parameter value: The value to encode
    /// - Returns: A buffer containing the encoded data
    public static func from<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> SerializationBuffer {
        let data = try encoder.encode(value)
        return .data(data)
    }
    
    /// Decode a value from the buffer using JSON decoding
    /// - Parameters:
    ///   - type: The type to decode
    ///   - decoder: The JSON decoder to use
    /// - Returns: The decoded value
    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let data = readData()
        return try decoder.decode(type, from: data)
    }
}