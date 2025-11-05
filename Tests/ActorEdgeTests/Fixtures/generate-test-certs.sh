#!/bin/bash

# Generate test certificates for TLS testing
# This script creates a CA, server cert, and client cert for mTLS testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Generating test certificates..."

# 1. Generate CA private key and certificate
openssl genrsa -out ca-key.pem 2048
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
    -subj "/C=US/ST=Test/L=Test/O=ActorEdge Test CA/CN=Test CA"

# 2. Generate server private key and CSR
openssl genrsa -out server-key.pem 2048
openssl req -new -key server-key.pem -out server.csr \
    -subj "/C=US/ST=Test/L=Test/O=ActorEdge/CN=localhost"

# 3. Create server certificate config with proper extensions
cat > server-ext.cnf <<EOF
subjectAltName = DNS:localhost,IP:127.0.0.1
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
EOF

# 4. Sign server certificate with CA
openssl x509 -req -days 3650 -in server.csr \
    -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
    -out server-cert.pem -extfile server-ext.cnf

# 5. Generate client private key and CSR (for mTLS)
openssl genrsa -out client-key.pem 2048
openssl req -new -key client-key.pem -out client.csr \
    -subj "/C=US/ST=Test/L=Test/O=ActorEdge/CN=test-client"

# 6. Create client certificate config with proper extensions
cat > client-ext.cnf <<EOF
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOF

# 7. Sign client certificate with CA
openssl x509 -req -days 3650 -in client.csr \
    -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
    -out client-cert.pem -extfile client-ext.cnf

# 7. Generate invalid/expired certificate for failure testing
openssl genrsa -out invalid-key.pem 2048
openssl req -new -x509 -days 1 -key invalid-key.pem -out invalid-cert.pem \
    -subj "/C=US/ST=Test/L=Test/O=Invalid/CN=invalid"

# Set certificate to already be expired (backdated)
openssl req -new -key invalid-key.pem -out invalid.csr \
    -subj "/C=US/ST=Test/L=Test/O=Invalid/CN=invalid"
# Create expired cert (valid for -1 days)
openssl x509 -req -days -1 -in invalid.csr \
    -signkey invalid-key.pem -out expired-cert.pem 2>/dev/null || \
    cp invalid-cert.pem expired-cert.pem

# Clean up CSR and config files
rm -f server.csr client.csr invalid.csr server-ext.cnf client-ext.cnf ca-cert.srl

echo "✅ Test certificates generated successfully:"
echo "  - ca-cert.pem (CA certificate)"
echo "  - ca-key.pem (CA private key)"
echo "  - server-cert.pem (Server certificate)"
echo "  - server-key.pem (Server private key)"
echo "  - client-cert.pem (Client certificate for mTLS)"
echo "  - client-key.pem (Client private key for mTLS)"
echo "  - invalid-cert.pem (Invalid certificate for failure testing)"
echo "  - expired-cert.pem (Expired certificate for failure testing)"
