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
    /// Passphrase for encrypted private keys
    public let passphrase: String?
    
    public init(
        certificateChainSources: [CertificateSource],
        privateKeySource: PrivateKeySource,
        trustRoots: TrustRootsSource = .systemDefault,
        clientCertificateVerification: CertificateVerification = .none,
        cipherSuites: [NIOTLSCipher]? = nil,
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion = .tlsv13,
        requireALPN: Bool = true,
        passphrase: String? = nil
    ) {
        self.certificateChainSources = certificateChainSources
        self.privateKeySource = privateKeySource
        self.trustRoots = trustRoots
        self.clientCertificateVerification = clientCertificateVerification
        self.cipherSuites = cipherSuites
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.requireALPN = requireALPN
        self.passphrase = passphrase
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
    
    // MARK: - NIOSSL Conversion

    /// Create NIOSSL TLS configuration for server
    public func makeNIOSSLConfiguration() throws -> NIOSSL.TLSConfiguration {
        let certificateChain = try certificateChainSources.map { try $0.load() }
        let privateKey = try privateKeySource.load()
        let trustRoots = try trustRoots.makeNIOSSLTrustRoots()

        var tlsConfig = NIOSSL.TLSConfiguration.makeServerConfiguration(
            certificateChain: certificateChain.map { .certificate($0) },
            privateKey: .privateKey(privateKey)
        )

        tlsConfig.certificateVerification = clientCertificateVerification.niosslVerification
        tlsConfig.trustRoots = trustRoots
        tlsConfig.minimumTLSVersion = minimumTLSVersion.niosslVersion
        tlsConfig.maximumTLSVersion = maximumTLSVersion.niosslVersion

        // Note: NIOSSL expects cipherSuites as a String
        // For now, we'll skip cipher suite configuration

        return tlsConfig
    }

    // MARK: - grpc-swift Conversion

    /// Convert to grpc-swift HTTP2ServerTransport.Posix.TransportSecurity
    public func toGRPCTransportSecurity() throws -> HTTP2ServerTransport.Posix.TransportSecurity {
        // Convert certificate sources to grpc-swift format
        let grpcCertSources: [TLSConfig.CertificateSource] = certificateChainSources.map { source in
            switch source {
            case .file(let path, let format):
                let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                return .file(path: path, format: grpcFormat)
            case .bytes(let data, let format):
                let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                return .bytes(Array(data), format: grpcFormat)
            case .certificate:
                // Pre-loaded certificates not supported in grpc-swift transport
                fatalError("Pre-loaded certificates not supported in grpc-swift transport")
            }
        }

        // Convert private key source
        let grpcKeySource: TLSConfig.PrivateKeySource
        switch privateKeySource {
        case .file(let path, let format, _):
            let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
            grpcKeySource = .file(path: path, format: grpcFormat)
        case .bytes(let data, let format, _):
            let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
            grpcKeySource = .bytes(Array(data), format: grpcFormat)
        case .privateKey:
            fatalError("Pre-loaded private keys not supported in grpc-swift transport")
        }

        // Convert trust roots
        let grpcTrustRoots: TLSConfig.TrustRootsSource
        switch trustRoots {
        case .systemDefault:
            grpcTrustRoots = .systemDefault
        case .certificates(let sources):
            let certSources = sources.map { source -> TLSConfig.CertificateSource in
                switch source {
                case .file(let path, let format):
                    let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                    return .file(path: path, format: grpcFormat)
                case .bytes(let data, let format):
                    let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                    return .bytes(Array(data), format: grpcFormat)
                case .certificate:
                    fatalError("Pre-loaded certificates not supported in grpc-swift transport")
                }
            }
            grpcTrustRoots = .certificates(certSources)
        case .none:
            grpcTrustRoots = .systemDefault  // Fall back to system default
        }

        // Convert certificate verification
        let grpcVerification: TLSConfig.CertificateVerification
        switch clientCertificateVerification {
        case .none:
            grpcVerification = .noVerification
        case .noHostnameVerification:
            grpcVerification = .noHostnameVerification
        case .fullVerification:
            grpcVerification = .fullVerification
        }

        // Create grpc-swift TLS config
        return .tls(
            certificateChain: grpcCertSources,
            privateKey: grpcKeySource
        ) { config in
            config.clientCertificateVerification = grpcVerification
            config.trustRoots = grpcTrustRoots
            config.requireALPN = requireALPN
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
        cipherSuites: [NIOTLSCipher]? = nil,
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion = .tlsv13,
        serverHostname: String? = nil
    ) {
        self.trustRoots = trustRoots
        self.certificateChainSources = certificateChainSources
        self.privateKeySource = privateKeySource
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
        trustRoots: TrustRootsSource = .systemDefault
    ) -> ClientTLSConfiguration {
        return ClientTLSConfiguration(
            trustRoots: trustRoots,
            certificateChainSources: certificateChain,
            privateKeySource: privateKey
        )
    }
    
    /// Insecure configuration (development only)
    public static func insecure() -> ClientTLSConfiguration {
        return ClientTLSConfiguration(trustRoots: .none)
    }

    // MARK: - NIOSSL Conversion

    /// Create NIOSSL TLS configuration for client
    public func makeNIOSSLConfiguration() throws -> NIOSSL.TLSConfiguration {
        var tlsConfig = NIOSSL.TLSConfiguration.makeClientConfiguration()

        // Configure trust roots
        tlsConfig.trustRoots = try trustRoots.makeNIOSSLTrustRoots()

        // Configure certificate chain and private key for mTLS if provided
        if let certSources = certificateChainSources, !certSources.isEmpty {
            let certificates = try certSources.map { try $0.load() }
            tlsConfig.certificateChain = certificates.map { .certificate($0) }
        }

        if let keySource = privateKeySource {
            let privateKey = try keySource.load()
            tlsConfig.privateKey = .privateKey(privateKey)
        }

        // Configure TLS versions
        tlsConfig.minimumTLSVersion = minimumTLSVersion.niosslVersion
        tlsConfig.maximumTLSVersion = maximumTLSVersion.niosslVersion

        // Note: NIOSSL expects cipherSuites as a String
        // For now, we'll skip cipher suite configuration

        return tlsConfig
    }

    // MARK: - grpc-swift Conversion

    /// Convert to grpc-swift HTTP2ClientTransport.Posix.TransportSecurity
    public func toGRPCClientTransportSecurity() throws -> HTTP2ClientTransport.Posix.TransportSecurity {
        // Convert trust roots
        let grpcTrustRoots: TLSConfig.TrustRootsSource
        switch trustRoots {
        case .systemDefault:
            grpcTrustRoots = .systemDefault
        case .certificates(let sources):
            let certSources = sources.map { source -> TLSConfig.CertificateSource in
                switch source {
                case .file(let path, let format):
                    let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                    return .file(path: path, format: grpcFormat)
                case .bytes(let data, let format):
                    let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                    return .bytes(Array(data), format: grpcFormat)
                case .certificate:
                    fatalError("Pre-loaded certificates not supported in grpc-swift transport")
                }
            }
            grpcTrustRoots = .certificates(certSources)
        case .none:
            grpcTrustRoots = .systemDefault
        }

        // Convert certificate chain and private key for mTLS if provided
        let grpcCertSources: [TLSConfig.CertificateSource]?
        let grpcKeySource: TLSConfig.PrivateKeySource?

        if let certSources = certificateChainSources, !certSources.isEmpty {
            grpcCertSources = certSources.map { source in
                switch source {
                case .file(let path, let format):
                    let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                    return .file(path: path, format: grpcFormat)
                case .bytes(let data, let format):
                    let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                    return .bytes(Array(data), format: grpcFormat)
                case .certificate:
                    fatalError("Pre-loaded certificates not supported in grpc-swift transport")
                }
            }
        } else {
            grpcCertSources = nil
        }

        if let keySource = privateKeySource {
            switch keySource {
            case .file(let path, let format, _):
                let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                grpcKeySource = .file(path: path, format: grpcFormat)
            case .bytes(let data, let format, _):
                let grpcFormat: TLSConfig.SerializationFormat = (format == .pem) ? .pem : .der
                grpcKeySource = .bytes(Array(data), format: grpcFormat)
            case .privateKey:
                fatalError("Pre-loaded private keys not supported in grpc-swift transport")
            }
        } else {
            grpcKeySource = nil
        }

        // If we have mTLS configuration
        if let certChain = grpcCertSources, let privateKey = grpcKeySource {
            return .mTLS(
                certificateChain: certChain,
                privateKey: privateKey
            ) { config in
                config.trustRoots = grpcTrustRoots
                config.serverCertificateVerification = .fullVerification
            }
        } else {
            // Regular TLS without client certificates
            return .tls { config in
                config.trustRoots = grpcTrustRoots
                config.serverCertificateVerification = .fullVerification
            }
        }
    }
}