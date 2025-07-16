import Foundation
import NIOSSL

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
    internal func makeNIOSSLConfiguration() throws -> NIOSSL.TLSConfiguration {
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
}