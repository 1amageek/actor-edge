import Foundation
@_spi(Reflection) import Swift

// MARK: - Swift Runtime Functions (safe)
// swift_getMangledTypeName is an ABI‑stable symbol that can still be used to obtain the mangled
// name of a known type. It is *not* reserved in the same way as the context‑sensitive resolver,
// so we keep it for diagnostic purposes only.
@_silgen_name("swift_getMangledTypeName")
@usableFromInline
internal func _swift_getMangledTypeName(_ type: Any.Type,
                                        _ qualified: Bool) -> UnsafePointer<UInt8>?

// MARK: - Mangled Type Names

/// Return the fully‑qualified *mangled* name for the supplied type, or `nil` if it cannot be
/// obtained (for example, anonymous or generic contextual types).
@usableFromInline
internal func _mangledTypeName(_ type: Any.Type) -> String? {
    guard let ptr = _swift_getMangledTypeName(type, /*qualified:*/ true) else { return nil }
    return String(cString: ptr)
}

// MARK: - Demangled Type Names

/// Human‑readable type name identical to `String(reflecting:)`, kept for consistency with the
/// older API used throughout the codebase.
@usableFromInline
internal func _typeName(_ type: Any.Type) -> String {
    String(reflecting: type)
}

// MARK: - Type Resolution (swift-distributed-actors compatible)

/// Swift runtime function for type resolution
@_silgen_name("swift_getTypeByMangledNameInContext")
internal func _swift_getTypeByMangledNameInContext(
    _ name: UnsafePointer<CChar>,
    _ nameLength: Int,
    _ genericContext: UnsafeRawPointer?,
    _ genericArguments: UnsafePointer<UnsafeRawPointer>?
) -> Any.Type?

/// swift-distributed-actors準拠の型解決
@usableFromInline
internal func _typeByName(_ typeName: String) -> Any.Type? {
    print("🔵 [TYPE_RESOLUTION] Attempting to resolve: \(typeName)")
    
    // 1. Mangled nameの場合、直接Swift runtimeで解決
    if typeName.hasPrefix("$") || (typeName.count > 10 && typeName.allSatisfy({ $0.isLetter || $0.isNumber })) {
        if let type = typeName.withCString({ namePtr in
            _swift_getTypeByMangledNameInContext(
                namePtr,
                typeName.utf8.count,
                nil,
                nil
            )
        }) {
            print("🟢 [TYPE_RESOLUTION] Resolved: \(typeName) -> \(type)")
            return type
        }
    }
    
    // 2. ビルトイン型の最適化
    if let builtinType = _resolveBuiltinType(typeName) {
        print("🟢 [TYPE_RESOLUTION] Builtin: \(typeName) -> \(builtinType)")
        return builtinType
    }
    
    // 3. Swift runtime での一般解決
    let result = typeName.withCString { namePtr in
        _swift_getTypeByMangledNameInContext(
            namePtr,
            typeName.utf8.count,
            nil,
            nil
        )
    }
    
    if let type = result {
        print("🟢 [TYPE_RESOLUTION] Runtime: \(typeName) -> \(type)")
        return type
    }
    
    print("🔴 [TYPE_RESOLUTION] Failed: \(typeName)")
    return nil
}

private func _resolveBuiltinType(_ typeName: String) -> Any.Type? {
    switch typeName {
    case "Swift.String", "String":
        return String.self
    case "Swift.Int", "Int":
        return Int.self
    case "Swift.Double", "Double":
        return Double.self
    case "Swift.Bool", "Bool":
        return Bool.self
    case "Swift.Float", "Float":
        return Float.self
    case "Foundation.Date", "Date":
        return Date.self
    case "Foundation.Data", "Data":
        return Data.self
    case "Foundation.URL", "URL":
        return URL.self
    case "Foundation.UUID", "UUID":
        return UUID.self
    case "Swift.Array<Swift.String>", "Array<String>", "[String]":
        return [String].self
    case "Swift.Array<Swift.Int>", "Array<Int>", "[Int]":
        return [Int].self
    case "Swift.Dictionary<Swift.String, Swift.String>", "Dictionary<String, String>":
        return [String: String].self
    default:
        return nil
    }
}

