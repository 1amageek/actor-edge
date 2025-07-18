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
