import Foundation

extension Serialization {
    /// Identifies which serializer to use, following SDA's exact numbering
    public enum SerializerID: Sendable, Hashable, Codable {
        /// Foundation's JSONEncoder/Decoder
        case foundationJSON  // = 1
        
        /// Foundation's PropertyListEncoder/Decoder with binary format
        case foundationPropertyListBinary  // = 2
        
        /// Custom JSON implementation (swift-corelibs-foundation compatible)
        case json  // = 3
        
        /// Foundation's PropertyListEncoder/Decoder with XML format
        case foundationPropertyListXML  // = 4
        
        /// Specialized serializers for primitive types (no hint needed)
        case specializedWithTypeHint  // = 200
        
        /// User-defined custom serializers
        case custom(Int)
        
        // MARK: - Codable
        
        private enum CodingKeys: String, CodingKey {
            case base, custom
        }
        
        private enum Base: Int, Codable {
            case foundationJSON = 1
            case foundationPropertyListBinary = 2
            case json = 3
            case foundationPropertyListXML = 4
            case specializedWithTypeHint = 200
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            if let custom = try container.decodeIfPresent(Int.self, forKey: .custom) {
                self = .custom(custom)
            } else {
                let base = try container.decode(Base.self, forKey: .base)
                switch base {
                case .foundationJSON:
                    self = .foundationJSON
                case .foundationPropertyListBinary:
                    self = .foundationPropertyListBinary
                case .json:
                    self = .json
                case .foundationPropertyListXML:
                    self = .foundationPropertyListXML
                case .specializedWithTypeHint:
                    self = .specializedWithTypeHint
                }
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .foundationJSON:
                try container.encode(Base.foundationJSON, forKey: .base)
            case .foundationPropertyListBinary:
                try container.encode(Base.foundationPropertyListBinary, forKey: .base)
            case .json:
                try container.encode(Base.json, forKey: .base)
            case .foundationPropertyListXML:
                try container.encode(Base.foundationPropertyListXML, forKey: .base)
            case .specializedWithTypeHint:
                try container.encode(Base.specializedWithTypeHint, forKey: .base)
            case .custom(let id):
                try container.encode(id, forKey: .custom)
            }
        }
    }
}

// MARK: - Convenience Properties

extension Serialization.SerializerID {
    /// The raw integer value for wire format compatibility
    public var rawValue: Int {
        switch self {
        case .foundationJSON:
            return 1
        case .foundationPropertyListBinary:
            return 2
        case .json:
            return 3
        case .foundationPropertyListXML:
            return 4
        case .specializedWithTypeHint:
            return 200
        case .custom(let id):
            return id
        }
    }
    
    /// Create from raw value
    public init?(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .foundationJSON
        case 2:
            self = .foundationPropertyListBinary
        case 3:
            self = .json
        case 4:
            self = .foundationPropertyListXML
        case 200:
            self = .specializedWithTypeHint
        default:
            // Assume values > 1000 are custom
            if rawValue > 1000 {
                self = .custom(rawValue)
            } else {
                return nil
            }
        }
    }
    
    /// Check if this is a built-in serializer
    public var isBuiltIn: Bool {
        switch self {
        case .foundationJSON, .foundationPropertyListBinary, .json,
             .foundationPropertyListXML, .specializedWithTypeHint:
            return true
        case .custom:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension Serialization.SerializerID: CustomStringConvertible {
    public var description: String {
        switch self {
        case .foundationJSON:
            return "foundationJSON"
        case .foundationPropertyListBinary:
            return "foundationPropertyListBinary"
        case .json:
            return "json"
        case .foundationPropertyListXML:
            return "foundationPropertyListXML"
        case .specializedWithTypeHint:
            return "specializedWithTypeHint"
        case .custom(let id):
            return "custom(\(id))"
        }
    }
}