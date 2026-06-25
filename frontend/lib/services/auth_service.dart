import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  Key? _key;
  IV? _iv;

  Future<void> _initKey() async {
    if (_key != null) return;

    final appDataDir = await getApplicationSupportDirectory();
    final keyDir = Directory(p.join(appDataDir.path, 'HomeworkTracker'));
    if (!await keyDir.exists()) {
      await keyDir.create(recursive: true);
    }

    final keyFile = File(p.join(keyDir.path, '.encryption_key'));

    String keyBase64;
    if (await keyFile.exists()) {
      keyBase64 = await keyFile.readAsString();
    } else {
      final newKey = Key.fromSecureRandom(32);
      keyBase64 = newKey.base64;
      await keyFile.writeAsString(keyBase64);
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
    final encrypter = Encrypter(AES(_key!));
    final decrypted = encrypter.decrypt64(encryptedValue, iv: _iv);
    return decrypted;
  }
}
