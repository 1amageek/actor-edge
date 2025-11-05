import Foundation
import NIOSSL
import GRPCNIOTransportHTTP2

/// TLS configuration for secure server connections
public struct TLSConfiguration: Sendable {
    /// Certificate chain sources
    public let certificateChainSources: [CertificateSource]
    /// Private key source
    public let privateKeySource: PrivateKeySource
    /// Trust roots for client certificate verification (mTLS)
    public let trustRoots: TrustRootsSource
    /// Client certificate verification mode
    public let clientCertificateVerification: CertificateVerification
    /// Cipher suites to use
    public let cipherSuites: [NIOTLSCipher]?
    /// Minimum TLS version
    public let minimumTLSVersion: TLSVersion
    /// Maximum TLS version
    public let maximumTLSVersion: TLSVersion
    /// Whether to require ALPN
    public let requireALPN: Bool

    public init(
        certificateChainSources: [CertificateSource],
        privateKeySource: PrivateKeySource,
        trustRoots: TrustRootsSource = .systemDefault,
        clientCertificateVerification: CertificateVerification = .none,
        cipherSuites: [NIOTLSCipher]? = nil,
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion = .tlsv13,
        requireALPN: Bool = false
    ) {
        self.certificateChainSources = certificateChainSources
        self.privateKeySource = privateKeySource
        self.trustRoots = trustRoots
        self.clientCertificateVerification = clientCertificateVerification
        self.cipherSuites = cipherSuites
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.requireALPN = requireALPN
    }
    
    
    // MARK: - Factory Methods
    
    /// Create a server TLS configuration
    public static func server(
        certificateChain: [CertificateSource],
        privateKey: PrivateKeySource,
        clientCertificateVerification: CertificateVerification = .none,
        trustRoots: TrustRootsSource = .systemDefault
    ) -> TLSConfiguration {
        return TLSConfiguration(
            certificateChainSources: certificateChain,
            privateKeySource: privateKey,
            trustRoots: trustRoots,
            clientCertificateVerification: clientCertificateVerification
        )
    }
    
    /// Create a server TLS configuration for mutual TLS
    public static func serverMTLS(
        certificateChain: [CertificateSource],
        privateKey: PrivateKeySource,
        trustRoots: TrustRootsSource,
        clientCertificateVerification: CertificateVerification = .fullVerification
    ) -> TLSConfiguration {
        return TLSConfiguration(
            certificateChainSources: certificateChain,
            privateKeySource: privateKey,
            trustRoots: trustRoots,
            clientCertificateVerification: clientCertificateVerification
        )
    }
    
    /// Load TLS configuration from certificate and key files
    public static func fromFiles(
        certificatePath: String,
        privateKeyPath: String,
        format: SerializationFormat = .pem,
        privateKeyPassword: String? = nil
    ) throws -> TLSConfiguration {
        let certificateSource = CertificateSource.file(certificatePath, format: format)
        let privateKeySource: PrivateKeySource
        
        privateKeySource = .file(privateKeyPath, format: format, passphrase: privateKeyPassword)
        
        return TLSConfiguration(
            certificateChainSources: [certificateSource],
            privateKeySource: privateKeySource
        )
    }
    
    // MARK: - grpc-swift Conversion

    /// Convert to grpc-swift HTTP2ServerTransport.Posix.TransportSecurity
    /// - Throws: `TLSConfigurationError` if using pre-loaded certificates or private keys
    public func toGRPCTransportSecurity() throws -> HTTP2ServerTransport.Posix.TransportSecurity {
        // Use conversion methods from TLSTypes
        let grpcCertSources = try certificateChainSources.map { try $0.toGRPCCertificateSource() }
        let grpcKeySource = try privateKeySource.toGRPCPrivateKeySource()
        let grpcTrustRoots = try trustRoots.toGRPCTrustRootsSource()
        let grpcVerification = clientCertificateVerification.grpcVerification

        // Use mTLS if client certificate verification is enabled
        if grpcVerification != .noVerification {
            return .mTLS(
                certificateChain: grpcCertSources,
                privateKey: grpcKeySource
            ) { config in
                config.clientCertificateVerification = grpcVerification
                config.trustRoots = grpcTrustRoots
                config.requireALPN = requireALPN
            }
        } else {
            // Regular TLS
            return .tls(
                certificateChain: grpcCertSources,
                privateKey: grpcKeySource
            ) { config in
                config.trustRoots = grpcTrustRoots
                config.requireALPN = requireALPN
            }
        }
    }
}

