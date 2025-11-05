import Testing
import Foundation
import ActorEdge
import Distributed

@Suite("TLS Configuration Tests")
struct TLSTests {

    // MARK: - Test Helpers

    /// Get the path to the test certificates directory
    static func certificatesPath() -> String {
        let currentFile = #filePath
        let testDir = URL(fileURLWithPath: currentFile).deletingLastPathComponent()
        return testDir
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("certificates")
            .path
    }

    /// Get path to a specific certificate file
    static func certificatePath(_ filename: String) -> String {
        return "\(certificatesPath())/\(filename)"
    }

    // MARK: - Certificate Loading Tests

    @Test("Load certificate chain from PEM file")
    func testLoadCertificateChain() async throws {
        let certPath = Self.certificatePath("server-cert.pem")
        let certificates = try CertificateUtilities.loadCertificateChain(from: certPath)

        #expect(certificates.count == 1, "Should load one certificate")
    }

    @Test("Create server TLS configuration from files")
    func testServerConfigFromFiles() async throws {
        let certPath = Self.certificatePath("server-cert.pem")
        let keyPath = Self.certificatePath("server-key.pem")

        let tlsConfig = try CertificateUtilities.serverConfig(
            certificatePath: certPath,
            privateKeyPath: keyPath
        )

        #expect(tlsConfig.certificateChainSources.count == 1, "Should have one certificate")
    }

    @Test("Create client TLS configuration with custom CA")
    func testClientConfigWithCA() async throws {
        let caPath = Self.certificatePath("ca-cert.pem")

        let clientConfig = try CertificateUtilities.clientConfig(
            caCertificatePath: caPath
        )

        // Verify trust roots are configured
        switch clientConfig.trustRoots {
        case .certificates(let sources):
            #expect(sources.count == 1, "Should have one CA certificate")
        default:
            Issue.record("Expected certificates trust roots")
        }
    }

    // MARK: - TLS Conversion Tests

    @Test("Convert TLS configuration to gRPC transport security")
    func testTLSConfigurationConversion() async throws {
        let certPath = Self.certificatePath("server-cert.pem")
        let keyPath = Self.certificatePath("server-key.pem")

        let tlsConfig = try TLSConfiguration.fromFiles(
            certificatePath: certPath,
            privateKeyPath: keyPath
        )

        // Should not throw when converting
        let _ = try tlsConfig.toGRPCTransportSecurity()
    }

    @Test("Convert client TLS configuration to gRPC transport security")
    func testClientTLSConfigurationConversion() async throws {
        let caPath = Self.certificatePath("ca-cert.pem")

        let clientConfig = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caPath, format: .pem)])
        )

        // Should not throw when converting
        let _ = try clientConfig.toGRPCClientTransportSecurity()
    }

    @Test("Convert mTLS client configuration")
    func testMTLSClientConfigurationConversion() async throws {
        let caPath = Self.certificatePath("ca-cert.pem")
        let clientCertPath = Self.certificatePath("client-cert.pem")
        let clientKeyPath = Self.certificatePath("client-key.pem")

        let clientConfig = ClientTLSConfiguration.mutualTLS(
            certificateChain: [.file(clientCertPath, format: .pem)],
            privateKey: .file(clientKeyPath, format: .pem),
            trustRoots: .certificates([.file(caPath, format: .pem)])
        )

        // Should not throw when converting
        let _ = try clientConfig.toGRPCClientTransportSecurity()
    }

    // MARK: - Error Handling Tests

    @Test("Pre-loaded certificates throw proper error")
    func testPreloadedCertificatesError() async throws {
        let certPath = Self.certificatePath("server-cert.pem")
        let cert = try CertificateSource.file(certPath, format: .pem).load()

        let source = CertificateSource.certificate(cert)

        do {
            let _ = try source.toGRPCCertificateSource()
            Issue.record("Should have thrown error for pre-loaded certificate")
        } catch let error as TLSConfigurationError {
            #expect(error == .preloadedCertificatesNotSupported)
        }
    }

    @Test("Pre-loaded private keys throw proper error")
    func testPreloadedPrivateKeyError() async throws {
        let keyPath = Self.certificatePath("server-key.pem")
        let key = try PrivateKeySource.file(keyPath, format: .pem).load()

        let source = PrivateKeySource.privateKey(key)

        do {
            let _ = try source.toGRPCPrivateKeySource()
            Issue.record("Should have thrown error for pre-loaded private key")
        } catch let error as TLSConfigurationError {
            #expect(error == .preloadedPrivateKeysNotSupported)
        }
    }

    // MARK: - Certificate Format Tests

    @Test("Load PEM format certificates")
    func testPEMFormatCertificates() async throws {
        let certPath = Self.certificatePath("server-cert.pem")
        let source = CertificateSource.file(certPath, format: .pem)

        // Should not throw
        let _ = try source.load()
    }

    @Test("Load PEM format private key")
    func testPEMFormatPrivateKey() async throws {
        let keyPath = Self.certificatePath("server-key.pem")
        let source = PrivateKeySource.file(keyPath, format: .pem)

        // Should not throw
        let _ = try source.load()
    }

    // MARK: - Trust Roots Tests

    @Test("System default trust roots")
    func testSystemDefaultTrustRoots() async throws {
        let source = TrustRootsSource.systemDefault

        // Should convert successfully without throwing
        let _ = try source.toGRPCTrustRootsSource()
    }

    @Test("Custom CA trust roots")
    func testCustomCATrustRoots() async throws {
        let caPath = Self.certificatePath("ca-cert.pem")
        let source = TrustRootsSource.certificates([.file(caPath, format: .pem)])

        // Should convert successfully without throwing
        let _ = try source.toGRPCTrustRootsSource()
    }

    // MARK: - Integration Scenarios

    @Test("Server TLS configuration with mTLS")
    func testServerMTLSConfiguration() async throws {
        let certPath = Self.certificatePath("server-cert.pem")
        let keyPath = Self.certificatePath("server-key.pem")
        let caPath = Self.certificatePath("ca-cert.pem")

        let tlsConfig = TLSConfiguration.serverMTLS(
            certificateChain: [.file(certPath, format: .pem)],
            privateKey: .file(keyPath, format: .pem),
            trustRoots: .certificates([.file(caPath, format: .pem)]),
            clientCertificateVerification: .fullVerification
        )

        #expect(tlsConfig.clientCertificateVerification == .fullVerification)

        // Should convert successfully
        let _ = try tlsConfig.toGRPCTransportSecurity()
    }
}

