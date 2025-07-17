import Foundation

/// Reply message for remote actor invocations
/// Based on swift-distributed-actors RemoteCallReply
public struct RemoteCallReply: Codable, Sendable {
    /// Call ID to match with the original request
    public let callID: String
    
    /// Successful return value (serialized)
    public let value: Data?
    
    /// Error information if the call failed
    public let error: RemoteCallError?
    
    private init(callID: String, value: Data?, error: RemoteCallError?) {
        self.callID = callID
        self.value = value
        self.error = error
    }
    
    /// Create a successful reply with a return value
    public static func success(callID: String, value: Data) -> RemoteCallReply {
        RemoteCallReply(callID: callID, value: value, error: nil)
    }
    
    /// Create a successful reply for void returns
    public static func void(callID: String) -> RemoteCallReply {
        // Use empty Data for void returns
        RemoteCallReply(callID: callID, value: Data(), error: nil)
    }
    
    /// Create a failure reply with an error
    public static func failure(callID: String, error: Error) -> RemoteCallReply {
        let remoteError = RemoteCallError.from(error)
        return RemoteCallReply(callID: callID, value: nil, error: remoteError)
    }
    
    /// Check if this is a successful reply
    public var isSuccess: Bool {
        error == nil
    }
}

// MARK: - CustomStringConvertible
extension RemoteCallReply: CustomStringConvertible {
    public var description: String {
        if let error = error {
            return "RemoteCallReply(callID: \(callID), error: \(error))"
        } else if let value = value {
            return "RemoteCallReply(callID: \(callID), value: \(value.count) bytes)"
        } else {
            return "RemoteCallReply(callID: \(callID), void)"
        }
    }
}