import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-scoped secret storage (Flutter port of the Swift SecretStore).
///
/// On first launch a random 256-bit device number is generated and kept in the
/// secure storage (Android Keystore-backed; only readable on this device). A
/// symmetric AES-GCM key is derived from it (SHA-256) and used to encrypt the
/// GitHub token before persisting it. Any older plaintext token is migratated on
/// read, then removed.
class SecretStore {
  SecretStore._();
  static final SecretStore _i = SecretStore._();
  static final _storage = const FlutterSecureStorage();

  static const _deviceKey = 'deviceNumber';
  static const _tokenEncKey = 'ghTokenEnc';
  static const _tokenLegacyKey = 'ghToken';

  static const _blobVersion = 0x01;

  // SHA-256(AES key bytes). Reused for token encrypt/decrypt.
  static Future<SecretKey> _aesKey() async {
    final device = await deviceNumber();
    final hash = await Sha256().hash(device);
    return AesGcm.with256bits().newSecretKeyFromBytes(hash.bytes);
  }

  static Future<String?> loadToken() async {
    final stored = await _storage.read(key: _tokenEncKey);
    if (stored != null && stored.isNotEmpty) {
      final d = await _decrypt(stored);
      if (d != null) return d;
    }
    final legacy = await _storage.read(key: _tokenLegacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      await storeToken(legacy);
      await _storage.delete(key: _tokenLegacyKey);
      return legacy;
    }
    return null;
  }

  static Future<void> storeToken(String token) async {
    final blob = await _encrypt(token);
    if (blob == null) {
      await _storage.delete(key: _tokenEncKey);
      return;
    }
    await _storage.write(key: _tokenEncKey, value: blob);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenEncKey);
    await _storage.delete(key: _tokenLegacyKey);
  }

  /// 256-bit device number: generate once, then reuse.
  static Future<List<int>> deviceNumber() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) {
      return base64UrlDecode(existing);
    }
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    await _storage.write(key: _deviceKey, value: base64UrlEncode(bytes));
    return bytes;
  }

  // Blob layout: 0x01 || AES-GCM concatenation (nonce || cipherText || mac).
  static Future<String?> _encrypt(String token) async {
    try {
      final bytes = utf8.encode(token);
      final key = await _aesKey();
      final alg = AesGcm.with256bits();
      final box = await alg.encrypt(bytes, secretKey: key);
      final payload = box.concatenation();
      final blob = <int>[0x01, ...payload];
      return base64Encode(blob);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _decrypt(String base64) async {
    try {
      final blob = base64Decode(base64);
      if (blob.length < 2 || blob[0] != _blobVersion) return null;
      final payload = blob.sublist(1);
      final alg = AesGcm.with256bits();
      final box = SecretBox.fromConcatenation(
        payload,
        nonceLength: alg.nonceLength,
        macLength: 16,
      );
      final key = await _aesKey();
      final clear = await alg.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}