/// TLS configuration for client connections
public struct ClientTLSConfiguration: Sendable {
    /// Trust roots for server certificate verification
    public let trustRoots: TrustRootsSource
    /// Certificate chain sources (for mTLS)
    public let certificateChainSources: [CertificateSource]?
    /// Private key source (for mTLS)
    public let privateKeySource: PrivateKeySource?
    /// Server certificate verification mode
    public let serverCertificateVerification: CertificateVerification
    /// Cipher suites to use
    public let cipherSuites: [NIOTLSCipher]?
    /// Minimum TLS version
    public let minimumTLSVersion: TLSVersion
    /// Maximum TLS version
    public let maximumTLSVersion: TLSVersion
    /// Server hostname for verification
    public let serverHostname: String?

    public init(
        trustRoots: TrustRootsSource = .systemDefault,
        certificateChainSources: [CertificateSource]? = nil,
        privateKeySource: PrivateKeySource? = nil,
        serverCertificateVerification: CertificateVerification = .fullVerification,
        cipherSuites: [NIOTLSCipher]? = nil,
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion = .tlsv13,
        serverHostname: String? = nil
    ) {
        self.trustRoots = trustRoots
        self.certificateChainSources = certificateChainSources
        self.privateKeySource = privateKeySource
        self.serverCertificateVerification = serverCertificateVerification
        self.cipherSuites = cipherSuites
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.serverHostname = serverHostname
    }
    
    // MARK: - Factory Methods
    
    /// System default TLS configuration
    public static func systemDefault() -> ClientTLSConfiguration {
        return ClientTLSConfiguration()
    }
    
    /// Client configuration with custom CA
    public static func client(
        trustRoots: TrustRootsSource
    ) -> ClientTLSConfiguration {
        return ClientTLSConfiguration(trustRoots: trustRoots)
    }
    
    /// Mutual TLS configuration
    public static func mutualTLS(
        certificateChain: [CertificateSource],
        privateKey: PrivateKeySource,
        trustRoots: TrustRootsSource = .systemDefault,
        serverHostname: String? = nil
    ) -> ClientTLSConfiguration {
        return ClientTLSConfiguration(
            trustRoots: trustRoots,
            certificateChainSources: certificateChain,
            privateKeySource: privateKey,
            serverHostname: serverHostname
        )
    }
    
    /// Insecure configuration (development only)
    /// - Warning: This disables certificate verification. Use only for development/testing with self-signed certificates.
    public static func insecure() -> ClientTLSConfiguration {
        return ClientTLSConfiguration(
            trustRoots: .none,
            serverCertificateVerification: .none
        )
    }

    // MARK: - grpc-swift Conversion

    /// Convert to grpc-swift HTTP2ClientTransport.Posix.TransportSecurity
    /// - Throws: `TLSConfigurationError` if using pre-loaded certificates or private keys
    public func toGRPCClientTransportSecurity() throws -> HTTP2ClientTransport.Posix.TransportSecurity {
        // Use conversion methods from TLSTypes
        let grpcTrustRoots = try trustRoots.toGRPCTrustRootsSource()
        let grpcVerification = serverCertificateVerification.grpcVerification

        // Convert certificate chain and private key for mTLS if provided
        let grpcCertSources = try certificateChainSources?.map { try $0.toGRPCCertificateSource() }
        let grpcKeySource = try privateKeySource?.toGRPCPrivateKeySource()

        // If we have mTLS configuration
        if let certChain = grpcCertSources, !certChain.isEmpty, let privateKey = grpcKeySource {
            return .mTLS(
                certificateChain: certChain,
                privateKey: privateKey
            ) { config in
                config.trustRoots = grpcTrustRoots
                config.serverCertificateVerification = grpcVerification
            }
        } else {
            // Regular TLS without client certificates
            return .tls { config in
                config.trustRoots = grpcTrustRoots
                config.serverCertificateVerification = grpcVerification
            }
        }
    }
}