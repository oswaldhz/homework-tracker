import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import 'database_service.dart';
import 'auth_service.dart';
import 'moodle_service.dart';
import 'ai_service.dart';

class ApiService extends ChangeNotifier {
  List<Task> _tasks = [];
  List<Task> get tasks => _tasks;

  bool _loading = false;
  bool get loading => _loading;

  Map<String, int> _stats = {'total': 0, 'completed': 0, 'pending': 0, 'due_soon': 0, 'overdue': 0};
  Map<String, int> get stats => _stats;

  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> get courses => _courses;

  TaskFilter _filter = const TaskFilter();
  TaskFilter get filter => _filter;

  Future<bool> hasCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('moodle_url')) return false;
      final cred = await DatabaseService.instance.getCredentials();
      if (cred == null) return false;
      try {
        await AuthService.instance.decrypt(cred['encrypted_username']);
        await AuthService.instance.decrypt(cred['encrypted_password']);
        return true;
      } catch (_) {
        await clearCredentials();
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('moodle_url');
    await prefs.remove('username');
    await prefs.remove('password');
    await prefs.remove('login_type');
    await prefs.remove('session_cookie');
    await prefs.remove('remember_me');
    await AuthService.instance.resetKey();
    await DatabaseService.instance.clearAllCredentials();
  }

  Future<Map<String, dynamic>> login(
    String moodleUrl,
    String username,
    String password, {
    String loginType = 'moodle',
    String? sessionCookie,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final encryptedUsername = await AuthService.instance.encrypt(username);
      final encryptedPassword = await AuthService.instance.encrypt(sessionCookie ?? password);
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? false;
      await DatabaseService.instance.saveCredentials(
        moodleUrl,
        encryptedUsername,
        encryptedPassword,
        loginType: loginType,
        rememberMe: rememberMe,
      );

      final result = await MoodleService.instance.scrapeAssignments(
        moodleUrl,
        username,
        password,
        sessionCookie: sessionCookie,
      );

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('moodle_url', moodleUrl);
        await prefs.setString('username', username);
        await prefs.setString('password', sessionCookie ?? password);
        await prefs.setString('login_type', loginType);
        await prefs.setBool('remember_me', true);
        if (sessionCookie != null) {
          await prefs.setString('session_cookie', sessionCookie);
        } else {
          await prefs.remove('session_cookie');
        }
        await fetchTasks();
        await fetchCourses();
        return {'success': true, 'message': 'Login successful', 'tasks_found': result['count']};
      } else {
        return {'success': false, 'message': result['message'] ?? 'Login failed'};
      }
    } catch (e) {
      debugPrint('Login error: $e');
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('socketexception') || errorStr.contains('timeout')) {
        return {'success': false, 'message': 'Connection timed out. Check your internet and Moodle URL.'};
      } else if (errorStr.contains('session cookie is invalid') || errorStr.contains('expired')) {
        return {'success': false, 'message': 'Your Office 365 session has expired. Please log in again.'};
      } else if (errorStr.contains('credentials') || errorStr.contains('check your credentials') || errorStr.contains('login failed')) {
        return {'success': false, 'message': 'Invalid username or password.'};
      } else if (errorStr.contains('connection') || errorStr.contains('network') || errorStr.contains('failed host lookup')) {
        return {'success': false, 'message': 'Cannot reach Moodle server. Check the URL and your connection.'};
      }
      return {'success': false, 'message': 'Login error: $e'};
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTasks({bool weekOnly = false}) async {
    _loading = true;
    notifyListeners();

    try {
      String? status;
      if (_filter.status != null) {
        status = _filter.status;
      }

      final taskData = await DatabaseService.instance.getTasks(
        status: status,
        courseId: _filter.courseId,
        weekOnly: weekOnly,
      );

      _tasks = taskData.map((data) => Task(
        id: data['id'] as int,
        title: data['title'] as String,
        courseName: data['course_name'] as String? ?? 'Unknown',
        dueDate: data['due_date'] != null ? DateTime.tryParse(data['due_date']) : null,
        status: data['status'] as String? ?? 'open',
        isCompleted: (data['is_completed'] as int? ?? 0) == 1,
        fileUploaded: (data['file_uploaded'] as int? ?? 0) == 1,
        isSubmitted: (data['is_submitted'] as int? ?? 0) == 1,
        submissionFiles: [],
        submissionStatus: data['submission_status'] as String?,
        quizGrade: (data['quiz_grade'] as num?)?.toDouble(),
        quizFeedback: data['quiz_feedback'] as String?,
        lastSubmissionCheck: data['last_submission_check'] != null 
            ? DateTime.tryParse(data['last_submission_check'] as String) 
            : null,
        url: data['url'] as String?,
        description: data['description'] as String?,
      )).toList();
    } catch (e) {
      debugPrint('Fetch tasks error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchStats() async {
    try {
      _stats = await DatabaseService.instance.getStats();
      notifyListeners();
    } catch (e) {
      debugPrint('Fetch stats error: $e');
    }
  }

  Future<void> fetchCourses() async {
    try {
      _courses = await DatabaseService.instance.getCourses();
      notifyListeners();
    } catch (e) {
      debugPrint('Fetch courses error: $e');
    }
  }

  Future<Map<String, dynamic>> toggleComplete(int taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      return {'success': false, 'synced': false, 'message': 'Task not found'};
    }

    final originalTask = _tasks[taskIndex];
    final newCompletedState = !originalTask.isCompleted;

    _tasks[taskIndex] = Task(
      id: originalTask.id,
      title: originalTask.title,
      courseName: originalTask.courseName,
      dueDate: originalTask.dueDate,
      status: originalTask.status,
      isCompleted: newCompletedState,
      fileUploaded: originalTask.fileUploaded,
      isSubmitted: originalTask.isSubmitted,
      submissionFiles: originalTask.submissionFiles,
      submissionStatus: originalTask.submissionStatus,
      quizGrade: originalTask.quizGrade,
      quizFeedback: originalTask.quizFeedback,
      lastSubmissionCheck: originalTask.lastSubmissionCheck,
      url: originalTask.url,
      description: originalTask.description,
    );
    notifyListeners();

    try {
      await DatabaseService.instance.toggleTaskCompletion(taskId);
      _updateStats();

      // Background sync with Moodle - with smart retry (fire and forget)
      _syncWithMoodle(taskId, newCompletedState);

      return {
        'success': true,
        'synced': true,
        'message': newCompletedState ? 'Marked as done' : 'Marked as not done',
      };
    } catch (e) {
      _tasks[taskIndex] = originalTask;
      notifyListeners();
      debugPrint('Toggle complete error: $e');
      return {'success': false, 'synced': false, 'message': 'Error: $e'};
    }
  }

  void _updateStats() {
    final total = _tasks.length;
    final completed = _tasks.where((t) => t.isCompleted).length;
    final pending = total - completed;
    final now = DateTime.now();
    final soon = now.add(const Duration(hours: 24));
    final dueSoon = _tasks.where((t) {
      if (t.dueDate == null || t.isCompleted) return false;
      return t.dueDate!.isAfter(now) && t.dueDate!.isBefore(soon);
    }).length;
    final overdue = _tasks.where((t) {
      if (t.dueDate == null || t.isCompleted) return false;
      return t.dueDate!.isBefore(now);
    }).length;

    _stats = {
      'total': total,
      'completed': completed,
      'pending': pending,
      'due_soon': dueSoon,
      'overdue': overdue,
    };
    notifyListeners();
  }

  Future<bool> refresh() async {
    try {
      final cred = await DatabaseService.instance.getCredentials();
      if (cred == null) return false;

      final username = await AuthService.instance.decrypt(cred['encrypted_username']);
      final password = await AuthService.instance.decrypt(cred['encrypted_password']);
      final loginType = cred['login_type'] as String? ?? 'moodle';
      final sessionCookie = loginType == 'office365' ? password : null;

      final result = await MoodleService.instance.scrapeAssignments(
        cred['moodle_url'],
        username,
        password,
        sessionCookie: sessionCookie,
      );
      if (result['success'] == true) {
        await fetchTasks();
        await fetchStats();
        await fetchCourses();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Refresh error: $e');
      return false;
    }
  }

  void setFilter(TaskFilter newFilter) {
    _filter = newFilter;
    notifyListeners();
    fetchTasks();
  }

  void clearFilter() {
    _filter = const TaskFilter();
    notifyListeners();
    fetchTasks();
  }

  Future<Map<String, dynamic>> getMaterials(int taskId) async {
    try {
      final task = await DatabaseService.instance.getTask(taskId);
      if (task == null) return {'error': 'Task not found'};

      final cred = await DatabaseService.instance.getCredentials();
      String? moodleUrl;
      String? username;
      String? password;
      String? sessionCookie;
      String? credentialError;

      if (cred != null) {
        moodleUrl = cred['moodle_url'] as String?;
        try {
          username = await AuthService.instance.decrypt(cred['encrypted_username']);
          password = await AuthService.instance.decrypt(cred['encrypted_password']);
          final loginType = cred['login_type'] as String? ?? 'moodle';
          sessionCookie = loginType == 'office365' ? password : null;
        } catch (e) {
          credentialError = e.toString().replaceFirst('Exception: ', '');
        }
      }

      // Run AI search
      final aiResult = await AiService.instance.findMaterials(
        taskTitle: task['title'],
        taskDescription: task['description'] ?? '',
        courseName: task['course_name'] ?? '',
        moodleUrl: moodleUrl,
        username: username,
        password: password,
        sessionCookie: sessionCookie,
      );

      // Run Moodle content scraping only if credentials work
      if (credentialError == null && moodleUrl != null && username != null && password != null) {
        try {
          final moodleResources = await _scrapeMoodleContent(
            task, moodleUrl, username, password, sessionCookie,
          );
          if (moodleResources.isNotEmpty) {
            aiResult['moodle_resources'] = moodleResources;
            final existingPdfs = aiResult['pdfs'] as List<dynamic>? ?? [];
            final moodlePdfs = moodleResources.where((r) => r['type'] == 'pdf').toList();
            final existingBooks = aiResult['books'] as List<dynamic>? ?? [];
            final moodleBooks = moodleResources.where((r) => r['type'] == 'book').toList();
            final moodleVideos = moodleResources.where((r) => r['type'] == 'video').toList();
            aiResult['pdfs'] = [...existingPdfs, ...moodlePdfs];
            aiResult['books'] = [...existingBooks, ...moodleBooks];
            if (moodleVideos.isNotEmpty) {
              final existingVideos = aiResult['videos'] as List<dynamic>? ?? [];
              aiResult['videos'] = [...existingVideos, ...moodleVideos];
            }
          }
        } catch (e) {
          // Moodle scraping failed, AI result still valid
        }
      }

      if (credentialError != null) {
        aiResult['credential_error'] = credentialError;
      }

      return aiResult;
    } catch (e) {
      return {'error': 'Error: $e'};
    }
  }

  Future<List<Map<String, dynamic>>> _scrapeMoodleContent(
    Map<String, dynamic>? task,
    String? moodleUrl,
    String? username,
    String? password,
    String? sessionCookie,
  ) async {
    if (moodleUrl == null || username == null || password == null || task == null) {
      return [];
    }

    try {
      final courseName = task['course_name'] as String? ?? '';
      if (courseName.isEmpty) return [];

      final resources = await MoodleService.instance.scrapeCourseContent(
        moodleUrl: moodleUrl,
        username: username,
        password: password,
        sessionCookie: sessionCookie,
        courseName: courseName,
      );

      return resources;
    } catch (e) {
      debugPrint('Moodle content scraping error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> uploadFile(int taskId, String filePath) async {
    try {
      final task = await DatabaseService.instance.getTask(taskId);
      if (task == null) return {'success': false, 'message': 'Task not found'};

      final cred = await DatabaseService.instance.getCredentials();
      if (cred == null) return {'success': false, 'message': 'No credentials saved'};

      String username, password;
      try {
        username = await AuthService.instance.decrypt(cred['encrypted_username']);
        password = await AuthService.instance.decrypt(cred['encrypted_password']);
      } catch (e) {
        return {'success': false, 'open_in_browser': true, 'url': task['url'] ?? '', 'message': e.toString().replaceFirst('Exception: ', '')};
      }
      final loginType = cred['login_type'] as String? ?? 'moodle';
      final sessionCookie = loginType == 'office365' ? password : null;

      final result = await MoodleService.instance.uploadFile(
        cred['moodle_url'],
        username,
        password,
        task['url'],
        filePath,
        sessionCookie: sessionCookie,
      );

      if (result['success'] == true) {
        await fetchTasks();
      }

      return result;
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  Future<Map<String, dynamic>> getQuiz(int taskId) async {
    try {
      final task = await DatabaseService.instance.getTask(taskId);
      if (task == null) return {'success': false, 'message': 'Task not found'};

      final cred = await DatabaseService.instance.getCredentials();
      if (cred == null) return {'success': false, 'message': 'No credentials saved'};

      String username, password;
      try {
        username = await AuthService.instance.decrypt(cred['encrypted_username']);
        password = await AuthService.instance.decrypt(cred['encrypted_password']);
      } catch (e) {
        return {'success': false, 'open_in_browser': true, 'url': task['url'] ?? '', 'message': e.toString().replaceFirst('Exception: ', '')};
      }
      final loginType = cred['login_type'] as String? ?? 'moodle';
      final sessionCookie = loginType == 'office365' ? password : null;

      return await MoodleService.instance.getQuizQuestions(
        cred['moodle_url'],
        username,
        password,
        task['url'],
        sessionCookie: sessionCookie,
      );
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  Future<Map<String, dynamic>> submitQuiz(int taskId, Map<String, String> answers) async {
    try {
      final task = await DatabaseService.instance.getTask(taskId);
      if (task == null) return {'success': false, 'message': 'Task not found'};

      final cred = await DatabaseService.instance.getCredentials();
      if (cred == null) return {'success': false, 'message': 'No credentials saved'};

      String username, password;
      try {
        username = await AuthService.instance.decrypt(cred['encrypted_username']);
        password = await AuthService.instance.decrypt(cred['encrypted_password']);
      } catch (e) {
        return {'success': false, 'open_in_browser': true, 'url': task['url'] ?? '', 'message': e.toString().replaceFirst('Exception: ', '')};
      }
      final loginType = cred['login_type'] as String? ?? 'moodle';
      final sessionCookie = loginType == 'office365' ? password : null;

      return await MoodleService.instance.submitQuizAnswers(
        cred['moodle_url'],
        username,
        password,
        task['url'],
        answers,
        sessionCookie: sessionCookie,
      );
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  Future<void> setGeminiKey(String apiKey) async {
    await AiService.instance.setApiKey(apiKey);
  }

  Future<bool> getGeminiStatus() async {
    return await AiService.instance.checkStatus();
  }

  Future<List<Map<String, dynamic>>> getAllSavedCredentials() async {
    return await DatabaseService.instance.getAllSavedCredentials();
  }

  Future<void> saveCredentials(
    String moodleUrl,
    String username,
    String password, {
    String loginType = 'moodle',
    bool rememberMe = false,
  }) async {
    final encryptedUsername = await AuthService.instance.encrypt(username);
    final encryptedPassword = await AuthService.instance.encrypt(password);
    await DatabaseService.instance.saveCredentials(
      moodleUrl,
      encryptedUsername,
      encryptedPassword,
      loginType: loginType,
      rememberMe: rememberMe,
    );
  }

  Future<String> decryptUsername(String encrypted) async {
    return await AuthService.instance.decrypt(encrypted);
  }

  Future<String> decryptPassword(String encrypted) async {
    return await AuthService.instance.decrypt(encrypted);
  }

  Future<void> deleteSavedCredential(int id) async {
    await DatabaseService.instance.deleteSavedCredential(id);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await DatabaseService.instance.clearAll();
    _tasks = [];
    _stats = {'total': 0, 'completed': 0, 'pending': 0, 'due_soon': 0, 'overdue': 0};
    _courses = [];
    _filter = const TaskFilter();
    notifyListeners();
  }

  Future<void> _syncWithMoodle(int taskId, bool completed) async {
    try {
      final task = await DatabaseService.instance.getTask(taskId);
      if (task != null && task['url'] != null && (task['url'] as String).isNotEmpty) {
        final cred = await DatabaseService.instance.getCredentials();
        if (cred != null) {
          String username, password;
          try {
            username = await AuthService.instance.decrypt(cred['encrypted_username']);
            password = await AuthService.instance.decrypt(cred['encrypted_password']);
          } catch (e) {
            debugPrint('Background sync failed: ${e.toString().replaceFirst("Exception: ", "")}');
            return;
          }
          final loginType = cred['login_type'] as String? ?? 'moodle';
          final sessionCookie = loginType == 'office365' ? password : null;
          
          final result = await MoodleService.instance.toggleCompletion(
            cred['moodle_url'] as String,
            username,
            password,
            task['url'] as String,
            completed,
            sessionCookie: sessionCookie,
            maxRetries: 5,
            retryDelay: const Duration(seconds: 3),
          );
          
          debugPrint('Background sync result: $result');
        }
      }
    } catch (e) {
      debugPrint('Background sync error: $e');
    }
  }
}
