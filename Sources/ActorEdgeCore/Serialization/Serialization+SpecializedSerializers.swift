import Foundation
import NIO

// MARK: - Specialized Serializers for Primitive Types

extension Serialization {
    /// Base class for specialized serializers
    public struct SpecializedSerializer<T: Codable & Sendable>: AnySerializer {
        public let serializerID: SerializerID = .specializedWithTypeHint
        private let encode: @Sendable (T) throws -> Buffer
        private let decode: @Sendable (Buffer) throws -> T
        
        init(
            encode: @escaping @Sendable (T) throws -> Buffer,
            decode: @escaping @Sendable (Buffer) throws -> T
        ) {
            self.encode = encode
            self.decode = decode
        }
        
        public func serialize(any value: Any, context: Context) throws -> Buffer {
            guard let typedValue = value as? T else {
                throw SerializationError.deserializationFailed(
                    "Expected \(T.self), got \(type(of: value))"
                )
            }
            return try encode(typedValue)
        }
        
        public func deserialize(buffer: Buffer, context: Context) throws -> Any {
            return try decode(buffer)
        }
    }
}

// MARK: - String Serializer

extension Serialization {
    public static let stringSerializer = SpecializedSerializer<String>(
        encode: { string in
            guard let data = string.data(using: .utf8) else {
                throw SerializationError.deserializationFailed("Failed to encode string as UTF-8")
            }
            return .data(data)
        },
        decode: { buffer in
            let data = buffer.readData()
            guard let string = String(data: data, encoding: .utf8) else {
                throw SerializationError.deserializationFailed("Failed to decode UTF-8 string")
            }
            return string
        }
    )
}

// MARK: - Integer Serializers

extension Serialization {
    public static let intSerializer = SpecializedSerializer<Int>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 8)
            buffer.writeInteger(Int64(value), endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            guard buffer.readableBytes >= 8 else {
                throw SerializationError.deserializationFailed("Not enough bytes for Int")
            }
            let int64: Int64 = try buffer.readInteger()
            return Int(int64)
        }
    )
    
    public static let int32Serializer = SpecializedSerializer<Int32>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 4)
            buffer.writeInteger(value, endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            try buffer.readInteger() as Int32
        }
    )
    
    public static let int64Serializer = SpecializedSerializer<Int64>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 8)
            buffer.writeInteger(value, endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            try buffer.readInteger() as Int64
        }
    )
}

// MARK: - Unsigned Integer Serializers

extension Serialization {
    public static let uintSerializer = SpecializedSerializer<UInt>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 8)
            buffer.writeInteger(UInt64(value), endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            guard buffer.readableBytes >= 8 else {
                throw SerializationError.deserializationFailed("Not enough bytes for UInt")
            }
            let uint64: UInt64 = try buffer.readInteger()
            return UInt(uint64)
        }
    )
    
    public static let uint32Serializer = SpecializedSerializer<UInt32>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 4)
            buffer.writeInteger(value, endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            try buffer.readInteger() as UInt32
        }
    )
    
    public static let uint64Serializer = SpecializedSerializer<UInt64>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 8)
            buffer.writeInteger(value, endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            try buffer.readInteger() as UInt64
        }
    )
}

// MARK: - Boolean Serializer

extension Serialization {
    public static let boolSerializer = SpecializedSerializer<Bool>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 1)
            buffer.writeInteger(UInt8(value ? 1 : 0))
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            let byte: UInt8 = try buffer.readInteger()
            return byte != 0
        }
    )
}

// MARK: - Floating Point Serializers

extension Serialization {
    public static let doubleSerializer = SpecializedSerializer<Double>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 8)
            buffer.writeInteger(value.bitPattern, endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            let bits: UInt64 = try buffer.readInteger()
            return Double(bitPattern: bits)
        }
    )
    
    public static let floatSerializer = SpecializedSerializer<Float>(
        encode: { value in
            var buffer = ByteBufferAllocator().buffer(capacity: 4)
            buffer.writeInteger(value.bitPattern, endianness: .little)
            return .byteBuffer(buffer)
        },
        decode: { buffer in
            let bits: UInt32 = try buffer.readInteger()
            return Float(bitPattern: bits)
        }
    )
}

// MARK: - Data Serializer

extension Serialization {
    public static let dataSerializer = SpecializedSerializer<Data>(
        encode: { data in
            .data(data)
        },
        decode: { buffer in
            buffer.readData()
        }
    )
}

// MARK: - Specialized Dispatcher

extension Serialization {
    /// Dispatcher for specialized serializers
    public struct SpecializedDispatcher: AnySerializer {
        public let serializerID: SerializerID = .specializedWithTypeHint
        
        private let specializedSerializers: [String: any AnySerializer]
        
        init() {
            var serializers: [String: any AnySerializer] = [:]
            for (type, serializer) in Serialization.specializedSerializers {
                // Store both demangled and mangled names as keys
                let demangledName = String(reflecting: type)
                serializers[demangledName] = serializer
                
                // Also store with mangled name if available
                if let mangledName = _mangledTypeName(type) {
                    serializers[mangledName] = serializer
                }
            }
            self.specializedSerializers = serializers
        }
        
        public func serialize(any value: Any, context: Context) throws -> Buffer {
            // Get type hint from manifest or infer from value
            let typeName = context.manifest.hint ?? String(reflecting: type(of: value))
            
            guard let serializer = specializedSerializers[typeName] else {
                throw SerializationError.serializerNotFound(.specializedWithTypeHint)
            }
            
            return try serializer.serialize(any: value, context: context)
        }
        
        public func deserialize(buffer: Buffer, context: Context) throws -> Any {
            guard let hint = context.manifest.hint else {
                throw SerializationError.unknownManifest(context.manifest)
            }
            
            guard let serializer = specializedSerializers[hint] else {
                throw SerializationError.serializerNotFound(.specializedWithTypeHint)
            }
            
            return try serializer.deserialize(buffer: buffer, context: context)
        }
    }
}

// MARK: - Registration Helper

extension Serialization {
    /// Get all built-in specialized serializers
    public static var specializedSerializers: [(Any.Type, any AnySerializer)] {
        [
            (String.self, stringSerializer),
            (Int.self, intSerializer),
            (Int32.self, int32Serializer),
            (Int64.self, int64Serializer),
            (UInt.self, uintSerializer),
            (UInt32.self, uint32Serializer),
            (UInt64.self, uint64Serializer),
            (Bool.self, boolSerializer),
            (Double.self, doubleSerializer),
            (Float.self, floatSerializer),
            (Data.self, dataSerializer)
        ]
    }
}