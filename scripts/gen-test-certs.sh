#!/bin/sh
# Generates the TEST-ONLY TLS fixtures used by the Flutter TLS tests:
#   ca.pem, leaf.pem      a test CA and a leaf certificate signed by it
#   self1.pem, self2.pem  two different self-signed certificates
# together with their private keys (*.key.pem). All certificates are valid for
# localhost and 127.0.0.1 and for about 100 years, so the committed files never
# expire under a test run.
#
# These keys are public by design and MUST NEVER be used outside tests.
#
# Usage: scripts/gen-test-certs.sh [output-dir]
#        (default: apps/client/test/fixtures/tls)
set -eu

# Git Bash on Windows would otherwise rewrite "/CN=..." as a file path.
MSYS2_ARG_CONV_EXCL="/CN="
export MSYS2_ARG_CONV_EXCL

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/apps/client/test/fixtures/tls}
days=36500
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

genkey() {
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1" 2>/dev/null
}

server_ext() {
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n' > "$1"
}

# Test CA.
genkey "$out/ca.key.pem"
openssl req -new -x509 -key "$out/ca.key.pem" -sha256 -days "$days" \
    -subj "/CN=Test Assistant TEST CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$out/ca.pem"

# Leaf signed by the test CA.
genkey "$out/leaf.key.pem"
openssl req -new -key "$out/leaf.key.pem" -subj "/CN=localhost" -out "$tmp/leaf.csr"
server_ext "$tmp/leaf.ext"
openssl x509 -req -in "$tmp/leaf.csr" -CA "$out/ca.pem" -CAkey "$out/ca.key.pem" -CAcreateserial \
    -CAserial "$tmp/ca.srl" -sha256 -days "$days" -extfile "$tmp/leaf.ext" -out "$out/leaf.pem" 2>/dev/null

# Two distinct self-signed server certificates.
for name in self1 self2; do
    genkey "$out/$name.key.pem"
    server_ext "$tmp/$name.ext"
    openssl req -new -x509 -key "$out/$name.key.pem" -sha256 -days "$days" \
        -subj "/CN=Test Assistant TEST $name" -addext "basicConstraints=CA:FALSE" \
        -addext "keyUsage=digitalSignature" -addext "extendedKeyUsage=serverAuth" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -out "$out/$name.pem"
done

echo "Test certificates written to $out"
