import Foundation
import NIO

extension Serialization {
    /// A zero-copy buffer abstraction for serialization
    public enum Buffer: Sendable {
        case data(Data)
        case byteBuffer(ByteBuffer)
        
        
        /// Get the number of readable bytes
        public var readableBytes: Int {
            switch self {
            case .data(let data):
                return data.count
            case .byteBuffer(let buffer):
                return buffer.readableBytes
            }
        }
        
        /// Read all data (may involve copying)
        public func readData() -> Data {
            switch self {
            case .data(let data):
                return data
            case .byteBuffer(var buffer):
                return buffer.readData(length: buffer.readableBytes) ?? Data()
            }
        }
        
        /// Access bytes without copying if possible
        public func withUnsafeReadableBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
            switch self {
            case .data(let data):
                return try data.withUnsafeBytes(body)
            case .byteBuffer(let buffer):
                return try buffer.withUnsafeReadableBytes(body)
            }
        }
        
        /// Write to a ByteBuffer
        public func write(to buffer: inout ByteBuffer) {
            switch self {
            case .data(let data):
                buffer.writeBytes(data)
            case .byteBuffer(let source):
                buffer.writeImmutableBuffer(source)
            }
        }
        
        /// Encode for wire format (returns Data for protobuf compatibility)
        public func encode() -> Data {
            readData()
        }
        
        /// Create from encoded data
        public static func decode(_ data: Data) -> Buffer {
            .data(data)
        }
    }
}

// MARK: - Buffer Creation Helpers

extension Serialization.Buffer {
    /// Create an empty buffer
    public static var empty: Serialization.Buffer {
        .data(Data())
    }
    
    /// Create a buffer from a string
    public static func string(_ string: String, encoding: String.Encoding = .utf8) -> Serialization.Buffer? {
        guard let data = string.data(using: encoding) else { return nil }
        return .data(data)
    }
    
    /// Create a buffer with specific capacity using ByteBuffer
    public static func withCapacity(_ capacity: Int) -> Serialization.Buffer {
        let allocator = ByteBufferAllocator()
        let buffer = allocator.buffer(capacity: capacity)
        return .byteBuffer(buffer)
    }
}

// MARK: - Reading Primitives

extension Serialization.Buffer {
    /// Read an integer from the buffer
    public func readInteger<T: FixedWidthInteger>() throws -> T {
        guard readableBytes >= MemoryLayout<T>.size else {
            throw SerializationError.deserializationFailed("Not enough bytes to read \(T.self)")
        }
        
        switch self {
        case .data(let data):
            return data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(as: T.self)
            }
        case .byteBuffer(var buffer):
            guard let value = buffer.readInteger(as: T.self) else {
                throw SerializationError.deserializationFailed("Failed to read \(T.self)")
            }
            return value
        }
    }
    
    /// Read a string from the buffer
    public func readString(length: Int, encoding: String.Encoding = .utf8) throws -> String {
        guard readableBytes >= length else {
            throw SerializationError.deserializationFailed("Not enough bytes to read string")
        }
        
        switch self {
        case .data(let data):
            guard let string = String(data: data.prefix(length), encoding: encoding) else {
                throw SerializationError.deserializationFailed("Failed to decode string")
            }
            return string
        case .byteBuffer(var buffer):
            guard let string = buffer.readString(length: length, encoding: encoding) else {
                throw SerializationError.deserializationFailed("Failed to read string")
            }
            return string
        }
    }
}