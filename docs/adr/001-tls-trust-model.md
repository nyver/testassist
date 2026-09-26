# 001. TLS trust model: self-signed certificate with fingerprint pinning

## Status

Accepted.

## Context

The server is self-hosted by one operator, usually on a home network that is reached by IP address. Public CAs will not issue certificates for such addresses, and many operators do not want to run a domain and ACME. The API carries the Bearer token and the user's questions, so plaintext HTTP is not acceptable. `AGENTS.md` forbids disabling certificate verification and allows pinning only with a safe rotation path.

## Decision

- The server only serves HTTPS (TLS 1.2 or newer). There is no plaintext listener.
- The server loads an administrator-provided certificate from `/certs/server.crt` and `/certs/server.key`. If neither file exists it generates a self-signed ECDSA P-256 certificate (10-year validity) and persists it. If exactly one file exists it refuses to start (`TLS_CONFIGURATION_ERROR`) rather than replace something the operator may care about.
- The certificate fingerprint is the SHA-256 digest of the DER-encoded leaf certificate, written as upper-case hexadecimal pairs separated by colons. The server prints it at startup and through `server certificate fingerprint`.
- The client uses trust on first use (TOFU) with an out-of-band comparison:
  1. It probes the server with a TLS handshake that captures the certificate and rejects it. No HTTP bytes, and therefore no token, are sent.
  2. If the certificate is publicly trusted, the client stores no pin and validates normally.
  3. Otherwise the user compares the displayed fingerprint with the one printed by the server and explicitly taps Trust. Only then is the fingerprint stored (in `flutter_secure_storage`).
  4. From then on the client accepts a bad-certificate callback only for that host and port and only when the leaf fingerprint equals the stored pin. A pin is also enforced for CA-valid certificates.
- A fingerprint mismatch blocks the connection with `CERTIFICATE_CHANGED`. The user has to choose "Reset trusted certificate" and confirm the new fingerprint.
- Pinning is by leaf fingerprint, not by adding the certificate as a trusted root. A trusted root would also trust the certificate as a CA and would enforce hostname and SAN matching, which breaks IP-only setups.

## Consequences

- Operators get working HTTPS without a domain. Users must compare a fingerprint once per server.
- A global "accept all certificates" callback never exists in the client. Test fixtures are the only place where extra trust roots are injected.
- Rotation is an explicit action: the operator replaces or deletes the certificate files and restarts; each client resets trust. There is no silent re-trust. This costs some convenience and buys protection against an active man-in-the-middle after pairing.
- Certificates are not hot-reloaded. Changing them requires a restart.
- The server's `healthcheck` subcommand trusts only the configured certificate file (self-signed) or the system roots (CA-issued), and never skips verification.
