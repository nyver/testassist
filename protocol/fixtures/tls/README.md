# TLS fingerprint fixture

`fingerprint_cert.pem` is a **test-only** public certificate (its private key was
discarded). It is used by the Go and Dart tests to check that both sides compute
the same certificate fingerprint: SHA-256 over the DER-encoded certificate, as
upper-case hex pairs separated by colons.

`fingerprint_cert.sha256.txt` holds the expected value, produced independently with
`openssl x509 -noout -fingerprint -sha256`. Never use this certificate at runtime.
