import 'package:flutter_test/flutter_test.dart';
import 'package:fsa_app/core/security/password_verifier.dart';

void main() {
  group('PBKDF2-SHA256 against known-answer vectors', () {
    // RFC 6070-style vectors for PBKDF2-HMAC-SHA256. These pin the derivation
    // itself, so a refactor cannot silently change what the app accepts.
    // Verified independently with Python hashlib.pbkdf2_hmac.
    test('password="password", salt="salt", iterations=1', () {
      // base64(pbkdf2_hmac('sha256', b'password', b'salt', 1, 32))
      const encoded =
          r'pbkdf2_sha256$1$c2FsdA==$Eg+2z/z4syxD5yJSVsT4N6hlSMkszDVICAWYfLcL4Xs=';
      expect(PasswordVerifier.verifySync('password', encoded), isTrue);
      expect(PasswordVerifier.verifySync('Password', encoded), isFalse);
    });

    test('password="password", salt="salt", iterations=4096', () {
      const encoded =
          r'pbkdf2_sha256$4096$c2FsdA==$xeR41ZKIyEGqUw22hFxMjZYok6ABzk4RpJY4c6qYE0o=';
      expect(PasswordVerifier.verifySync('password', encoded), isTrue);
      expect(PasswordVerifier.verifySync('passwore', encoded), isFalse);
    });
  });

  group('malformed input is rejected, never accepted', () {
    const cases = <String, String>{
      'empty': '',
      'wrong algorithm': r'bcrypt$150000$c2FsdA==$aGFzaA==',
      'too few parts': r'pbkdf2_sha256$150000$c2FsdA==',
      'non-numeric iterations': r'pbkdf2_sha256$abc$c2FsdA==$aGFzaA==',
      'zero iterations': r'pbkdf2_sha256$0$c2FsdA==$aGFzaA==',
      'negative iterations': r'pbkdf2_sha256$-1$c2FsdA==$aGFzaA==',
      'invalid base64 salt': r'pbkdf2_sha256$1$!!!notbase64!!!$aGFzaA==',
      'empty expected hash': r'pbkdf2_sha256$1$c2FsdA==$',
    };

    cases.forEach((name, encoded) {
      test('rejects $name', () {
        expect(PasswordVerifier.verifySync('anything', encoded), isFalse);
      });
    });
  });

  test('an empty password does not match a real verifier', () {
    const encoded =
        r'pbkdf2_sha256$1$c2FsdA==$Eg+2z/z/1L8mzsqjcgUieThJH/RnwBpAvUpDvSfWfdc=';
    expect(PasswordVerifier.verifySync('', encoded), isFalse);
  });
}
