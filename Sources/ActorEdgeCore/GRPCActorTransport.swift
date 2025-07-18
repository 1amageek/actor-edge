import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import ServiceContextModule
import Logging
import SwiftProtobuf
import NIOCore
import NIOPosix
import NIOSSL
import Metrics

/// gRPC-based transport implementation for ActorEdge
public final class GRPCActorTransport: ActorTransport, Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let logger: Logger
    private let endpoint: String
    private let callLifecycleManager: CallLifecycleManager
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let clientTask: Task<Void, Error>
    
    // Metrics
    private let requestCounter: Counter
    private let errorCounter: Counter
    private let metricNames: MetricNames
    
    public init(_ endpoint: String, tls: ClientTLSConfiguration? = nil, metricsNamespace: String = "actor_edge") async throws {
        self.endpoint = endpoint
        self.logger = Logger(label: "ActorEdge.Transport")
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.callLifecycleManager = CallLifecycleManager(eventLoopGroup: eventLoopGroup, metricsNamespace: metricsNamespace)
        
        // Initialize metrics
        self.metricNames = MetricNames(namespace: metricsNamespace)
        self.requestCounter = Counter(label: metricNames.grpcRequestsTotal)
        self.errorCounter = Counter(label: metricNames.grpcErrorsTotal)
        
        // Parse endpoint to extract host and port
        let components = endpoint.split(separator: ":")
        let host = String(components[0])
        let port = components.count > 1 ? Int(components[1]) ?? 443 : 443
        
        // Create HTTP2 transport with appropriate security
        let transport: HTTP2ClientTransport.Posix
        if tls != nil {
            // For now, we use plaintext and log a warning
            // TODO: Implement proper TLS when grpc-swift 2.0 exposes the configuration API
            logger.warning("TLS configuration provided but not fully implemented. Using plaintext for now.")
            transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .plaintext
            )
        } else {
            transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .plaintext
            )
        }
        
        // Create GRPCClient with the transport
        self.client = GRPCClient(transport: transport)
        
        // Capture client reference before initializing task
        let clientRef = self.client
        
        // Run the client connections in a background task
        self.clientTask = Task {
            try await clientRef.runConnections()
        }
        
        logger.info("GRPCActorTransport initialized", metadata: [
            "endpoint": "\(endpoint)",
            "tls": "\(tls != nil)"
        ])
    }
    
    public func remoteCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> Data {
        // Generate call ID
        let callID = CallIDGenerator.generate()
        
        // Create protobuf request
        let request = Actoredge_RemoteCallRequest.with {
            $0.callID = callID
            $0.actorID = actorID.description
            $0.method = method
            $0.payload = arguments
            
            // Add trace context to metadata if available
            if let traceID = context.traceID {
                $0.metadata["trace-id"] = traceID
            }
        }
        
        // Update metrics
        requestCounter.increment()
        
        // Get event loop for this call
        let eventLoop = self.eventLoop
        
        // Register call with lifecycle manager on the EventLoop
        let timeout = TimeAmount.seconds(30) // TODO: Make configurable
        let future: EventLoopFuture<ByteBuffer>
        
        if eventLoop.inEventLoop {
            // Already on the EventLoop, register directly
            future = try callLifecycleManager.register(
                callID: callID,
                eventLoop: eventLoop,
                timeout: timeout
            )
        } else {
            // Need to hop to the EventLoop
            let promise = eventLoop.makePromise(of: ByteBuffer.self)
            eventLoop.execute {
                do {
                    let registeredFuture = try self.callLifecycleManager.register(
                        callID: callID,
                        eventLoop: eventLoop,
                        timeout: timeout
                    )
                    registeredFuture.cascade(to: promise)
                } catch {
                    promise.fail(error)
                }
            }
            future = promise.futureResult
        }
        
        // Make the gRPC call in background
        Task {
            do {
                // Create metadata from context
                var metadata = Metadata()
                if let traceID = context.traceID {
                    metadata.addString(traceID, forKey: "trace-id")
                }
                
                // Make unary RPC call
                let descriptor = MethodDescriptor(
                    service: ServiceDescriptor(fullyQualifiedService: "actoredge.DistributedActor"),
                    method: "RemoteCall"
                )
                
                let response = try await client.unary(
                    request: ClientRequest(message: request, metadata: metadata),
                    descriptor: descriptor,
                    serializer: ProtobufSerializer<Actoredge_RemoteCallRequest>(),
                    deserializer: ProtobufDeserializer<Actoredge_RemoteCallResponse>(),
                    options: .defaults
                ) { response in
                    response
                }
                
                // Handle response
                let message = try response.message
                
                // Verify call ID matches
                guard message.callID == callID else {
                    callLifecycleManager.fail(
                        callID: callID,
                        error: ActorEdgeError.invalidResponse
                    )
                    return
                }
                
                switch message.result {
                case .value(let data):
                    // Convert Data to ByteBuffer
                    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                    buffer.writeBytes(data)
                    callLifecycleManager.succeed(callID: callID, buffer: buffer)
                    
                case .error(let errorEnvelope):
                    let error = deserializeError(errorEnvelope)
                    errorCounter.increment()
                    callLifecycleManager.fail(callID: callID, error: error)
                    
                case .none:
                    errorCounter.increment()
                    callLifecycleManager.fail(
                        callID: callID,
                        error: ActorEdgeError.invalidResponse
                    )
                }
            } catch {
                errorCounter.increment()
                callLifecycleManager.fail(callID: callID, error: error)
            }
        }
        
        // Wait for result using EventLoopFuture bridge
        let buffer = try await future.get()
        return Data(buffer.readableBytesView)
    }
    
    public func remoteCallVoid(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws {
        // Reuse remoteCall but ignore the return value
        _ = try await remoteCall(
            on: actorID,
            method: method,
            arguments: arguments,
            context: context
        )
    }
    
    public func streamCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> AsyncThrowingStream<Data, Error> {
        // TODO: Implement bidirectional streaming
        throw ActorEdgeError.transportError("Streaming not yet implemented")
    }
    
    // Helper to deserialize error from ErrorEnvelope
    private func deserializeError(_ envelope: Actoredge_ErrorEnvelope) -> Error {
        let errorEnvelope = ErrorEnvelope(
            typeURL: envelope.typeURL,
            data: envelope.data
        )
        return ActorEdgeError.remoteError(errorEnvelope)
    }
    
    // MARK: - EventLoop Access
    
    /// Get the next available EventLoop
    public var eventLoop: EventLoop {
        eventLoopGroup.next()
    }
    
    // MARK: - Graceful Shutdown
    
    /// Graceful shutdown
    public func shutdownGracefully() async throws {
        // Cancel all pending calls
        callLifecycleManager.cancelAll()
        
        // Begin graceful shutdown of client
        client.beginGracefulShutdown()
        
        // Wait for client task to complete
        _ = try? await clientTask.value
        
        // Shutdown event loop group
        try await eventLoopGroup.shutdownGracefully()
    }
    
    deinit {
        // Cancel all pending calls
        callLifecycleManager.cancelAll()
        
        // Cancel client task
        clientTask.cancel()
        
        // Shutdown event loop group
        try? eventLoopGroup.syncShutdownGracefully()
    }
}

