import Foundation

// MARK: - Swift Runtime Functions

// swift_getMangledTypeName is an internal stdlib function with ABI-stable symbol name
@_silgen_name("swift_getMangledTypeName")
@usableFromInline
internal func _swift_getMangledTypeName(_ type: Any.Type,
                                      _ qualified: Bool) -> UnsafePointer<UInt8>?

// swift_getTypeByMangledNameInContext is used to resolve types from mangled names
// This is declared in the Swift runtime but not exposed publicly
@_silgen_name("swift_getTypeByMangledNameInContext")
@usableFromInline
internal func _swift_getTypeByMangledNameInContext(
    _ name: UnsafePointer<UInt8>,
    _ nameLength: Int,
    _ context: UnsafeRawPointer?,
    _ genericArgs: UnsafeRawPointer?
) -> Any.Type?

// MARK: - Mangled Type Names

/// Get the mangled type name for a type
/// This uses Swift's internal API to get the ABI-stable mangled name
@usableFromInline
internal func _mangledTypeName(_ type: Any.Type) -> String? {
    guard let ptr = _swift_getMangledTypeName(type, /*qualified:*/ true) else { return nil }
    return String(cString: ptr)
}

// MARK: - Type Name Utilities

/// Get a human-readable type name (demangled)
@usableFromInline
internal func _typeName(_ type: Any.Type) -> String {
    String(reflecting: type)
}