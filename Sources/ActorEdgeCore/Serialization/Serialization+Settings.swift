import Foundation
import NIOConcurrencyHelpers

extension Serialization {
    /// Thread-safe settings and registry for serialization
    public final class Settings: Sendable {
        /// Default serializer ID for Codable types
        public var defaultSerializerID: SerializerID {
            _defaultSerializerID.withLockedValue { $0 }
        }
        
        // MARK: - Private State
        
        private let _defaultSerializerID = NIOLockedValueBox<SerializerID>(.json)
        private let _serializers = NIOLockedValueBox<[SerializerID: any AnySerializer]>([:])
        private let _typeToManifest = NIOLockedValueBox<[ObjectIdentifier: Manifest]>([:])
        private let _manifestToType = NIOLockedValueBox<[Manifest: Any.Type]>([:])
        private let _specializedTypes = NIOLockedValueBox<Set<ObjectIdentifier>>(Set())
        
        // MARK: - Initialization
        
        public init() {
            // Register built-in serializers
            registerBuiltInSerializers()
        }
        
        // MARK: - Serializer Registration
        
        /// Register a serializer
        public func registerSerializer(_ serializer: any AnySerializer, for type: Any.Type? = nil) {
            _serializers.withLockedValue { serializers in
                serializers[serializer.serializerID] = serializer
            }
            
            // If type is provided, register type mapping
            if let type = type {
                let manifest = Manifest(
                    serializerID: serializer.serializerID,
                    hint: serializer.requiresTypeHint ? String(reflecting: type) : nil
                )
                registerType(type, manifest: manifest)
                
                // Mark as specialized if appropriate
                if serializer.serializerID == .specializedWithTypeHint {
                    _specializedTypes.withLockedValue { types in
                        _ = types.insert(ObjectIdentifier(type))
                    }
                }
            }
        }
        
        /// Register a Codable type with default serializer
        public func registerCodableSerializer<T: Codable & Sendable>(for type: T.Type) {
            let manifest = Manifest(
                serializerID: defaultSerializerID,
                hint: String(reflecting: type)
            )
            registerType(type, manifest: manifest)
        }
        
        /// Get a serializer by ID
        public func serializer(for id: SerializerID) throws -> any AnySerializer {
            let serializer = _serializers.withLockedValue { serializers in
                serializers[id]
            }
            
            guard let serializer = serializer else {
                throw SerializationError.serializerNotFound(id)
            }
            
            return serializer
        }
        
        /// Check if there's a specialized serializer for a type
        public func hasSpecializedSerializer(for type: Any.Type) -> Bool {
            _specializedTypes.withLockedValue { types in
                types.contains(ObjectIdentifier(type))
            }
        }
        
        // MARK: - Type Registration
        
        /// Register a type with its manifest
        public func registerType(_ type: Any.Type, manifest: Manifest) {
            let typeID = ObjectIdentifier(type)
            
            _typeToManifest.withLockedValue { mapping in
                mapping[typeID] = manifest
            }
            
            _manifestToType.withLockedValue { mapping in
                mapping[manifest] = type
            }
        }
        
        /// Get manifest for a type
        public func manifest(for type: Any.Type) -> Manifest? {
            let typeID = ObjectIdentifier(type)
            return _typeToManifest.withLockedValue { mapping in
                mapping[typeID]
            }
        }
        
        /// Get type for a manifest
        public func type(for manifest: Manifest) -> Any.Type? {
            _manifestToType.withLockedValue { mapping in
                mapping[manifest]
            }
        }
        
        // MARK: - Configuration
        
        /// Set the default serializer ID
        public func setDefaultSerializerID(_ id: SerializerID) {
            _defaultSerializerID.withLockedValue { value in
                value = id
            }
        }
        
        // MARK: - Private Helpers
        
        private func registerBuiltInSerializers() {
            // Register Codable serializers
            let jsonSerializer = CodableSerializer(serializerID: .json)
            let foundationSerializer = FoundationJSONSerializer()
            
            registerSerializer(jsonSerializer)
            registerSerializer(foundationSerializer)
            
            // Register specialized dispatcher
            let specializedDispatcher = SpecializedDispatcher()
            _serializers.withLockedValue { $0[.specializedWithTypeHint] = specializedDispatcher }
            
            // Register specialized types (mark them as specialized)
            for (type, _) in Serialization.specializedSerializers {
                _specializedTypes.withLockedValue { types in
                    _ = types.insert(ObjectIdentifier(type))
                }
            }
            
            // Register common ActorEdge types
            registerType(InvocationMessage.self, manifest: Manifest(serializerID: .json, hint: "ActorEdgeCore.InvocationMessage"))
        }
    }
}

// MARK: - Debugging Support

extension Serialization.Settings {
    /// Get debug information about registered serializers
    public var debugInfo: String {
        let serializerCount = _serializers.withLockedValue { $0.count }
        let typeCount = _typeToManifest.withLockedValue { $0.count }
        let specializedCount = _specializedTypes.withLockedValue { $0.count }
        
        return """
        Serialization Settings:
        - Registered serializers: \(serializerCount)
        - Registered types: \(typeCount)
        - Specialized types: \(specializedCount)
        - Default serializer: \(defaultSerializerID)
        """
    }
    
    /// List all registered serializer IDs
    public var registeredSerializerIDs: [Serialization.SerializerID] {
        _serializers.withLockedValue { serializers in
            Array(serializers.keys).sorted { $0.rawValue < $1.rawValue }
        }
    }
}