import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  Key? _key;
  IV? _iv;

  Future<void> _initKey() async {
    if (_key != null) return;

    final prefs = await SharedPreferences.getInstance();
    String? keyBase64 = prefs.getString('encryption_key');

    if (keyBase64 == null || keyBase64.length != 44) {
      final newKey = Key.fromSecureRandom(32);
      keyBase64 = newKey.base64;
      await prefs.setString('encryption_key', keyBase64);
    }

    _key = Key.fromBase64(keyBase64);
    _iv = IV.fromLength(16);
  }

  Future<String> encrypt(String value) async {
    await _initKey();
    final encrypter = Encrypter(AES(_key!));
    final encrypted = encrypter.encrypt(value, iv: _iv);
    return encrypted.base64;
  }

  Future<String> decrypt(String encryptedValue) async {
    await _initKey();
    if (encryptedValue.isEmpty) {
      throw Exception('No credentials stored. Please log in to Moodle first.');
    }
    final encrypter = Encrypter(AES(_key!));
    try {
      final decrypted = encrypter.decrypt64(encryptedValue, iv: _iv);
      return decrypted;
    } on FormatException {
      throw Exception('Encryption key changed — please go to Settings and log in to Moodle again to re-save your credentials.');
    } catch (e) {
      throw Exception('Could not read saved credentials. Please log in again: $e');
    }
  }
}