// MARK: - ServiceContext Extensions

private extension ServiceContext {
    var traceID: String? {
        // TODO: Extract trace ID from context
        return nil
    }
}

// MARK: - ClientTLSConfiguration

import NIOSSL

/// Client-side TLS configuration for secure connections
public struct ClientTLSConfiguration: Sendable {
    /// Server certificate verification mode
    public let serverCertificateVerification: CertificateVerification
    
    /// Trust roots for server certificate validation
    public let trustRoots: TrustRootsSource
    
    /// Expected server hostname for validation
    public let serverHostname: String?
    
    /// Client certificate chain sources for mutual TLS
    public let certificateChainSources: [CertificateSource]?
    
    /// Client private key source for mutual TLS
    public let privateKeySource: PrivateKeySource?
    
    /// Minimum TLS version (default: TLS 1.2)
    public let minimumTLSVersion: TLSVersion
    
    /// Maximum TLS version (default: TLS 1.3)
    public let maximumTLSVersion: TLSVersion
    
    /// Custom cipher suites
    public let cipherSuites: [NIOTLSCipher]?
    
    /// Passphrase for encrypted private keys
    public let passphrase: String?
    
    public init(
        serverCertificateVerification: CertificateVerification = .fullVerification,
        trustRoots: TrustRootsSource = .systemDefault,
        serverHostname: String? = nil,
        certificateChainSources: [CertificateSource]? = nil,
        privateKeySource: PrivateKeySource? = nil,
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion = .tlsv13,
        cipherSuites: [NIOTLSCipher]? = nil,
        passphrase: String? = nil
    ) {
        self.serverCertificateVerification = serverCertificateVerification
        self.trustRoots = trustRoots
        self.serverHostname = serverHostname
        self.certificateChainSources = certificateChainSources
        self.privateKeySource = privateKeySource
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.cipherSuites = cipherSuites
        self.passphrase = passphrase
    }
    
