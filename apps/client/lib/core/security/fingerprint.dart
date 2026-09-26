import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 of a DER-encoded certificate as upper-case hexadecimal byte pairs
/// separated by colons, the same format the server prints
/// (`server certificate fingerprint`).
String certificateFingerprint(Uint8List der) {
  final digest = sha256.convert(der).bytes;
  return digest
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}
