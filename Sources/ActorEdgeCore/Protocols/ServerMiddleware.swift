import Foundation

/// Protocol for server middleware that can intercept and process requests
public protocol ServerMiddleware: Sendable {
    /// Process a request and optionally modify it before passing to the next handler
    func process(
        _ request: Request,
        next: (Request) async throws -> Response
    ) async throws -> Response
}

/// Represents an incoming request
public struct Request: Sendable {
    public let method: String
    public let actorID: ActorEdgeID
    public let headers: [String: String]
    public let payload: Data
    
    public init(
        method: String,
        actorID: ActorEdgeID,
        headers: [String: String],
        payload: Data
    ) {
        self.method = method
        self.actorID = actorID
        self.headers = headers
        self.payload = payload
    }
}

/// Represents a response to be sent back
public struct Response: Sendable {
    public let status: ResponseStatus
    public let headers: [String: String]
    public let payload: Data
    
    public init(
        status: ResponseStatus = .ok,
        headers: [String: String] = [:],
        payload: Data
    ) {
        self.status = status
        self.headers = headers
        self.payload = payload
    }
}

/// Response status codes
public enum ResponseStatus: Sendable {
    case ok
    case error(Error)
}