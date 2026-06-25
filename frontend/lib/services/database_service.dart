import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'logger_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final appDataDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(appDataDir.path, 'HomeworkTracker'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final dbPath = p.join(dbDir.path, 'homework_tracker.db');

    return await openDatabase(
      dbPath,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        moodle_id TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        short_name TEXT,
        url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        moodle_id TEXT UNIQUE NOT NULL,
        course_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        due_date TEXT,
        status TEXT DEFAULT 'open',
        is_completed INTEGER DEFAULT 0,
        file_uploaded INTEGER DEFAULT 0,
        is_submitted INTEGER DEFAULT 0,
        submission_files TEXT,
        submission_status TEXT,
        quiz_grade REAL,
        quiz_feedback TEXT,
        last_submission_check TEXT,
        url TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY (course_id) REFERENCES courses(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE credentials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        moodle_url TEXT NOT NULL,
        encrypted_username TEXT NOT NULL,
        encrypted_password TEXT NOT NULL,
        login_type TEXT DEFAULT 'moodle',
        remember_me INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE credentials ADD COLUMN login_type TEXT DEFAULT "moodle"');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE tasks ADD COLUMN file_uploaded INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE tasks ADD COLUMN is_submitted INTEGER DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE credentials ADD COLUMN remember_me INTEGER DEFAULT 0');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE tasks ADD COLUMN submission_files TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN submission_status TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN quiz_grade REAL');
      await db.execute('ALTER TABLE tasks ADD COLUMN quiz_feedback TEXT');
      await db.execute('ALTER TABLE tasks ADD COLUMN last_submission_check TEXT');
    }
  }

  Future<List<Map<String, dynamic>>> getTasks({String? status, String? courseId, bool weekOnly = false}) async {
    final db = await database;

    String where = '1=1';
    final List<dynamic> whereArgs = [];

    if (status != null) {
      if (status == 'pending') {
        where += ' AND is_completed = 0 AND due_date >= ?';
        whereArgs.add(DateTime.now().toIso8601String());
      } else if (status == 'completed') {
        where += ' AND is_completed = 1';
      } else if (status == 'overdue') {
        where += ' AND due_date < ? AND is_completed = 0';
        whereArgs.add(DateTime.now().toIso8601String());
      }
    }

    if (courseId != null && courseId.isNotEmpty) {
      where += ' AND course_id = ?';
      whereArgs.add(int.tryParse(courseId));
    }

    if (weekOnly) {
      final now = DateTime.now();
      final start = now.subtract(Duration(days: now.weekday - 1));
      final startDt = DateTime(start.year, start.month, start.day);
      final endDt = startDt.add(const Duration(days: 7));
      where += ' AND due_date >= ? AND due_date < ?';
      whereArgs.addAll([startDt.toIso8601String(), endDt.toIso8601String()]);
    }

    final tasks = await db.query(
      'tasks',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'due_date ASC',
    );

    final result = <Map<String, dynamic>>[];
    for (final task in tasks) {
      final course = await db.query('courses', where: 'id = ?', whereArgs: [task['course_id']]);
      result.add({
        ...task,
        'course_name': course.isNotEmpty ? course.first['name'] : 'Unknown',
      });
    }

    return result;
  }

  Future<Map<String, int>> getStats() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final soon = DateTime.now().add(const Duration(hours: 24)).toIso8601String();

    final totalResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM tasks');
    final total = (totalResult.first['cnt'] as int?) ?? 0;

    final completedResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM tasks WHERE is_completed = 1');
    final completed = (completedResult.first['cnt'] as int?) ?? 0;

    final dueSoonResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM tasks WHERE due_date BETWEEN ? AND ? AND is_completed = 0',
      [now, soon],
    );
    final dueSoon = (dueSoonResult.first['cnt'] as int?) ?? 0;

    final overdueResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM tasks WHERE due_date < ? AND is_completed = 0',
      [now],
    );
    final overdue = (overdueResult.first['cnt'] as int?) ?? 0;

    return {
      'total': total,
      'completed': completed,
      'pending': total - completed,
      'due_soon': dueSoon,
      'overdue': overdue,
    };
  }

  Future<void> toggleTaskCompletion(int taskId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE tasks SET is_completed = CASE WHEN is_completed = 1 THEN 0 ELSE 1 END, updated_at = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), taskId],
    );
  }

  Future<Map<String, dynamic>?> getTask(int taskId) async {
    final db = await database;
    final tasks = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
    if (tasks.isEmpty) return null;

    final task = tasks.first;
    final course = await db.query('courses', where: 'id = ?', whereArgs: [task['course_id']]);

    return {
      ...task,
      'course_name': course.isNotEmpty ? course.first['name'] : 'Unknown',
      'course_url': course.isNotEmpty ? course.first['url'] : null,
    };
  }

  Future<List<Map<String, dynamic>>> getCourses() async {
    final db = await database;
    return await db.query('courses');
  }

  Future<Map<String, dynamic>?> getCredentials() async {
    final db = await database;
    final creds = await db.query('credentials', orderBy: 'created_at DESC', limit: 1);
    return creds.isNotEmpty ? creds.first : null;
  }

  Future<void> saveCredentials(
    String moodleUrl,
    String encryptedUsername,
    String encryptedPassword, {
    String loginType = 'moodle',
    bool rememberMe = false,
  }) async {
    final db = await database;
    final existing = await db.query(
      'credentials',
      where: 'moodle_url = ? AND encrypted_username = ?',
      whereArgs: [moodleUrl, encryptedUsername],
    );

    final data = {
      'moodle_url': moodleUrl,
      'encrypted_username': encryptedUsername,
      'encrypted_password': encryptedPassword,
      'login_type': loginType,
      'remember_me': rememberMe ? 1 : 0,
    };

    if (existing.isNotEmpty) {
      await db.update(
        'credentials',
        data,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('credentials', {
        ...data,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // Verify the save persisted
    final verify = await db.query('credentials');
    final count = verify.length;
    await Logger.instance.log('DB_SAVE_CRED: table has $count rows after save');
  }

  Future<List<Map<String, dynamic>>> getAllSavedCredentials() async {
    final db = await database;
    return await db.query(
      'credentials',
      where: 'remember_me = 1',
      orderBy: 'created_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getAnyCredential() async {
    final db = await database;
    final results = await db.query('credentials', orderBy: 'created_at DESC', limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> deleteSavedCredential(int id) async {
    final db = await database;
    await db.delete('credentials', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllCredentials() async {
    final db = await database;
    await db.delete('credentials');
  }

  Future<void> saveAssignments(List<Map<String, dynamic>> assignments, String moodleUrl) async {
    final db = await database;

    for (final assignment in assignments) {
      final moodleId = _generateMoodleId(
        assignment['title'].toString(),
        assignment['course_name'].toString(),
        assignment['due_date'] as DateTime?,
      );

      var course = (await db.query('courses', where: 'name = ?', whereArgs: [assignment['course_name']])).firstOrNull;

      if (course == null) {
        var courseUrl = assignment['course_url'] ?? '';
        if (courseUrl.isNotEmpty && !courseUrl.startsWith('http')) {
          courseUrl = '${moodleUrl.replaceAll(RegExp(r'/$'), '')}/${courseUrl.replaceAll(RegExp(r'^/'), '')}';
        }

        final courseId = await db.insert('courses', {
          'moodle_id': 'course_${assignment['course_name'].toString().substring(0, assignment['course_name'].toString().length.clamp(0, 30))}',
          'name': assignment['course_name'],
          'short_name': assignment['course_name'].toString().substring(0, assignment['course_name'].toString().length.clamp(0, 10)),
          'url': courseUrl,
        });
        course = {'id': courseId};
      } else if ((course['url'] == null || course['url'] == '') && assignment['course_url'] != null) {
        var courseUrl = assignment['course_url'] ?? '';
        if (courseUrl.isNotEmpty && !courseUrl.startsWith('http')) {
          courseUrl = '${moodleUrl.replaceAll(RegExp(r'/$'), '')}/${courseUrl.replaceAll(RegExp(r'^/'), '')}';
        }
        await db.update('courses', {'url': courseUrl}, where: 'id = ?', whereArgs: [course['id']]);
      }

      final existing = await db.query('tasks', where: 'moodle_id = ?', whereArgs: [moodleId]);

      final taskData = {
        'course_id': course['id'],
        'title': assignment['title'],
        'due_date': assignment['due_date']?.toIso8601String(),
        'status': assignment['status'] ?? 'open',
        'url': assignment['url'] ?? '',
        'description': assignment['description'] ?? '',
        'file_uploaded': assignment['file_uploaded'] == true ? 1 : 0,
        'is_submitted': assignment['is_submitted'] == true ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing.isNotEmpty) {
        await db.update('tasks', taskData, where: 'moodle_id = ?', whereArgs: [moodleId]);
      } else {
        await db.insert('tasks', {
          ...taskData,
          'moodle_id': moodleId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  /// Generates a stable, unique moodle_id from title, course and due date.
  /// Avoids collisions between assignments that share the same title prefix.
  String _generateMoodleId(String title, String courseName, DateTime? dueDate) {
    final sanitizedTitle = title.substring(0, title.length.clamp(0, 40)).replaceAll(RegExp(r'[^\w]'), '_');
    final sanitizedCourse = courseName.substring(0, courseName.length.clamp(0, 20)).replaceAll(RegExp(r'[^\w]'), '_');
    final dueSuffix = dueDate?.millisecondsSinceEpoch.toString() ?? 'nodate';
    final input = '${sanitizedTitle}_${sanitizedCourse}_$dueSuffix';
    // Simple hash to keep the ID short but unique
    var hash = 5381;
    for (final c in input.codeUnits) {
      hash = ((hash << 5) + hash) + c;
    }
    return '${sanitizedTitle}_${hash.toRadixString(36).replaceAll('-', 'n')}';
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('tasks');
    await db.delete('courses');
    await db.delete('credentials');
  }
}
