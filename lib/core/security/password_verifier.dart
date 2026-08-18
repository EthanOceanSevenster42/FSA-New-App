import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Verifies the server-issued offline credential.
///
/// Format (same shape as a Django hash, own iteration count):
///   `pbkdf2_sha256$<iterations>$<salt_b64>$<hash_b64>`
///
/// Verifies a password against a stored PBKDF2 record: the salt and iteration
/// count are read from [encoded], the password is re-derived, and the result is
/// compared without an early exit.
///
/// The legacy app's "hash" was Base64 of password+salt, which decoded straight
/// back to the plaintext. That is what this replaces, not what it does.
abstract final class PasswordVerifier {
  /// Verifies off the UI thread. PBKDF2 at 150k iterations is deliberately
  /// expensive; running it inline would freeze the frame on an entry-level
  /// handset for the whole derivation.
  static Future<bool> verify(String password, String encoded) =>
      compute(_verifySync, _VerifyRequest(password, encoded));

  /// Synchronous form — for tests and for use already inside an isolate.
  @visibleForTesting
  static bool verifySync(String password, String encoded) =>
      _verifySync(_VerifyRequest(password, encoded));
}

class _VerifyRequest {
  const _VerifyRequest(this.password, this.encoded);
  final String password;
  final String encoded;
}

bool _verifySync(_VerifyRequest request) {
  final parts = request.encoded.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;

  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations <= 0) return false;

  final Uint8List salt;
  final Uint8List expected;
  try {
    salt = base64.decode(parts[2]);
    expected = base64.decode(parts[3]);
  } on FormatException {
    return false;
  }
  if (expected.isEmpty) return false;

  final actual = _pbkdf2Sha256(
    utf8.encode(request.password),
    salt,
    iterations,
    expected.length,
  );
  return _constantTimeEquals(actual, expected);
}

/// PBKDF2-HMAC-SHA256 (RFC 8018).
Uint8List _pbkdf2Sha256(
  List<int> password,
  Uint8List salt,
  int iterations,
  int keyLength,
) {
  final hmac = Hmac(sha256, password);
  const blockSize = 32; // SHA-256 output
  final blocks = (keyLength / blockSize).ceil();
  final output = Uint8List(blocks * blockSize);

  for (var block = 1; block <= blocks; block++) {
    // U1 = PRF(password, salt || INT_32_BE(block))
    final seed = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..[salt.length] = (block >> 24) & 0xff
      ..[salt.length + 1] = (block >> 16) & 0xff
      ..[salt.length + 2] = (block >> 8) & 0xff
      ..[salt.length + 3] = block & 0xff;

    var u = Uint8List.fromList(hmac.convert(seed).bytes);
    final accumulator = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < blockSize; j++) {
        accumulator[j] ^= u[j];
      }
    }
    output.setRange((block - 1) * blockSize, block * blockSize, accumulator);
  }
  return Uint8List.sublistView(output, 0, keyLength);
}

/// Compares without an early exit, so timing does not leak how much matched.
bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
