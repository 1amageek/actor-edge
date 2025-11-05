import Foundation
import NIOSSL

/// Utilities for working with TLS certificates
public enum CertificateUtilities {

    // MARK: - Certificate Loading

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