    // MARK: - Factory Methods
    
    /// Create a client configuration that trusts the system's default CA certificates
    public static func systemDefault() -> ClientTLSConfiguration {
        ClientTLSConfiguration()
    }
    
    /// Create a client configuration for development that disables certificate verification
    /// WARNING: This should ONLY be used for development/testing
    public static func insecure() -> ClientTLSConfiguration {
        ClientTLSConfiguration(serverCertificateVerification: .none)
    }
    
    /// Create a client configuration with custom trust roots
    public static func client(
        trustRoots: TrustRootsSource,
        serverCertificateVerification: CertificateVerification = .fullVerification
    ) -> ClientTLSConfiguration {
        ClientTLSConfiguration(
            serverCertificateVerification: serverCertificateVerification,
            trustRoots: trustRoots
        )
    }
    
    /// Create a client configuration with mutual TLS
    public static func mutualTLS(
        certificateChain: [CertificateSource],
        privateKey: PrivateKeySource,
        trustRoots: TrustRootsSource = .systemDefault,
        serverCertificateVerification: CertificateVerification = .fullVerification
    ) -> ClientTLSConfiguration {
        ClientTLSConfiguration(
            serverCertificateVerification: serverCertificateVerification,
            trustRoots: trustRoots,
            certificateChainSources: certificateChain,
            privateKeySource: privateKey
        )
    }
    
    // MARK: - NIOSSL Conversion
    
    /// Create NIOSSL TLS configuration for client
    internal func makeNIOSSLConfiguration(serverHostname: String) throws -> NIOSSL.TLSConfiguration {
        var tlsConfig = NIOSSL.TLSConfiguration.makeClientConfiguration()
        
        // Set certificate verification
        tlsConfig.certificateVerification = serverCertificateVerification.niosslVerification
        
        // Set trust roots
        tlsConfig.trustRoots = try trustRoots.makeNIOSSLTrustRoots()
        
        // Set client certificates for mTLS
        if let certSources = certificateChainSources,
           let keySource = privateKeySource {
            let certificates = try certSources.map { try $0.load() }
            let privateKey = try keySource.load()
            
            tlsConfig.certificateChain = certificates.map { .certificate($0) }
            tlsConfig.privateKey = .privateKey(privateKey)
        }
        
        // Set TLS versions
        tlsConfig.minimumTLSVersion = minimumTLSVersion.niosslVersion
        tlsConfig.maximumTLSVersion = maximumTLSVersion.niosslVersion
        
        // Note: NIOSSL expects cipherSuites as a String
        // For now, we'll skip cipher suite configuration
        
        return tlsConfig
    }
}