import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Logger {
  static final Logger _instance = Logger._();
  Logger._();
  static Logger get instance => _instance;

  File? _logFile;

  Future<void> init() async {
    if (_logFile != null) return;
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'HomeworkTracker'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _logFile = File(p.join(dir.path, 'app.log'));
  }

  Future<void> log(String message) async {
    try {
      await init();
      final timestamp = DateTime.now().toIso8601String();
      await _logFile!.writeAsString('[$timestamp] $message\n', mode: FileMode.append);
    } catch (e) {
      // Logging failures should never crash the app
      debugPrint('Logger error: $e');
    }
  }

  Future<void> clear() async {
    try {
      await init();
      await _logFile!.writeAsString('', mode: FileMode.write);
    } catch (_) {}
  }

  Future<String> getLogPath() async {
    await init();
    return _logFile!.path;
  }
}

