import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';
import 'database_service.dart';
import 'logger_service.dart';

class MoodleService {
  static final MoodleService instance = MoodleService._();
  MoodleService._();

  final Map<String, String> _cookies = {};
  String _baseUrl = '';

  // Network configuration
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxRetries = 2;

  http.Client _createClient() => http.Client();

  Map<String, String> _headers() {
    final h = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'es-DO,es;q=0.9,en;q=0.8',
    };
    if (_cookies.isNotEmpty) {
      h['Cookie'] = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    return h;
  }

  void clearCookies() {
    _cookies.clear();
    _baseUrl = '';
  }

  /// Parse Set-Cookie headers while handling the fact that Dart's http
  /// package joins multiple Set-Cookie headers with commas. Cookie
  /// attributes such as Expires also contain commas, so we must not split
  /// naively on every comma.
  void _parseCookies(http.Response response) {
    final values = response.headers['set-cookie'];
    if (values == null || values.isEmpty) return;

    final combined = values.trim();
    if (combined.isEmpty) return;

    // Split by comma, then reassemble segments that are continuations of
    // the same cookie (e.g. Expires=Wed, 21 Oct 2025 ...).
    final rawSegments = combined.split(',');
    final segments = <String>[];
    String? current;

    for (final part in rawSegments) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      if (_isCookieAttributeStart(trimmed)) {
        // This segment is a continuation of the previous Set-Cookie value
        if (current != null) {
          current = '$current, $trimmed';
        }
      } else {
        if (current != null) {
          segments.add(current);
        }
        current = trimmed;
      }
    }
    if (current != null) {
      segments.add(current);
    }

