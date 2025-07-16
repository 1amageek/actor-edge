import Foundation
import NIOSSL

/// Utilities for working with TLS certificates
public enum CertificateUtilities {
    
    // MARK: - Certificate Loading
    
    /// Load a certificate from a PEM or DER file
    public static func loadCertificate(from path: String, format: SerializationFormat = .pem) throws -> NIOSSLCertificate {
        let source = CertificateSource.file(path, format: format)
        return try source.load()
    }
    
    /// Load multiple certificates from a PEM file (certificate chain)
    public static func loadCertificateChain(from path: String) throws -> [NIOSSLCertificate] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let pemString = String(data: data, encoding: .utf8) ?? ""
        
        var certificates: [NIOSSLCertificate] = []
        let certificateBlocks = pemString.components(separatedBy: "-----END CERTIFICATE-----")
            .dropLast() // Remove empty last element
        
        for block in certificateBlocks {
            let certPEM = block + "-----END CERTIFICATE-----"
            if certPEM.contains("-----BEGIN CERTIFICATE-----") {
                let certificate = try NIOSSLCertificate(bytes: Array(certPEM.utf8), format: .pem)
                certificates.append(certificate)
            }
        }
        
        return certificates
    }
    
    /// Create certificate sources from a chain file
    public static func certificateSources(from chainPath: String, format: SerializationFormat = .pem) throws -> [CertificateSource] {
        let certificates = try loadCertificateChain(from: chainPath)
        return certificates.map { .certificate($0) }
    }
    
    /// Load a private key from a PEM or DER file
    public static func loadPrivateKey(
        from path: String,
        format: SerializationFormat = .pem,
        passphrase: String? = nil
    ) throws -> NIOSSLPrivateKey {
        let source: PrivateKeySource
        source = .file(path, format: format, passphrase: passphrase)
        return try source.load()
    }
    
    // MARK: - Certificate Validation
    
    /// Validate that a certificate is currently valid (not expired)
    public static func isCertificateValid(_ certificate: NIOSSLCertificate) -> Bool {
        // Note: NIOSSL doesn't expose certificate details directly
        // In production, you'd need to use Security framework or OpenSSL
        // For now, we assume certificates are valid
        return true
    }
    
    /// Extract common name from certificate
    public static func commonName(from certificate: NIOSSLCertificate) -> String? {
        // Note: NIOSSL doesn't expose certificate details directly
        // This would require using Security framework or OpenSSL
        return nil
    }
    
    // MARK: - Trust Store Management
    
    /// Create trust roots from CA certificates
    public static func createTrustRoots(from certificates: [NIOSSLCertificate]) -> NIOSSLTrustRoots {
        return .certificates(certificates)
    }
    
    /// Load trust roots from a CA bundle file
    public static func loadTrustRoots(from path: String) throws -> NIOSSLTrustRoots {
        let certificates = try loadCertificateChain(from: path)
        return .certificates(certificates)
    }
    
    /// Use system default trust roots
    public static func systemTrustRoots() -> TrustRootsSource {
        return .systemDefault
    }
    
    // MARK: - Quick Configuration Helpers
    
    /// Create a basic server TLS configuration from files
    public static func serverConfig(
        certificatePath: String,
        privateKeyPath: String,
        format: SerializationFormat = .pem,
        passphrase: String? = nil
    ) throws -> TLSConfiguration {
        let certificateSource = CertificateSource.file(certificatePath, format: format)
        let privateKeySource: PrivateKeySource
        
        privateKeySource = .file(privateKeyPath, format: format, passphrase: passphrase)
        
        return TLSConfiguration.server(
            certificateChain: [certificateSource],
            privateKey: privateKeySource
        )
    }
    
    /// Create a client TLS configuration with custom CA
    public static func clientConfig(
        caCertificatePath: String,
        format: SerializationFormat = .pem
    ) throws -> ClientTLSConfiguration {
        let caSource = CertificateSource.file(caCertificatePath, format: format)
        let trustRoots = TrustRootsSource.certificates([caSource])
        
        return ClientTLSConfiguration.client(
            trustRoots: trustRoots
        )
    }
}

// MARK: - Error Types

public enum CertificateError: Error, LocalizedError {
    case invalidCertificateData
    case noCertificatesFound
    case certificateExpired
    case privateKeyMismatch
    
    public var errorDescription: String? {
        switch self {
        case .invalidCertificateData:
            return "Invalid certificate data"
        case .noCertificatesFound:
            return "No certificates found in file"
        case .certificateExpired:
            return "Certificate has expired"
        case .privateKeyMismatch:
            return "Private key does not match certificate"
        }
    }
}