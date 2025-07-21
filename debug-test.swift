import Foundation

// Test type resolution
struct TestMessage: Codable {
    let id: String
}

let types = [
    "Swift.String",
    "Swift.Int", 
    "Swift.Dictionary<Swift.String, Swift.Int>",
    "SampleChatShared.Message",
    "TestMessage"
]

print("Testing type name resolution:")
for typeName in types {
    print("  \(typeName) -> ", terminator: "")
    
    // Simulate what _typeByName does
    switch typeName {
    case "Swift.String", "String":
        print("String.self ✓")
    case "Swift.Int", "Int":
        print("Int.self ✓")
    case "Swift.Dictionary<Swift.String, Swift.Int>", "Dictionary<String, Int>":
        print("[String: Int].self ✓")
    default:
        print("nil (custom type - will use Any.self)")
    }
}

// Show what String(reflecting:) produces
print("\nActual type names from String(reflecting:):")
print("  String.self -> \(String(reflecting: String.self))")
print("  Int.self -> \(String(reflecting: Int.self))")
print("  [String: Int].self -> \(String(reflecting: [String: Int].self))")
print("  TestMessage.self -> \(String(reflecting: TestMessage.self))")