    for (final raw in segments) {
      _parseSetCookieString(raw);
    }
  }

  bool _isCookieAttributeStart(String segment) {
    final lower = segment.toLowerCase();
    final attributePrefixes = [
      'expires=',
      'max-age=',
      'domain=',
      'path=',
      'samesite=',
      'secure',
      'httponly',
      'partitioned',
    ];
    for (final prefix in attributePrefixes) {
      if (lower.startsWith(prefix)) return true;
    }
    return false;
  }

  void _parseSetCookieString(String raw) {
    final parts = raw.split(';');
    if (parts.isEmpty) return;
    final first = parts.first.trim();
    final eq = first.indexOf('=');
    if (eq <= 0) return;
    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (name.isEmpty) return;
    // Ignore attribute-only segments that slipped through
    if (_isCookieAttributeName(name)) return;
    _cookies[name] = value;
  }

  bool _isCookieAttributeName(String name) {
    final lower = name.toLowerCase();
    return const {'expires', 'max-age', 'domain', 'path', 'secure', 'httponly', 'samesite', 'partitioned'}
        .contains(lower);
  }

  Future<http.Response> _get(http.Client client, String url, {Map<String, String>? extraHeaders, int retries = _maxRetries}) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await client
            .get(Uri.parse(url), headers: {..._headers(), ...?extraHeaders})
            .timeout(_requestTimeout);
        _parseCookies(response);
        return response;
      } on SocketException catch (_) {
        if (attempt == retries) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } on HttpException catch (_) {
        if (attempt == retries) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw Exception('Failed to GET $url after retries');
  }

  /// Checks whether the Moodle login page offers an Office 365 / SSO login
  /// option. Returns the SSO URL if found, otherwise null.
  Future<String?> detectSsoLogin(String moodleUrl) async {
    final client = _createClient();
    try {
      _baseUrl = moodleUrl.replaceAll(RegExp(r'/$'), '');
      final loginUrl = '$_baseUrl/login/index.php';
      final resp = await _get(client, loginUrl);
      final doc = html_parser.parse(resp.body);

      // Look for common SSO patterns in href attributes
      final ssoSelectors = [
        'a[href*="office365"]',
        'a[href*="microsoft"]',
        'a[href*="oauth2"]',
        'a[href*="sso"]',
        '#office365-login-btn',
        '.office365-login',
      ];

      for (final selector in ssoSelectors) {
        final el = doc.querySelector(selector);
        if (el != null) {
          final href = el.attributes['href'];
          if (href != null && href.isNotEmpty) {
            return _resolveUrl(href);
          }
        }
      }

      // Also check link text for Office 365 / Microsoft mentions
      final allLinks = doc.querySelectorAll('a');
      final ssoKeywords = RegExp(r'office\s*365|microsoft|sso|iniciar sesión con', caseSensitive: false);
      for (final link in allLinks) {
        final text = link.text.trim();
        final href = link.attributes['href'] ?? '';
        if (ssoKeywords.hasMatch(text) && href.isNotEmpty) {
          return _resolveUrl(href);
        }
      }
      return null;
    } catch (e) {
      debugPrint('SSO detection error: $e');
      return null;
    } finally {
      client.close();
      clearCookies();
    }
  }



  Future<void> _login(String moodleUrl, String username, String password) async {
    const maxAttempts = 3;
    Exception? lastError;

    await Logger.instance.clear();
    await Logger.instance.log('LOGIN: starting for $moodleUrl (user=$username)');

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final client = _createClient();
      try {
        await _attemptLogin(client, moodleUrl, username, password);
        return;
      } on Exception catch (e) {
        lastError = e;
        final errorText = e.toString().toLowerCase()
            .replaceAll('ó', 'o').replaceAll('í', 'i')
            .replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('ú', 'u');
        final isSessionError = errorText.contains('sesion') ||
            errorText.contains('session') ||
            errorText.contains('time');

        await Logger.instance.log('LOGIN: attempt $attempt failed: $e');

        if (!isSessionError || attempt == maxAttempts) {
          client.close();
          rethrow;
        }

        // Wait before retrying with a completely fresh client/session
        client.close();
        clearCookies();
        await Future.delayed(Duration(milliseconds: 800 * attempt));
      }
    }

    throw lastError ?? Exception('Login failed after $maxAttempts attempts');
  }

  Future<void> _attemptLogin(http.Client client, String moodleUrl, String username, String password) async {
    _cookies.clear();
    _baseUrl = moodleUrl.replaceAll(RegExp(r'/$'), '');

    final loginUrl = '$_baseUrl/login/index.php';
    final httpClient = HttpClient();

    Future<({int status, Uri url, String body, Map<String, String> cookies, String? location})> doRequest(String method, Uri url, {String? bodyString}) async {
      final req = method == 'POST'
          ? await httpClient.postUrl(url)
          : await httpClient.openUrl(method, url);
      req.followRedirects = false;
      _applyLoginHeaders(req.headers);
      _attachCookies(req, url);

      if (method == 'POST' && bodyString != null) {
        final bodyBytes = utf8.encode(bodyString);
        req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
        req.headers.set('Content-Length', bodyBytes.length.toString());
        req.add(bodyBytes);
      }

      final resp = await req.close();
      final body = await _readHttpClientResponse(resp);
      final cookies = _extractCookiesFromHeaders(resp.headers);
      final location = _getLocation(resp.headers);
      return (status: resp.statusCode, url: url, body: body, cookies: cookies, location: location);
    }

    try {
      await Logger.instance.log('LOGIN: GET $loginUrl');
      final getResp = await doRequest('GET', Uri.parse(loginUrl));
      for (final e in getResp.cookies.entries) _cookies[e.key] = e.value;
      await Logger.instance.log(
        'LOGIN: GET status=${getResp.status}, url=${getResp.url}, '
        'cookies=[${_cookies.keys.join(', ')}], bodyLength=${getResp.body.length}',
      );

      final doc = html_parser.parse(getResp.body);
      final tokenInput = doc.querySelector('input[name="logintoken"]');
      final logintoken = tokenInput?.attributes['value'] ?? '';
      await Logger.instance.log('LOGIN: token found=${logintoken.isNotEmpty}, tokenLength=${logintoken.length}');

      if (logintoken.isEmpty) {
        throw Exception('Could not find login form. Check the Moodle URL.');
      }

      final bodyString = 'username=${Uri.encodeQueryComponent(username)}'
          '&password=${Uri.encodeQueryComponent(password)}'
          '&logintoken=${Uri.encodeQueryComponent(logintoken)}'
          '&anchor=';
      await Logger.instance.log('LOGIN: POST $loginUrl (username=$username)');
      await Logger.instance.log('LOGIN: POST encodedBody=$bodyString');
      await Logger.instance.log('LOGIN: POST cookieHeader=${_cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')}');

      var current = await doRequest('POST', Uri.parse(loginUrl), bodyString: bodyString);
      await Logger.instance.log(
        'LOGIN: POST status=${current.status}, url=${current.url}, '
        'setCookies=[${current.cookies.keys.join(', ')}], bodyLength=${current.body.length}',
      );

      // Follow redirects manually so cookies are always attached.
      var redirectCount = 0;
      while ((current.status == 301 || current.status == 302 || current.status == 303) &&
             current.location != null &&
             redirectCount < 5) {
        // Update cookies from the redirect response before following.
        for (final e in current.cookies.entries) _cookies[e.key] = e.value;

        final nextUrl = current.url.resolve(current.location!);
        await Logger.instance.log('LOGIN: redirect ${redirectCount + 1} -> $nextUrl, cookies=[${_cookies.keys.join(', ')}]');

        current = await doRequest('GET', nextUrl);
        await Logger.instance.log(
          'LOGIN: redirect status=${current.status}, url=${current.url}, '
          'location=${current.location}, bodyLength=${current.body.length}',
        );
        redirectCount++;
      }

      if (!current.url.toString().contains('/login/')) {
        await Logger.instance.log('LOGIN: success via redirect to ${current.url}');
        return;
      }

      // Check for visible error messages on the final login page
      final errorDoc = html_parser.parse(current.body);
      for (final sel in ['.loginerrormsg', '#loginerrormessage', '.alert.alert-danger', '.alert']) {
        final errorEl = errorDoc.querySelector(sel);
        if (errorEl == null) continue;
        final text = errorEl.text.trim();
        if (text.isNotEmpty && text != '0') {
          await Logger.instance.log('LOGIN: Moodle error message="$text"');
          throw Exception(text);
        }
      }

      await Logger.instance.log('LOGIN: failed without visible error, bodyLength=${current.body.length}');
      await Logger.instance.log('LOGIN: response body snippet=${current.body.substring(0, current.body.length.clamp(0, 1000))}');
      throw Exception('Login failed. Check your credentials.');
    } finally {
      httpClient.close();
    }
  }

  void _attachCookies(HttpClientRequest req, Uri url) {
    if (_cookies.isEmpty) return;
    for (final entry in _cookies.entries) {
      final cookie = Cookie(entry.key, entry.value)
        ..domain = url.host
        ..path = '/';
      req.cookies.add(cookie);
    }
  }

  String? _getLocation(HttpHeaders headers) {
    final raw = headers['location'];
    if (raw == null || raw.isEmpty) return null;
    return raw.join(', ');
  }

  void _applyLoginHeaders(HttpHeaders headers) {
    headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36');
    headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8');
    headers.set('Accept-Encoding', 'gzip, deflate, br');
    headers.set('Connection', 'keep-alive');
  }

  Map<String, String> _extractCookiesFromHeaders(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      if (name.toLowerCase() == 'set-cookie') {
        for (final value in values) {
          final first = value.split(';').first.trim();
          final eq = first.indexOf('=');
          if (eq > 0) {
            final cookieName = first.substring(0, eq).trim();
            final cookieValue = first.substring(eq + 1).trim();
            if (cookieName.isNotEmpty && !_isCookieAttributeName(cookieName)) {
              result[cookieName] = cookieValue;
            }
          }
        }
      }
    });
    return result;
  }

  Future<String> _readHttpClientResponse(HttpClientResponse response) async {
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks);
  }

  /// Validates that a session cookie obtained from an external login (e.g.
  /// Office 365 SSO) is accepted by Moodle. Throws if invalid.
  Future<void> _loginWithSessionCookie(http.Client client, String moodleUrl, String sessionCookie) async {
    _cookies.clear();
    _baseUrl = moodleUrl.replaceAll(RegExp(r'/$'), '');

    // Accept either a single MoodleSession value or a full Cookie header
    if (sessionCookie.contains('=')) {
      for (final pair in sessionCookie.split(';')) {
        final trimmed = pair.trim();
        if (trimmed.isEmpty) continue;
        final eq = trimmed.indexOf('=');
        if (eq > 0) {
          final name = trimmed.substring(0, eq).trim();
          final value = trimmed.substring(eq + 1).trim();
          if (name.isNotEmpty) _cookies[name] = value;
        }
      }
    } else {
      _cookies['MoodleSession'] = sessionCookie.trim();
    }

    // Verify the cookie works by fetching the dashboard/homepage
    final resp = await _get(client, '$_baseUrl/my/');
    final body = resp.body.toLowerCase();
    final url = resp.request?.url.toString() ?? '';

    // If we got redirected back to login, the cookie is invalid
    if (url.contains('/login/') || body.contains('login/index.php') || body.contains('id="username"')) {
      throw Exception('The session cookie is invalid or has expired. Please log in again.');
    }

    // Make sure we captured any rotated session cookie from the response
    _parseCookies(resp);
  }

  String _resolveUrl(String href) {
    if (href.startsWith('http')) return href;
    if (href.startsWith('//')) return 'https:$href';
    return '$_baseUrl${href.startsWith('/') ? '' : '/'}$href';
  }

  String? _extractSesskey(String html) {
    final match = RegExp(r'sesskey=([a-zA-Z0-9]+)').firstMatch(html);
    return match?.group(1);
  }

  Future<void> _checkCourseSubmissionStatus(http.Client client, Map<String, dynamic> course) async {
    try {
      final courseUrl = course['url']?.toString() ?? '';
      if (courseUrl.isEmpty) return;

      final resp = await _get(client, courseUrl);
      final doc = html_parser.parse(resp.body);

      // Look for assignment modules with submission status
      final modules = doc.querySelectorAll('.activity');
      for (final module in modules) {
        // Check if this is an assignment or quiz
        final link = module.querySelector('a[href*="/mod/assign/"], a[href*="/mod/quiz/"]');
        if (link == null) continue;
        final activityUrl = link.attributes['href'] ?? '';
        if (activityUrl.isEmpty) continue;

        // Look for submission status indicators
        final statusEl = module.querySelector('.submissionstatustext, .feedback, .gradereport');
        final statusText = statusEl?.text.trim().toLowerCase() ?? '';

        final hasSubmitted = statusText.contains('submitted') || 
                             statusText.contains('submitted for grading') ||
                             statusText.contains('graded') ||
                             statusText.contains('entregado') ||
                             statusText.contains('calificado');

        if (hasSubmitted) {
          final db = await DatabaseService.instance.database;
          final existing = await db.query('tasks', where: 'url = ?', whereArgs: [activityUrl]);
          if (existing.isNotEmpty) {
            await db.update('tasks',
              {'is_submitted': 1, 'file_uploaded': 1},
              where: 'url = ?', whereArgs: [activityUrl],
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> scrapeAssignments(
    String moodleUrl,
    String username,
    String password, {
    String? sessionCookie,
  }) async {
    final client = _createClient();
    try {
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
      } else {
        await _login(moodleUrl, username, password);
      }

      final calendarUrl = '$_baseUrl/calendar/view.php?view=upcoming';
      final resp = await _get(client, calendarUrl);

      final doc = html_parser.parse(resp.body);
      var eventElements = doc.querySelectorAll('[data-type="event"]');
      if (eventElements.isEmpty) {
        eventElements = doc.querySelectorAll('.event, .calendar_event, .event-card');
      }

      final assignments = <Map<String, dynamic>>[];
      for (final event in eventElements) {
        try {
          final title = event.querySelector('.event-name a, h3.name, .card-header a, .event-title a')?.text.trim() ?? '';
          if (title.isEmpty) continue;

          DateTime? dueDate;
          final tsEl = event.querySelector('[data-timestamp]');
          if (tsEl != null) {
            final ts = int.tryParse(tsEl.attributes['data-timestamp'] ?? '');
            if (ts != null) dueDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          }
          if (dueDate == null) {
            final dateEl = event.querySelector('.date, .event-date, .time');
            if (dateEl != null) {
              final dateText = dateEl.text.trim();
              final ts = int.tryParse(dateText.replaceAll(RegExp(r'[^0-9]'), ''));
              if (ts != null && ts > 1000000000) {
                dueDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
              }
            }
          }

          final courseEl = event.querySelector('a[href*="/course/view.php"], .course a, .event-course a');
          final courseName = courseEl?.text.trim() ?? 'ITLA';
          final courseUrl = courseEl?.attributes['href'] ?? '';

          final urlEl = event.querySelector('a[href*="/mod/"], a.card-link, .card-footer a');
          final url = urlEl?.attributes['href'] ?? '';

          final descEl = event.querySelector('.description-content, .description, .event-description');
          final descText = descEl?.text.trim() ?? '';
          final description = descText.length > 500 ? descText.substring(0, 500) : descText;

          assignments.add({
            'title': title,
            'course_name': courseName,
            'course_url': courseUrl,
            'due_date': dueDate,
            'url': url,
            'description': description,
            'status': 'open',
          });
        } catch (_) {}
      }

      await DatabaseService.instance.saveAssignments(assignments, moodleUrl);

      // Check submission status for each course
      final courses = await DatabaseService.instance.getCourses();
      for (final course in courses) {
        await _checkCourseSubmissionStatus(client, course);
      }

      return {'success': true, 'count': assignments.length};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> toggleCompletion(
    String moodleUrl,
    String username,
    String password,
    String taskUrl,
    bool complete, {
    String? sessionCookie,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    final client = _createClient();
    try {
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
      } else {
        await _login(moodleUrl, username, password);
      }

      final taskPageResp = await _get(client, taskUrl);

      final sesskey = _extractSesskey(taskPageResp.body);
      if (sesskey == null) {
        return {'success': false, 'message': 'Could not find session key. Please try again.'};
      }

      final uri = Uri.parse(taskUrl);
      final cmid = uri.queryParameters['id'];
      if (cmid == null) {
        return {'success': false, 'message': 'Invalid task URL.'};
      }

      // Toggle completion with retry logic
      Exception? lastError;
      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          await _get(client, '$_baseUrl/course/togglecompletion.php?id=$cmid&sesskey=$sesskey');
          
          // Verify the toggle worked by checking the page
          await Future.delayed(const Duration(milliseconds: 500));
          final verifyResp = await _get(client, taskUrl);
          final verifyDoc = html_parser.parse(verifyResp.body);
          
          // Check for completion indicator
          final completionIcon = verifyDoc.querySelector('.activity-completion-icon, .completionstatus, [class*="completion"]');
          bool verified = false;
          if (completionIcon != null) {
            final classes = completionIcon.attributes['class'] ?? '';
            if (complete) {
              verified = classes.contains('complete') || classes.contains('completed') || classes.contains('check');
            } else {
              verified = !classes.contains('complete') && !classes.contains('completed');
            }
          }
          
          if (verified || attempt == maxRetries) {
            return {
              'success': true, 
              'message': complete ? 'Marked as complete on Moodle' : 'Marked as incomplete on Moodle',
              'verified': verified,
            };
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
          }
        }
      }

      return {'success': false, 'message': 'Failed to toggle completion after retries: ${lastError?.toString() ?? "Unknown error"}'};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> uploadFile(
    String moodleUrl,
    String username,
    String password,
    String taskUrl,
    String filePath, {
    String? sessionCookie,
  }) async {
    final client = _createClient();
    try {
      await Logger.instance.log('UPLOAD: Starting upload for $taskUrl');
      
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
      } else {
        await _login(moodleUrl, username, password);
      }

      final uri = Uri.parse(taskUrl);
      final cmid = uri.queryParameters['id'];
      if (cmid == null) {
        await Logger.instance.log('UPLOAD: Invalid task URL - no cmid');
        return {'success': false, 'open_in_browser': true, 'url': taskUrl, 'message': 'Invalid task URL.'};
      }

      // Step 1: Get edit submission page to extract form fields and current itemid
      final editUrl = '$_baseUrl/mod/assign/view.php?id=$cmid&action=editsubmission';
      await Logger.instance.log('UPLOAD: Fetching edit page: $editUrl');
      final editResp = await _get(client, editUrl);
      final editDoc = html_parser.parse(editResp.body);

      final sesskey = _extractSesskey(editResp.body);
      if (sesskey == null) {
        await Logger.instance.log('UPLOAD: Could not find sesskey');
        return {'success': false, 'open_in_browser': true, 'url': taskUrl, 'message': 'Could not find session key. Please upload in your browser.'};
      }
      await Logger.instance.log('UPLOAD: Found sesskey: $sesskey');

      // Extract itemid from the file manager form
      int? itemid;
      final fileManagerForm = editDoc.querySelector('form[id^="filemanager"]') ?? editDoc.querySelector('form[action*="repository_ajax"]');
      if (fileManagerForm != null) {
        final itemidInput = fileManagerForm.querySelector('input[name="itemid"]');
        if (itemidInput != null) {
          itemid = int.tryParse(itemidInput.attributes['value'] ?? '');
          await Logger.instance.log('UPLOAD: Found itemid from form: $itemid');
        }
      }

      // Also check for itemid in the repository call context
      if (itemid == null) {
        final itemidMatch = RegExp("itemid[\"']?\\s*[:=]\\s*[\"']?(\\d+)").firstMatch(editResp.body);
        if (itemidMatch != null) {
          itemid = int.tryParse(itemidMatch.group(1)!);
          await Logger.instance.log('UPLOAD: Found itemid from regex: $itemid');
        }
      }

      // Fallback: try to get itemid from the draft file area
      if (itemid == null) {
        itemid = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await Logger.instance.log('UPLOAD: Using generated itemid: $itemid');
      }

      // Step 2: Upload file to Moodle draft area (repository)
      await Logger.instance.log('UPLOAD: Uploading file to draft area');
      final file = await http.MultipartFile.fromPath('repo_upload_file', filePath);
      final uploadRequest = http.MultipartRequest('POST', Uri.parse('$_baseUrl/repository/repository_ajax.php?action=upload'))
        ..headers.addAll({..._headers(), 'Accept': 'application/json'})
        ..fields['sesskey'] = sesskey
        ..fields['repo_id'] = '4'
        ..fields['env'] = 'filemanager'
        ..fields['itemid'] = itemid.toString()
        ..fields['author'] = username
        ..files.add(file);

      final uploadStream = await client.send(uploadRequest).timeout(_requestTimeout);
      final uploadResp = await http.Response.fromStream(uploadStream);
      _parseCookies(uploadResp);
      
      await Logger.instance.log('UPLOAD: Draft upload response status: ${uploadResp.statusCode}');
      await Logger.instance.log('UPLOAD: Draft upload response body: ${uploadResp.body.substring(0, uploadResp.body.length.clamp(0, 500))}');

      // Parse upload response to get the file info (including updated itemid)
      int? uploadedItemid;
      String? uploadedFilename;
      try {
        final uploadData = jsonDecode(uploadResp.body);
        if (uploadData is List && uploadData.isNotEmpty) {
          final firstFile = uploadData[0];
          uploadedItemid = firstFile['itemid'] as int?;
          uploadedFilename = firstFile['filename'] as String?;
          await Logger.instance.log('UPLOAD: Parsed from list - itemid: $uploadedItemid, filename: $uploadedFilename');
        } else if (uploadData is Map) {
          uploadedItemid = uploadData['itemid'] as int?;
          uploadedFilename = uploadData['filename'] as String?;
          await Logger.instance.log('UPLOAD: Parsed from map - itemid: $uploadedItemid, filename: $uploadedFilename');
        }
      } catch (e) {
        await Logger.instance.log('UPLOAD: Failed to parse upload response: $e');
      }

      if (uploadedItemid == null && uploadedFilename == null) {
        await Logger.instance.log('UPLOAD: Draft upload failed - no itemid or filename returned');
        return {'success': false, 'open_in_browser': true, 'url': taskUrl, 'message': 'File upload to draft area failed. Please try in your browser.'};
      }

      final finalItemid = uploadedItemid ?? itemid;
      await Logger.instance.log('UPLOAD: Using final itemid: $finalItemid');

      // Step 3: Submit the assignment with the uploaded file reference
      await Logger.instance.log('UPLOAD: Submitting assignment with savesubmission');
      final submitResp = await client.post(
        Uri.parse('$_baseUrl/mod/assign/view.php?id=$cmid&action=savesubmission'),
        headers: _headers(),
        body: {
          'sesskey': sesskey,
          '_qf__mod_assign_submission_form': '1',
          'files_filemanager': finalItemid.toString(),
          'submitbutton': 'Save changes',
        },
      ).timeout(_requestTimeout);
      
      await Logger.instance.log('UPLOAD: Savesubmission response status: ${submitResp.statusCode}');
      await Logger.instance.log('UPLOAD: Savesubmission response body: ${submitResp.body.substring(0, submitResp.body.length.clamp(0, 500))}');

      // Step 4: Verify submission by checking the assignment page
      await Future.delayed(const Duration(milliseconds: 500));
      await Logger.instance.log('UPLOAD: Verifying submission');
      final verifyResp = await _get(client, '$_baseUrl/mod/assign/view.php?id=$cmid');
      final verifyDoc = html_parser.parse(verifyResp.body);
      
      // Check for submission status indicators
      bool hasSubmission = false;
      String? submissionStatus;
      String? submittedFileName;
      
      final statusEl = verifyDoc.querySelector('.submissionstatustext, .submissionstatus, .assignsubmissionstatus, .status');
      if (statusEl != null) {
        final statusText = statusEl.text.trim().toLowerCase();
        await Logger.instance.log('UPLOAD: Found status element: ${statusEl.text.trim()}');
        if (statusText.contains('submitted') || statusText.contains('entregado') || statusText.contains('graded') || statusText.contains('calificado')) {
          hasSubmission = true;
          submissionStatus = statusEl.text.trim();
        }
      }
      
      // Check for file list in submission
      final fileList = verifyDoc.querySelectorAll('.filemanager-file, .fp-file, .submission-file');
      if (fileList.isNotEmpty) {
        hasSubmission = true;
        submittedFileName = fileList.first.text.trim();
        await Logger.instance.log('UPLOAD: Found file in submission: $submittedFileName');
      }

      await Logger.instance.log('UPLOAD: Verification result - hasSubmission: $hasSubmission, status: $submissionStatus');

      // Update local DB with submission info
      final db = await DatabaseService.instance.database;
      final existing = await db.query('tasks', where: 'url = ?', whereArgs: [taskUrl]);
      if (existing.isNotEmpty) {
        final submissionFiles = [
          {
            'filename': uploadedFilename ?? submittedFileName ?? filePath.split('/').last,
            'size': await File(filePath).length(),
            'uploaded_at': DateTime.now().toIso8601String(),
            'itemid': finalItemid,
          }
        ];
        await db.update('tasks',
          {
            'file_uploaded': hasSubmission ? 1 : 1,
            'is_submitted': hasSubmission ? 1 : 1,
            'submission_files': jsonEncode(submissionFiles),
            'submission_status': submissionStatus ?? 'Submitted via app',
            'last_submission_check': DateTime.now().toIso8601String(),
          },
          where: 'url = ?', whereArgs: [taskUrl],
        );
      }

      return {
        'success': true, 
        'message': hasSubmission ? 'File uploaded and submission saved' : 'File uploaded (submission may need verification)',
        'filename': uploadedFilename ?? filePath.split('/').last,
        'verified': hasSubmission,
      };
    } catch (e) {
      await Logger.instance.log('UPLOAD: Exception: $e');
      return {'success': false, 'open_in_browser': true, 'url': taskUrl, 'message': 'Upload failed: $e'};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> getQuizQuestions(
    String moodleUrl,
    String username,
    String password,
    String quizUrl, {
    String? sessionCookie,
  }) async {
    return {'success': false, 'open_in_browser': true, 'url': quizUrl, 'message': 'Open the quiz in your browser'};
  }

  Future<Map<String, dynamic>> submitQuizAnswers(
    String moodleUrl,
    String username,
    String password,
    String quizUrl,
    Map<String, String> answers, {
    String? sessionCookie,
  }) async {
    return {'success': false, 'open_in_browser': true, 'url': quizUrl, 'message': 'Submit the quiz in your browser'};
  }

  Future<Map<String, dynamic>> checkSubmissionStatus(
    String moodleUrl,
    String username,
    String password,
    String taskUrl, {
    String? sessionCookie,
  }) async {
    final client = _createClient();
    try {
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
      } else {
        await _login(moodleUrl, username, password);
      }

      final uri = Uri.parse(taskUrl);
      final cmid = uri.queryParameters['id'];
      if (cmid == null) {
        return {'success': false, 'message': 'Invalid task URL.'};
      }

      // Check assignment submission status
      final assignResp = await _get(client, '$_baseUrl/mod/assign/view.php?id=$cmid');
      final assignDoc = html_parser.parse(assignResp.body);

      bool hasSubmission = false;
      String? submissionStatus;
      List<Map<String, dynamic>> submissionFiles = [];

      // Check for submission status
      final statusEl = assignDoc.querySelector('.submissionstatustext, .submissionstatus, .assignsubmissionstatus, .status');
      if (statusEl != null) {
        final statusText = statusEl.text.trim().toLowerCase();
        if (statusText.contains('submitted') || statusText.contains('entregado') || statusText.contains('graded') || statusText.contains('calificado')) {
          hasSubmission = true;
          submissionStatus = statusEl.text.trim();
        }
      }

      // Check for file list in submission
      final fileList = assignDoc.querySelectorAll('.filemanager-file, .fp-file, .submission-file, .submission-file-list a');
      for (final fileEl in fileList) {
        final fileName = fileEl.text.trim();
        final fileUrl = fileEl.attributes['href'];
        if (fileName.isNotEmpty) {
          submissionFiles.add({
            'filename': fileName,
            'url': fileUrl != null ? _resolveUrl(fileUrl) : null,
            'checked_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // Check quiz grade if it's a quiz
      double? quizGrade;
      String? quizFeedback;
      if (taskUrl.contains('/mod/quiz/')) {
        final quizResp = await _get(client, '$_baseUrl/mod/quiz/report.php?id=$cmid');
        final quizDoc = html_parser.parse(quizResp.body);
        
        // Try to find grade
        final gradeEl = quizDoc.querySelector('.grade, .quiz-grade, [class*="grade"]');
        if (gradeEl != null) {
          final gradeText = gradeEl.text.trim();
          final gradeMatch = RegExp(r'(\d+(?:\.\d+)?)%?').firstMatch(gradeText);
          if (gradeMatch != null) {
            quizGrade = double.tryParse(gradeMatch.group(1)!);
          }
        }
        
        // Try to find feedback
        final feedbackEl = quizDoc.querySelector('.feedback, .quiz-feedback');
        if (feedbackEl != null) {
          quizFeedback = feedbackEl.text.trim();
        }
      }

      // Update local DB
      final db = await DatabaseService.instance.database;
      final existing = await db.query('tasks', where: 'url = ?', whereArgs: [taskUrl]);
      if (existing.isNotEmpty) {
        final updates = <String, dynamic>{
          'last_submission_check': DateTime.now().toIso8601String(),
        };
        
        if (hasSubmission || submissionFiles.isNotEmpty) {
          updates['file_uploaded'] = 1;
          updates['is_submitted'] = 1;
          updates['submission_files'] = jsonEncode(submissionFiles);
          if (submissionStatus != null) {
            updates['submission_status'] = submissionStatus;
          }
        }
        
        if (quizGrade != null) {
          updates['quiz_grade'] = quizGrade;
        }
        if (quizFeedback != null) {
          updates['quiz_feedback'] = quizFeedback;
        }

        await db.update('tasks', updates, where: 'url = ?', whereArgs: [taskUrl]);
      }

      return {
        'success': true,
        'has_submission': hasSubmission,
        'submission_status': submissionStatus,
        'files': submissionFiles,
        'quiz_grade': quizGrade,
        'quiz_feedback': quizFeedback,
      };
    } catch (e) {
      return {'success': false, 'message': 'Check failed: $e'};
    } finally {
      client.close();
    }
  }

  /// Launches the given SSO URL in the user's default browser. After login
  /// the user must provide the MoodleSession cookie to the app.
  Future<void> launchSsoLogin(String ssoUrl) async {
    final uri = Uri.parse(ssoUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $ssoUrl in the browser.');
    }
  }
}
