import Foundation
import NIOSSL

// MARK: - Certificate Source

/// Source for loading TLS certificates
public enum CertificateSource: Sendable {
    /// Certificate provided as raw bytes
    case bytes(Data, format: SerializationFormat)
    /// Certificate loaded from file path
    case file(String, format: SerializationFormat)
    /// Pre-loaded certificate object
    case certificate(NIOSSLCertificate)
    
    /// Load the certificate
    public func load() throws -> NIOSSLCertificate {
        switch self {
        case .bytes(let data, let format):
            return try NIOSSLCertificate(bytes: Array(data), format: format.niosslFormat)
        case .file(let path, let format):
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try NIOSSLCertificate(bytes: Array(data), format: format.niosslFormat)
        case .certificate(let cert):
            return cert
        }
    }
}

// MARK: - Private Key Source

/// Source for loading private keys
public enum PrivateKeySource: Sendable {
    /// Private key provided as raw bytes
    case bytes(Data, format: SerializationFormat, passphrase: String? = nil)
    /// Private key loaded from file path
    case file(String, format: SerializationFormat, passphrase: String? = nil)
    /// Pre-loaded private key object
    case privateKey(NIOSSLPrivateKey)
    
    /// Load the private key
    public func load() throws -> NIOSSLPrivateKey {
        switch self {
        case .bytes(let data, let format, let passphrase):
            if let passphrase = passphrase {
                let passphraseBytes = Array(passphrase.utf8)
                let callback: NIOSSLPassphraseCallback<[UInt8]> = { _ in passphraseBytes }
                return try NIOSSLPrivateKey(bytes: Array(data), format: format.niosslFormat, passphraseCallback: callback)
            } else {
                return try NIOSSLPrivateKey(bytes: Array(data), format: format.niosslFormat)
            }
        case .file(let path, let format, let passphrase):
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let passphrase = passphrase {
                let passphraseBytes = Array(passphrase.utf8)
                let callback: NIOSSLPassphraseCallback<[UInt8]> = { _ in passphraseBytes }
                return try NIOSSLPrivateKey(bytes: Array(data), format: format.niosslFormat, passphraseCallback: callback)
            } else {
                return try NIOSSLPrivateKey(bytes: Array(data), format: format.niosslFormat)
            }
        case .privateKey(let key):
            return key
        }
    }
}

// MARK: - Trust Roots Source

/// Source for trust roots configuration
public enum TrustRootsSource: Sendable {
    /// Use system default trust roots
    case systemDefault
    /// Use custom certificates as trust roots
    case certificates([CertificateSource])
    
    /// Convert to NIOSSL trust roots
    public func makeNIOSSLTrustRoots() throws -> NIOSSLTrustRoots {
        switch self {
        case .systemDefault:
            return .default
        case .certificates(let sources):
            let certs = try sources.map { try $0.load() }
            return .certificates(certs)
        }
    }
}

// MARK: - Serialization Format

/// Certificate/Key serialization format
public enum SerializationFormat: Sendable {
    case pem
    case der
    
    var niosslFormat: NIOSSLSerializationFormats {
        switch self {
        case .pem:
            return .pem
        case .der:
            return .der
        }
    }
}

// MARK: - TLS Version

/// TLS protocol version
public enum TLSVersion: Sendable {
    case tlsv10
    case tlsv11
    case tlsv12
    case tlsv13
    
    /// Convert to NIOSSL TLS version
    public var niosslVersion: NIOSSL.TLSVersion {
        switch self {
        case .tlsv10:
            return .tlsv1
        case .tlsv11:
            return .tlsv11
        case .tlsv12:
            return .tlsv12
        case .tlsv13:
            return .tlsv13
        }
    }
}

// MARK: - Certificate Verification

/// Certificate verification mode
public enum CertificateVerification: Sendable {
    /// Do not verify certificates (INSECURE - only for testing)
    case none
    /// Verify certificate chain but not hostname
    case noHostnameVerification
    /// Full certificate and hostname verification
    case fullVerification
    
    /// Convert to NIOSSL certificate verification
    public var niosslVerification: NIOSSL.CertificateVerification {
        switch self {
        case .none:
            return .none
        case .noHostnameVerification:
            return .noHostnameVerification
        case .fullVerification:
            return .fullVerification
        }
    }
}