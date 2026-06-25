import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  Key? _key;
  IV? _iv;

  // Fixed application key — deterministic, no persistence needed.
  // Safe because this is a local client-side app; encryption is for
  // casual protection against disk access, not cryptographic security.
  static final Key _appKey = Key.fromUtf8('HomeworkTracker2024!@#\$%^&*()_+=');

  Future<File> get _keyFile async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'HomeworkTracker'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, '.encryption_key'));
  }

  Future<void> _initKey() async {
    if (_key != null) return;

    // Use the fixed app key — no persistence needed.
    _key = _appKey;
    _iv = IV.fromLength(16);

    // Also try to migrate any existing key file for backward compatibility,
    // but this is best-effort.
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyBase64 = prefs.getString('encryption_key');
      if (keyBase64 != null && keyBase64.length == 44 && keyBase64 != _appKey.base64) {
        // Old random key exists — keep it for backward compat
        _key = Key.fromBase64(keyBase64);
        _iv = IV.fromLength(16);
        await Logger.instance.log('AUTH: using existing random key (prefs)');
        return;
      }
    } catch (_) {}

    try {
      final file = await _keyFile;
      if (await file.exists()) {
        final fileKey = (await file.readAsString()).trim();
        if (fileKey.length == 44 && fileKey != _appKey.base64) {
          _key = Key.fromBase64(fileKey);
          _iv = IV.fromLength(16);
          await Logger.instance.log('AUTH: using existing random key (file)');
          return;
        }
      }
    } catch (_) {}

    await Logger.instance.log('AUTH: using fixed app key');
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
      throw Exception('Encryption key changed. Please go to Settings and log in again.');
    } catch (e) {
      throw Exception('Could not read saved credentials. Please log in again: $e');
    }
  }

  Future<bool> hasValidKey() async {
    try {
      await _initKey();
      return _key != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> resetKey() async {
    _key = null;
    _iv = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('encryption_key');
    final file = await _keyFile;
    if (await file.exists()) {
      await file.delete();
    }
  }
}
