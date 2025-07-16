import Foundation
import NIOSSL

/// TLS configuration for secure connections
public struct TLSConfiguration: Sendable {
    public let certificateChain: [NIOSSLCertificate]
    public let privateKey: NIOSSLPrivateKey
    public let trustRoots: NIOSSLTrustRoots?
    public let certificateVerification: CertificateVerification
    public let cipherSuites: [NIOTLSCipher]?
    public let minimumTLSVersion: TLSVersion
    public let maximumTLSVersion: TLSVersion
    
    public init(
        certificateChain: [NIOSSLCertificate],
        privateKey: NIOSSLPrivateKey,
        trustRoots: NIOSSLTrustRoots? = nil,
        certificateVerification: CertificateVerification = .fullVerification,
        cipherSuites: [NIOTLSCipher]? = nil,
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion = .tlsv13
    ) {
        self.certificateChain = certificateChain
        self.privateKey = privateKey
        self.trustRoots = trustRoots
        self.certificateVerification = certificateVerification
        self.cipherSuites = cipherSuites
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
    }
    
    /// Create a server TLS configuration
    public static func makeServerConfiguration(
        certificateChain: [NIOSSLCertificate],
        privateKey: NIOSSLPrivateKey
    ) -> TLSConfiguration {
        return TLSConfiguration(certificateChain: certificateChain, privateKey: privateKey)
    }
    
    /// Create a simple server TLS configuration for testing
    public static func makeServerTLS() -> TLSConfiguration? {
        // TODO: Implement proper certificate generation
        // For now, return nil - in production, this should load from files or generate self-signed
        return nil
    }
    
    /// Create a simple client TLS configuration
    public static func makeClientTLS() -> ClientTLSConfiguration {
        ClientTLSConfiguration()
    }
}

/// Certificate verification mode
public enum CertificateVerification: Sendable {
    case none
    case noHostnameVerification
    case fullVerification
}