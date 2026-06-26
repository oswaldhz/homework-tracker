import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'database_service.dart';
import 'logger_service.dart';

class MoodleService {
  static final MoodleService instance = MoodleService._();
  MoodleService._();

  final Map<String, String> _cookies = {};
  String? get currentSessionCookie => _cookies['MoodleSession'];
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
    final url = resp.request?.url.toString() ?? '';

    // If we got redirected back to login, the cookie is invalid
    if (url.contains('/login/')) {
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

  void _saveDebugResponse(String body, String label) {
    try {
      final path = '${Directory.systemTemp.path}/homework_tracker_${label}_${DateTime.now().millisecondsSinceEpoch}.html';
      File(path).writeAsStringSync(body);
      Logger.instance.log('DEBUG: Saved $label response to $path');
    } catch (_) {}
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

        // Look for submission status indicators in the activity info area
        final statusEl = module.querySelector(
          '.submissionstatustext, '
          '.submissionstatus, '
          '.activity-submissioninfo, '
          '.activity-info .submissionstatustext, '
          '.activity-info .submissionstatus, '
          '.activity-info span, '
          '.feedback, '
          '.gradereport, '
          'div[class*="infostatus"] span',
        );
        final statusText = statusEl?.text.trim().toLowerCase() ?? '';

        final hasSubmitted = statusText.contains('submitted') ||
                             statusText.contains('entregado') ||
                             statusText.contains('graded') ||
                             statusText.contains('calificado') ||
                             statusText.contains('for grading');

        if (hasSubmitted) {
          final db = await DatabaseService.instance.database;
          final existing = await db.query('tasks', where: 'url = ?', whereArgs: [activityUrl]);
          if (existing.isNotEmpty) {
            await db.update('tasks',
              {
                'is_submitted': 1,
                'file_uploaded': 1,
                'submission_status': statusEl!.text.trim(),
              },
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
        try {
          await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
        } catch (_) {
          await Logger.instance.log('SCRAPE: Saved session expired, logging in fresh');
          _cookies.clear();
          await _login(moodleUrl, username, password);
        }
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
      await Logger.instance.log('TOGGLE: Starting toggleCompletion for $taskUrl, complete=$complete');

      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        try {
          await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
        } catch (_) {
          await Logger.instance.log('TOGGLE: Saved session expired, logging in fresh');
          _cookies.clear();
          await _login(moodleUrl, username, password);
        }
      } else {
        await _login(moodleUrl, username, password);
      }

      // First, get the task page to extract sesskey and verify current state
      final taskPageResp = await _get(client, taskUrl);

      final sesskey = _extractSesskey(taskPageResp.body);
      if (sesskey == null) {
        await Logger.instance.log('TOGGLE: Could not find sesskey');
        return {'success': false, 'message': 'Could not find session key. Please try again.'};
      }
      await Logger.instance.log('TOGGLE: Found sesskey: $sesskey');

      final uri = Uri.parse(taskUrl);
      final cmid = uri.queryParameters['id'];
      if (cmid == null) {
        await Logger.instance.log('TOGGLE: Invalid task URL - no cmid');
        return {'success': false, 'message': 'Invalid task URL.'};
      }

      // Toggle completion with retry logic
      Exception? lastError;
      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          await Logger.instance.log('TOGGLE: Attempt $attempt: Sending toggle request');
          
          // Moodle togglecompletion.php needs a proper GET request with sesskey
          // It returns a redirect back to the course page or the activity page
          final toggleUrl = '$_baseUrl/course/togglecompletion.php?id=$cmid&sesskey=$sesskey';
          await Logger.instance.log('TOGGLE: URL: $toggleUrl');
          
          try {
            final toggleResp = await _get(client, toggleUrl);
            await Logger.instance.log('TOGGLE: Response status: ${toggleResp.statusCode}');
            await Logger.instance.log('TOGGLE: Response URL: ${toggleResp.request?.url}');
          } catch (e) {
            await Logger.instance.log('TOGGLE: Toggle request exception (expected redirect): $e');
          }

          // Wait for Moodle to process
          await Future.delayed(const Duration(milliseconds: 1000));
          
          // Verify the toggle worked by checking the page:
          // - Check for completion checkbox/toggle state
          // - Check for completion status text
          // - Check the URL to see if we ended up on the course page (success indicator)
          final verifyResp = await _get(client, taskUrl);
          final verifyDoc = html_parser.parse(verifyResp.body);
          
          bool verified = false;
          
          // Method 1: Check for manual completion checkbox state
          final completionCheckbox = verifyDoc.querySelector('input[type="checkbox"][name="completion"]');
          if (completionCheckbox != null) {
            final isChecked = completionCheckbox.attributes['checked'] != null;
            if (complete == isChecked) {
              verified = true;
              await Logger.instance.log('TOGGLE: Verified via checkbox, checked=$isChecked');
            }
          }
          
          // Method 2: Check completion icon/indicator class
          if (!verified) {
            final completionEls = verifyDoc.querySelectorAll(
              '.completion_checkbox, .completion_complete, .completion_incomplete, '
              '[class*="completion"], .activity-completion, .completion-icon'
            );
            for (final el in completionEls) {
              final classes = (el.attributes['class'] ?? '') + ' ' + (el.text.trim().toLowerCase());
              if (complete && (classes.contains('completion_complete') || classes.contains('complete') || classes.contains('checked') || classes.contains('check'))) {
                verified = true;
                await Logger.instance.log('TOGGLE: Verified via completion class: ${el.attributes['class']}');
                break;
              } else if (!complete && (classes.contains('completion_incomplete') || classes.contains('incomplete') || classes.isEmpty)) {
                verified = true;
                await Logger.instance.log('TOGGLE: Verified via incomplete class: ${el.attributes['class']}');
                break;
              }
            }
          }

          // Method 3: Check if we have a form with completion tracking
          if (!verified) {
            final manualCompletion = verifyDoc.querySelector('.manual-completion-button, [data-toggle="manual-completion"]');
            if (manualCompletion != null && !complete) {
              verified = true;
              await Logger.instance.log('TOGGLE: Verified via manual-completion-button available');
            }
          }

          // Method 4: In some Moodle themes, completion is shown via image/icon
          if (!verified) {
            final completionIcons = verifyDoc.querySelectorAll('img[alt*="complete" i], img[alt*="incomplete" i], .completion-icon img');
            for (final icon in completionIcons) {
              final alt = (icon.attributes['alt'] ?? '').toLowerCase();
              final src = (icon.attributes['src'] ?? '').toLowerCase();
              final combined = '$alt $src';
              if (complete && (combined.contains('complete') || combined.contains('check'))) {
                verified = true;
                await Logger.instance.log('TOGGLE: Verified via completion icon alt/src');
                break;
              } else if (!complete && combined.contains('incomplete')) {
                verified = true;
                await Logger.instance.log('TOGGLE: Verified via incomplete icon');
                break;
              }
            }
          }

          await Logger.instance.log('TOGGLE: Attempt $attempt - verified=$verified');

          if (verified || attempt == maxRetries) {
            return {
              'success': true, 
              'message': complete ? 'Marked as complete on Moodle' : 'Marked as incomplete on Moodle',
              'verified': verified,
            };
          }
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          await Logger.instance.log('TOGGLE: Attempt $attempt error: $e');
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
          }
        }
      }

      await Logger.instance.log('TOGGLE: Failed after retries');
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
    int? taskId,
    String? sessionCookie,
  }) async {
    final client = _createClient();
    try {
      await Logger.instance.log('UPLOAD: Starting upload for $taskUrl');
      
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        try {
          await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
        } catch (_) {
          await Logger.instance.log('UPLOAD: Saved session expired, logging in fresh');
          _cookies.clear();
          await _login(moodleUrl, username, password);
        }
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

      String? extractNumber(String source, List<RegExp> patterns) {
        for (final pattern in patterns) {
          final match = pattern.firstMatch(source);
          if (match != null) return match.group(1);
        }
        return null;
      }

      final contextId = extractNumber(editResp.body, [
        RegExp(r"""["']?contextid["']?\s*[:=]\s*["']?(\d+)"""),
        RegExp(r"""["']?contextid["']?\s*,\s*["']?(\d+)"""),
        RegExp(r"""ctx_id["']?\s*[:=]\s*["']?(\d+)"""),
      ]);
      final maxbytes = extractNumber(editResp.body, [
        RegExp(r"""["']?maxbytes["']?\s*[:=]\s*["']?(-?\d+)"""),
      ]);
      final areamaxbytes = extractNumber(editResp.body, [
        RegExp(r"""["']?areamaxbytes["']?\s*[:=]\s*["']?(-?\d+)"""),
      ]);
      await Logger.instance.log(
        'UPLOAD: Upload context ctx_id=${contextId ?? "default"}, maxbytes=${maxbytes ?? "default"}',
      );

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

      if (itemid == null) {
        final itemidMatch = RegExp(r"""itemid["']?\s*[:=]\s*["']?(\d+)""").firstMatch(editResp.body);
        if (itemidMatch != null) {
          itemid = int.tryParse(itemidMatch.group(1)!);
          await Logger.instance.log('UPLOAD: Found itemid from regex: $itemid');
        }
      }

      if (itemid == null) {
        final inputMatch = RegExp(r'<input[^>]*name="itemid"[^>]*value="(\d+)"').firstMatch(editResp.body);
        if (inputMatch != null) {
          itemid = int.tryParse(inputMatch.group(1)!);
          await Logger.instance.log('UPLOAD: Found itemid from input: $itemid');
        }
      }

      if (itemid == null) {
        itemid = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await Logger.instance.log('UPLOAD: Using generated itemid: $itemid');
      }

      // Step 2: Discover upload repository ID
      await Logger.instance.log('UPLOAD: Discovering upload repository');

      // Priority-ordered list of repo IDs to try.
      final uploadRepoIds = <String>[];

      void tryAddRepoId(String? id) {
        final cleanId = id?.trim() ?? '';
        if (cleanId.isNotEmpty && !uploadRepoIds.contains(cleanId)) {
          uploadRepoIds.add(cleanId);
        }
      }

      // Strategy A (most reliable): parse JavaScript config — has explicit type field.
      await Logger.instance.log('UPLOAD: Strategy A: JS config');
      try {
        final initMatch = RegExp(
          r'M\.core_filepicker\.init\([^,]+,\s*(\{[\s\S]*?\})\s*\)',
        ).firstMatch(editResp.body);
        if (initMatch != null) {
          final config = jsonDecode(initMatch.group(1)!);
          final repos = config['repositories'] as List?;
          if (repos != null) {
            // First pass: collect upload repos; second pass: collect everything else.
            for (final r in repos) {
              if (r is Map && r['type'] == 'upload' && r['id'] != null) {
                tryAddRepoId(r['id'].toString());
                await Logger.instance.log('UPLOAD: JS config upload repo: id=${r['id']}');
              }
            }
            for (final r in repos) {
              if (r is Map && r['type'] != 'upload' && r['id'] != null) {
                tryAddRepoId(r['id'].toString());
                await Logger.instance.log('UPLOAD: JS config other repo: type=${r['type']}, id=${r['id']}');
              }
            }
          }
        }
      } catch (e) {
        await Logger.instance.log('UPLOAD: JS config parse failed: $e');
      }

      // Strategy B: call repositories API — also has explicit type.
      if (uploadRepoIds.isEmpty) {
        await Logger.instance.log('UPLOAD: Strategy B: repositories API');
        try {
          final repoListUrl = '$_baseUrl/repository/repository_ajax.php'
              '?action=repositories&sesskey=$sesskey&env=filemanager&itemid=$itemid'
              '${contextId != null ? '&ctx_id=$contextId' : ''}';
          final repoResp = await _get(client, repoListUrl);
          final repoData = jsonDecode(repoResp.body);

          final repos = repoData is List
              ? repoData
              : repoData is Map
                  ? (repoData['repositories'] as List? ?? repoData['list'] as List? ?? const [])
                  : const [];

          for (final repo in repos) {
            if (repo is Map && repo['type'] == 'upload' && repo['id'] != null) {
              tryAddRepoId(repo['id'].toString());
              await Logger.instance.log('UPLOAD: API upload repo: name=${repo['name']}, id=${repo['id']}');
            }
          }
          for (final repo in repos) {
            if (repo is Map && repo['type'] != 'upload' && repo['id'] != null) {
              tryAddRepoId(repo['id'].toString());
            }
          }
        } catch (e) {
          await Logger.instance.log('UPLOAD: Repo API failed: $e');
        }
      }

      // Strategy C: scan edit page HTML for repo IDs.
      await Logger.instance.log('UPLOAD: Strategy C: HTML scan');
      {
        final patterns = [
          RegExp(r'"id"\s*:\s*"?(\d+)"?'),
          RegExp(r"""data-repositoryid=["'](\d+)["']"""),
          RegExp(r"""repo_id["']?\s*[:=]\s*["']?(\d+)"""),
          RegExp(r"""[?&]repo_id=(\d+)"""),
        ];
        for (final pattern in patterns) {
          for (final match in pattern.allMatches(editResp.body)) {
            tryAddRepoId(match.group(1));
          }
        }
      }

      // Strategy D: try the filepicker HTML too.
      await Logger.instance.log('UPLOAD: Strategy D: filepicker HTML');
      try {
        final fpUrl = '$_baseUrl/repository/repository_ajax.php'
            '?action=filepicker&sesskey=$sesskey&env=filemanager&itemid=$itemid'
            '${contextId != null ? '&ctx_id=$contextId' : ''}';
        final fpResp = await _get(client, fpUrl);
        final fpPatterns = [
          RegExp(r'"id"\s*:\s*"?(\d+)"?'),
          RegExp(r"""data-repositoryid=["'](\d+)["']"""),
        ];
        for (final pattern in fpPatterns) {
          for (final match in pattern.allMatches(fpResp.body)) {
            tryAddRepoId(match.group(1));
          }
        }
      } catch (e) {
        await Logger.instance.log('UPLOAD: Filepicker fetch failed: $e');
      }

      // Strategy E: fallback common IDs.
      for (var id = 0; id <= 7; id++) {
        tryAddRepoId(id.toString());
      }

      await Logger.instance.log('UPLOAD: Repo IDs to try: $uploadRepoIds');

      if (uploadRepoIds.isEmpty) {
        await Logger.instance.log('UPLOAD: No repository ID found');
        return {
          'success': false,
          'open_in_browser': true,
          'url': taskUrl,
          'message': 'Could not find Moodle\'s upload repository for this assignment. Please upload in your browser.',
        };
      }

      // Step 3: Upload file to Moodle draft area (repository)
      await Logger.instance.log('UPLOAD: Uploading file to draft area');

      final uploadUrl = '$_baseUrl/repository/repository_ajax.php';
      final originalFilename = path.basename(filePath);

      int? asInt(dynamic value) {
        if (value is int) return value;
        if (value == null) return null;
        return int.tryParse(value.toString());
      }

      String? asNonEmptyString(dynamic value) {
        final text = value?.toString();
        if (text == null || text.isEmpty) return null;
        return text;
      }

      bool isFileExistsEvent(dynamic data) {
        final payload = data is List && data.isNotEmpty ? data.first : data;
        return payload is Map && payload['event'] == 'fileexists';
      }

      Map<String, dynamic>? parseUploadSuccess(dynamic data) {
        final payload = data is List && data.isNotEmpty ? data.first : data;
        if (payload is! Map) return null;

        if (payload['event'] == 'fileexists') return null;

        final itemIdFromResponse = asInt(payload['itemid'] ?? payload['id']);
        final filenameFromResponse = asNonEmptyString(payload['filename'] ?? payload['file']);
        if (itemIdFromResponse != null || filenameFromResponse != null || payload['url'] != null) {
          return {
            'itemid': itemIdFromResponse ?? itemid,
            'filename': filenameFromResponse ?? originalFilename,
          };
        }

        return null;
      }

      String parseUploadError(String body) {
        try {
          final data = jsonDecode(body);
          if (data is Map) {
            final error = data['error'] ?? data['errorcode'] ?? data['message'];
            if (error != null) return error.toString();
          }
        } catch (_) {}
        return body.substring(0, body.length.clamp(0, 200));
      }

      Future<Map<String, dynamic>> tryUpload(String rid) async {
        final file = await http.MultipartFile.fromPath('repo_upload_file', filePath);
        final uploadRequest = http.MultipartRequest('POST', Uri.parse(uploadUrl))
          ..headers.addAll({..._headers(), 'Accept': 'application/json, text/plain, */*'})
          ..fields['action'] = 'upload'
          ..fields['sesskey'] = sesskey
          ..fields['repo_id'] = rid
          ..fields['env'] = 'filemanager'
          ..fields['itemid'] = itemid.toString()
          ..fields['title'] = originalFilename
          ..fields['savepath'] = '/'
          ..fields['author'] = username
          ..fields['overwrite'] = 'true'
          ..files.add(file);

        if (contextId != null) uploadRequest.fields['ctx_id'] = contextId;
        if (maxbytes != null) uploadRequest.fields['maxbytes'] = maxbytes;
        if (areamaxbytes != null) uploadRequest.fields['areamaxbytes'] = areamaxbytes;

        await Logger.instance.log('UPLOAD: Trying repo_id=$rid');
        final stream = await client.send(uploadRequest).timeout(const Duration(seconds: 60));
        final resp = await http.Response.fromStream(stream);
        _parseCookies(resp);
        final body = resp.body;

        await Logger.instance.log('UPLOAD: response status=${resp.statusCode}, length=${body.length}');

        try {
          final data = jsonDecode(body);
          final success = parseUploadSuccess(data);
          if (success != null) return success;

          if (data is Map && data['error'] != null) {
            await Logger.instance.log('UPLOAD: Moodle error for repo_id=$rid: ${data['error']}');
            return {'error': data['error'].toString()};
          }

          if (isFileExistsEvent(data)) {
            await Logger.instance.log('UPLOAD: File exists event for repo_id=$rid - file may need different name');
            return {'error': 'A file with this name already exists. Try renaming the file or upload via browser.'};
          }
        } catch (_) {}

        // Check for errors in response
        if (body.contains('error') || body.contains('Error') || body.contains('not logged in') || body.contains('invalid')) {
          await Logger.instance.log('UPLOAD: Error in response for repo_id=$rid');
          return {'error': parseUploadError(body)};
        }

        if (resp.statusCode != 200) {
          return {'error': 'HTTP ${resp.statusCode}'};
        }

        return {};
      }

      int? uploadedItemid;
      String? uploadedFilename;
      String lastError = '';
      String usedRepoId = '';

      for (final rid in uploadRepoIds) {
        final result = await tryUpload(rid);
        uploadedItemid = result['itemid'] as int?;
        uploadedFilename = result['filename'] as String?;
        final error = result['error'] as String?;
        if (error != null && error.isNotEmpty) lastError = error;
        if (uploadedItemid != null || uploadedFilename != null) {
          usedRepoId = rid;
          await Logger.instance.log('UPLOAD: Success with repo_id=$rid');
          break;
        }
        await Logger.instance.log('UPLOAD: Failed repo_id=$rid');
      }

      if (uploadedItemid == null && uploadedFilename == null) {
        await Logger.instance.log('UPLOAD: All repo_ids failed. Last error: $lastError');
        return {
          'success': false,
          'open_in_browser': true,
          'url': taskUrl,
          'message': 'File upload to draft area failed${lastError.isNotEmpty ? ': $lastError' : ''}. Please try in your browser.',
          'debug': lastError,
        };
      }

      final finalItemid = uploadedItemid ?? itemid;
      await Logger.instance.log('UPLOAD: Using final itemid: $finalItemid, repo_id=$usedRepoId');

      // Step 3: Submit the assignment with the uploaded file reference
      await Logger.instance.log('UPLOAD: Submitting assignment with savesubmission');

      // Extract ALL form fields from the edit submission form.
      // This includes plugin-specific fields like assignsubmission_file_filemanager.
      Map<String, String> formFields = {};
      String? formActionUrl;

      String submitButtonValue = 'Save changes';
      final submitBtnEl = editDoc.querySelector('input[type="submit"][name="submitbutton"]');
      if (submitBtnEl != null) {
        final val = submitBtnEl.attributes['value'];
        if (val != null && val.isNotEmpty) submitButtonValue = val;
      }

      {
        // Try multiple selectors to find the submission form (ID varies by Moodle version)
        var form = editDoc.querySelector('form#mod_assign_submission_form');
        if (form == null) form = editDoc.querySelector('form.mform');
        if (form == null) form = editDoc.querySelector('form[action*="view.php"]');
        if (form != null) {
          final action = form.attributes['action'] ?? '';
          if (action.isNotEmpty) {
            // Resolve relative action URL properly against the edit page URL
            formActionUrl = Uri.parse(editUrl).resolve(action).toString();
          }
          await Logger.instance.log('UPLOAD: Found form, action=$action, resolved=$formActionUrl');

          // First pass: collect checkbox names so we can skip their hidden value=0 companions
          final checkboxNames = <String>{};
          for (final cb in form.querySelectorAll('input[type="checkbox"], input[type="radio"]')) {
            final n = cb.attributes['name'];
            if (n != null && n.isNotEmpty) checkboxNames.add(n);
          }

          // Second pass: extract all relevant fields
          final inputs = form.querySelectorAll('input, textarea, select');
          for (final input in inputs) {
            final tag = input.localName;
            final type = input.attributes['type'] ?? '';
            final name = input.attributes['name'];
            if (name == null || name.isEmpty) continue;

            if (tag == 'input') {
              if (type == 'hidden') {
                // Skip hidden inputs that accompany checkboxes (value=0 companions)
                if (checkboxNames.contains(name)) continue;
                formFields[name] = input.attributes['value'] ?? '';
              } else if (type == 'checkbox' || type == 'radio') {
                if (input.attributes.containsKey('checked') ||
                    name == 'submissionstatement' ||
                    name == 'submitforgrading') {
                  formFields[name] = input.attributes['value'] ?? '1';
                }
              } else if (type == 'submit' || type == 'button') {
                formFields[name] = input.attributes['value'] ?? submitButtonValue;
              } else {
                formFields[name] = input.attributes['value'] ?? '';
              }
            } else if (tag == 'textarea') {
              continue;
            } else if (tag == 'select') {
              final selectedOption = input.querySelector('option[selected]');
              if (selectedOption != null) {
                formFields[name] = selectedOption.attributes['value'] ?? '';
              }
            }
          }
        } else {
          await Logger.instance.log('UPLOAD: WARNING - Could not find mod_assign_submission_form');
        }
      }

      // Override the file manager field value with our uploaded draft itemid
      String? foundFmField;
      for (final key in formFields.keys) {
        if (key.endsWith('filemanager')) {
          formFields[key] = finalItemid.toString();
          foundFmField = key;
          await Logger.instance.log('UPLOAD: Set $key = $finalItemid');
        }
      }

      // Ensure sesskey and qf marker are present
      if (!formFields.containsKey('sesskey')) {
        formFields['sesskey'] = sesskey;
      }
      if (!formFields.containsKey('_qf__mod_assign_submission_form')) {
        formFields['_qf__mod_assign_submission_form'] = '1';
      }

      // If no filemanager field found, try the known pattern
      if (foundFmField == null) {
        final anyFm = editDoc.querySelector('input[type="hidden"][name\$="filemanager"]');
        if (anyFm != null) {
          final name = anyFm.attributes['name'];
          if (name != null && name.isNotEmpty && name != 'itemid') {
            formFields[name] = finalItemid.toString();
            await Logger.instance.log('UPLOAD: Fallback set $name = $finalItemid');
          }
        }
      }

      await Logger.instance.log('UPLOAD: Form fields: ${formFields.keys.join(', ')}');

      // Determine the submission URL
      final submitUrl = formActionUrl ??
          '$_baseUrl/mod/assign/view.php?id=$cmid&action=savesubmission';

      // Build headers with Referer for CSRF compatibility
      Map<String, String> submitHeaders = _headers();
      submitHeaders['Referer'] = editUrl;

      Future<String?> doSaveSubmission(Map<String, String> fields) async {
        await Logger.instance.log('UPLOAD: POST savesubmission with fields: ${fields.keys.join(", ")}');
        final resp = await client.post(
          Uri.parse(submitUrl),
          headers: submitHeaders,
          body: fields,
        ).timeout(_requestTimeout);

        await Logger.instance.log('UPLOAD: Savesubmission response status: ${resp.statusCode}');
        await Logger.instance.log('UPLOAD: Savesubmission response length: ${resp.body.length}');

        final body = resp.body;

        if (body.contains('Your submission has been saved') ||
            body.contains('Su entrega ha sido guardada') ||
            body.contains('Tu entrega ha sido guardada') ||
            body.contains('Su env') ||
            body.contains('Tu env') ||
            body.contains('class="notifysuccess"') ||
            body.contains('alert-success') ||
            body.contains('submissionstatussubmitted') ||
            body.contains('Enviado para calificar') ||
            body.contains('Submitted for grading')) {
          return null;
        }

        if (body.contains('action=editsubmission')) {
          _saveDebugResponse(body, 'savesubmission_editform');
          return 'Submission form was rejected by Moodle. Please try in your browser.';
        }

        if (body.contains('class="notifyproblem"') ||
            body.contains('class="alert alert-danger"') ||
            body.contains('class="error"')) {
          _saveDebugResponse(body, 'savesubmission_error');
          return 'Moodle rejected the submission. Please try in your browser.';
        }

        return null;
      }

      // Try submission: first include submissionstatement if the form wants it
      String? submitError;

      // If the form HTML already contains submissionstatement field, include it from start
      bool formHasSubmissionStatement = formFields.containsKey('submissionstatement');
      bool formHasSubmitForGrading = formFields.containsKey('submitforgrading');
      bool bodyHasSubmissionStatement = editResp.body.contains('name="submissionstatement"');
      bool bodyHasSubmitForGrading = editResp.body.contains('name="submitforgrading"');

      if (formHasSubmissionStatement || bodyHasSubmissionStatement) {
        formFields['submissionstatement'] = '1';
      }
      if (formHasSubmitForGrading || bodyHasSubmitForGrading) {
        formFields['submitforgrading'] = '1';
      }

      submitError = await doSaveSubmission(formFields);

      // Second attempt: if failed, try without submissionstatement (edge case)
      if (submitError != null && formFields.containsKey('submissionstatement')) {
        await Logger.instance.log('UPLOAD: Retrying without submissionstatement');
        final retryFields = Map<String, String>.from(formFields);
        retryFields.remove('submissionstatement');
        submitError = await doSaveSubmission(retryFields);
      }

      if (submitError != null) {
        await Logger.instance.log('UPLOAD: savesubmission failed: $submitError');
        return {
          'success': false,
          'open_in_browser': true,
          'url': taskUrl,
          'message': submitError,
        };
      }

      // Step 4: Verify submission by checking the assignment page
      await Future.delayed(const Duration(milliseconds: 500));
      await Logger.instance.log('UPLOAD: Verifying submission');
      final verifyResp = await _get(client, '$_baseUrl/mod/assign/view.php?id=$cmid');
      final verifyDoc = html_parser.parse(verifyResp.body);

      // Check for "Your submission has been saved" confirmation
      final submissionSaved = verifyResp.body.contains('Your submission has been saved') ||
          verifyResp.body.contains('Su entrega ha sido guardada') ||
          verifyResp.body.contains('class="notifysuccess"');

      // Check for submission status indicators
      bool hasSubmission = false;
      String? submissionStatus;
      String? submittedFileName;
      final List<Map<String, dynamic>> submissionFilesWithUrls = [];

      final statusEl = verifyDoc.querySelector('[class*="submissionstatustext"], [class*="submissionstatus"], [class*="submission_status"], [data-region*="submission"] > .status');
      if (statusEl != null) {
        final statusText = statusEl.text.trim().toLowerCase();
        if (statusText.contains('submitted') || statusText.contains('entregado') || statusText.contains('graded') || statusText.contains('calificado')) {
          hasSubmission = true;
          submissionStatus = statusEl.text.trim();
        }
      }

      // Find submitted files: scan submission regions only, no fallback
      final uploadSeenUrls = <String>{};

      // Helper: check if link is inside an intro/description container
      bool isInIntroArea(dynamic link) {
        var parent = link.parent;
        while (parent != null) {
          final classAttr = parent.attributes['class'] ?? '';
          if (parent.id == 'intro' ||
              parent.attributes['data-region'] == 'activity-info' ||
              parent.attributes['data-region'] == 'activity-header' ||
              classAttr.contains('no-overflow') ||
              classAttr.contains('activity-description')) {
            return true;
          }
          parent = parent.parent;
        }
        return false;
      }

      final uploadSubmissionSelectors = [
        '[data-region="submission-content"]',
        '[data-region="submission-received"]',
        '[data-region="submissions"]',
        '.submissionplugins',
        '.fileuploadsubmission',
      ];
      for (final sel in uploadSubmissionSelectors) {
        final elements = verifyDoc.querySelectorAll(sel);
        for (final el in elements) {
          final links = el.querySelectorAll('a[href*="pluginfile.php"], a[href*="draftfile.php"], a[href*="tokenpluginfile.php"]');
          for (final link in links) {
            final href = link.attributes['href'];
            if (href == null) continue;

            if (isInIntroArea(link)) continue;

            String filename = link.text.trim().replaceAll(RegExp(r'\s+'), ' ');
            if (filename.isEmpty || filename == 'Download' || filename == 'download') {
              final parent = link.parent;
              if (parent != null) {
                final siblingText = parent.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                if (siblingText.length > 1 && siblingText.length < 200) filename = siblingText;
              }
            }
            if (filename.isEmpty || filename.length > 200) {
              filename = Uri.decodeComponent(href.split('/').lastWhere((s) => s.contains('.'), orElse: () => href.split('/').last));
            }
            final resolved = _resolveUrl(href);
            if (resolved.isNotEmpty && uploadSeenUrls.add(resolved)) {
              hasSubmission = true;
              if (submittedFileName == null) submittedFileName = filename.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
              submissionFilesWithUrls.add({
                'filename': filename.replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
                'url': resolved,
                'size': await File(filePath).length(),
                'uploaded_at': DateTime.now().toIso8601String(),
                'itemid': finalItemid,
              });
            }
          }
        }
      }

      await Logger.instance.log('UPLOAD: Verification result - hasSubmission: $hasSubmission, status: $submissionStatus, files: ${submissionFilesWithUrls.length}, submissionSaved: $submissionSaved');

      // Update local DB with submission info
      final db = await DatabaseService.instance.database;
      List<Map<String, dynamic>> existing;
      if (taskId != null) {
        existing = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      } else {
        existing = await db.query('tasks', where: 'url = ?', whereArgs: [taskUrl]);
      }
      if (existing.isNotEmpty) {
        final matchId = existing.first['id'] as int;
        final submissionFiles = submissionFilesWithUrls.isNotEmpty
            ? submissionFilesWithUrls
            : [
                {
                  'filename': uploadedFilename ?? submittedFileName ?? originalFilename,
                  'url': null,
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
          where: 'id = ?', whereArgs: [matchId],
        );
      }

      final uploadedFileUrl = submissionFilesWithUrls.isNotEmpty
          ? submissionFilesWithUrls.first['url'] as String?
          : null;

      return {
        'success': true, 
        'message': hasSubmission ? 'File uploaded and submission saved' : 'File uploaded (submission may need verification)',
        'filename': uploadedFilename ?? originalFilename,
        'file_url': uploadedFileUrl,
        'verified': hasSubmission,
      };
    } catch (e) {
      await Logger.instance.log('UPLOAD: Exception: $e');
      return {'success': false, 'open_in_browser': true, 'url': taskUrl, 'message': 'Upload failed: $e'};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> removeSubmission(
    String moodleUrl,
    String username,
    String password,
    String taskUrl, {
    int? taskId,
    String? sessionCookie,
  }) async {
    final client = _createClient();
    try {
      await Logger.instance.log('REMOVE_SUB: Starting remove submission for $taskUrl');

      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        try {
          await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
        } catch (_) {
          await Logger.instance.log('REMOVE_SUB: Saved session expired, logging in fresh');
          _cookies.clear();
          await _login(moodleUrl, username, password);
        }
      } else {
        await _login(moodleUrl, username, password);
      }

      final uri = Uri.parse(taskUrl);
      final cmid = uri.queryParameters['id'];
      if (cmid == null) {
        return {'success': false, 'message': 'Invalid task URL.'};
      }

      // Step 1: Get the assignment page to find sesskey and removal elements
      final assignResp = await _get(client, '$_baseUrl/mod/assign/view.php?id=$cmid');
      final assignDoc = html_parser.parse(assignResp.body);
      final sesskey = _extractSesskey(assignResp.body);
      if (sesskey == null) {
        return {'success': false, 'message': 'Could not find session key.'};
      }

      // Step 2: Find the "Remove submission" link/button/form on the assignment page
      String? removeLinkUrl;
      bool remoteSuccess = false;

      // Strategy A: Find any element (a, button, input) linking to removesubmission
      {
        // Look for any element with an href or action pointing to removesubmission
        for (final el in assignDoc.querySelectorAll('a[href*="removesubmission"], a[href*="remove_submission"], form[action*="removesubmission"]')) {
          final href = el.attributes['href'] ?? el.attributes['action'] ?? '';
          if (href.contains('removesubmission')) {
            removeLinkUrl = href;
            break;
          }
        }
        if (removeLinkUrl == null) {
          // Try finding by text content
          for (final el in assignDoc.querySelectorAll('a, button, input[type="submit"], input[type="button"], span[role="button"]')) {
            final text = el.text.trim().toLowerCase();
            final type = (el.attributes['type'] ?? '').toLowerCase();
            final name = (el.attributes['name'] ?? '').toLowerCase();
            if (text.contains('remove') || text.contains('eliminar') || text.contains('delete') ||
                name.contains('remove') || name.contains('eliminar') || name.contains('delete')) {
              final href = el.attributes['href'] ?? el.attributes['formaction'] ?? '';
              if (href.contains('removesubmission')) {
                removeLinkUrl = href;
                break;
              }
              // If it's an input button, look for a surrounding form
              if (type == 'submit' || type == 'button') {
                // Walk up to find the form
                var parent = el.parent;
                while (parent != null) {
                  if (parent.localName == 'form') {
                    final action = parent.attributes['action'] ?? '';
                    if (action.contains('removesubmission')) {
                      removeLinkUrl = action;
                      break;
                    }
                  }
                  parent = parent.parent;
                }
                if (removeLinkUrl != null) break;
              }
            }
          }
        }
      }

      await Logger.instance.log('REMOVE_SUB: Found removal link: $removeLinkUrl');

      // Strategy B: Follow the found link to get the confirmation page
      if (removeLinkUrl != null && removeLinkUrl.isNotEmpty && !remoteSuccess) {
        try {
          final resolvedUrl = Uri.parse('$_baseUrl/mod/assign/view.php?id=$cmid').resolve(removeLinkUrl).toString();
          await Logger.instance.log('REMOVE_SUB: Following: $resolvedUrl');
          final confirmResp = await _get(client, resolvedUrl);
          final confirmBody = confirmResp.body;

          // Check if the removal succeeded directly (no confirmation needed)
          if (confirmBody.contains('Your submission has been removed') ||
              confirmBody.contains('Su entrega ha sido eliminada') ||
              confirmBody.contains('Tu entrega ha sido eliminada') ||
              confirmBody.contains('class="notifysuccess"') ||
              confirmBody.contains('alert-success')) {
            remoteSuccess = true;
          }

          // Check for a confirmation form
          if (!remoteSuccess) {
            final confirmDoc = html_parser.parse(confirmBody);
            // Look for any "Yes" / "Confirm" form or button
            final confirmForm = confirmDoc.querySelector(
              'form[action*="removesubmission"]',
            );
            if (confirmForm != null) {
              final formAction = confirmForm.attributes['action'] ?? '';
              final actionUrl = Uri.parse(resolvedUrl).resolve(formAction).toString();
              final formData = <String, String>{
                'id': cmid,
                'action': 'removesubmission',
                'sesskey': sesskey,
                'confirm': '1',
              };
              // Extract any extra hidden fields from the confirmation form
              for (final input in confirmForm.querySelectorAll('input[type="hidden"]')) {
                final name = input.attributes['name'];
                final val = input.attributes['value'] ?? '';
                if (name != null && name.isNotEmpty) formData[name] = val;
              }
              await Logger.instance.log('REMOVE_SUB: Submitting confirmation: $actionUrl');
              final postResp = await client.post(
                Uri.parse(actionUrl),
                headers: {..._headers(), 'Referer': resolvedUrl},
                body: formData,
              ).timeout(_requestTimeout);
              final postBody = postResp.body;
              remoteSuccess = postBody.contains('Your submission has been removed') ||
                  postBody.contains('Su entrega ha sido eliminada') ||
                  postBody.contains('Tu entrega ha sido eliminada') ||
                  postBody.contains('class="notifysuccess"') ||
                  postBody.contains('alert-success');
            }
          }
        } catch (e) {
          await Logger.instance.log('REMOVE_SUB: Follow link failed: $e');
        }
      }

      // Strategy C: Direct GET with confirm=1 (standard Moodle removal)
      if (!remoteSuccess) {
        await Logger.instance.log('REMOVE_SUB: Direct GET removesubmission');
        try {
          final getResp = await _get(client,
            '$_baseUrl/mod/assign/view.php?id=$cmid&action=removesubmission&sesskey=$sesskey&confirm=1',
          );
          final body = getResp.body;
          remoteSuccess = body.contains('Your submission has been removed') ||
              body.contains('Su entrega ha sido eliminada') ||
              body.contains('Tu entrega ha sido eliminada') ||
              body.contains('class="notifysuccess"') ||
              body.contains('alert-success');
        } catch (e) {
          await Logger.instance.log('REMOVE_SUB: Direct GET failed: $e');
        }
      }

      // Strategy D: Direct POST with confirm=1
      if (!remoteSuccess) {
        await Logger.instance.log('REMOVE_SUB: Direct POST removesubmission');
        try {
          final postResp = await client.post(
            Uri.parse('$_baseUrl/mod/assign/view.php'),
            headers: {..._headers(), 'Referer': '$_baseUrl/mod/assign/view.php?id=$cmid'},
            body: {
              'id': cmid,
              'action': 'removesubmission',
              'sesskey': sesskey,
              'confirm': '1',
            },
          ).timeout(_requestTimeout);
          final body = postResp.body;
          remoteSuccess = body.contains('Your submission has been removed') ||
              body.contains('Su entrega ha sido eliminada') ||
              body.contains('Tu entrega ha sido eliminada') ||
              body.contains('class="notifysuccess"') ||
              body.contains('alert-success');
        } catch (e) {
          await Logger.instance.log('REMOVE_SUB: Direct POST failed: $e');
        }
      }

      // Strategy E: Re-fetch assignment page to verify submission is gone
      if (!remoteSuccess) {
        await Logger.instance.log('REMOVE_SUB: Verifying by re-fetching assignment page');
        try {
          await Future.delayed(const Duration(milliseconds: 500));
          final verifyResp = await _get(client, '$_baseUrl/mod/assign/view.php?id=$cmid');
          final verifyBody = verifyResp.body;

          // If there's a success notification on the page, submission was removed
          if (verifyBody.contains('Your submission has been removed') ||
              verifyBody.contains('Su entrega ha sido eliminada') ||
              verifyBody.contains('Tu entrega ha sido eliminada') ||
              verifyBody.contains('class="notifysuccess"') ||
              verifyBody.contains('alert-success')) {
            remoteSuccess = true;
          } else {
            // Check if there's no longer a submitted file on the page
            // Look for the "Add submission" button (means submission was cleared)
            final verifyDoc = html_parser.parse(verifyBody);
            final addSubmissionLinks = verifyDoc.querySelectorAll(
              'a[href*="editsubmission"], a[href*="addsubmission"]',
            );
            bool canAddSubmission = false;
            for (final link in addSubmissionLinks) {
              final text = link.text.trim().toLowerCase();
              if (text.contains('add') || text.contains('edit') || text.contains('agregar') || text.contains('editar') || text.contains('añadir')) {
                canAddSubmission = true;
                break;
              }
            }
            // Also check files from submission area
            final fileLinks = verifyDoc.querySelectorAll(
              '[data-region="submission-content"] a[href*="pluginfile.php"], '
              '[data-region="submission-received"] a[href*="pluginfile.php"]',
            );
            if (canAddSubmission && fileLinks.isEmpty) {
              remoteSuccess = true;
              await Logger.instance.log('REMOVE_SUB: Verified - no files found and add link present');
            }
          }
        } catch (e) {
          await Logger.instance.log('REMOVE_SUB: Verification fetch failed: $e');
        }
      }

      // Step 5: Clear local DB if remote removal succeeded
      if (remoteSuccess) {
        final db = await DatabaseService.instance.database;
        List<Map<String, dynamic>> existing;
        if (taskId != null) {
          existing = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
        } else {
          existing = await db.query('tasks', where: 'url = ?', whereArgs: [taskUrl]);
        }
        if (existing.isNotEmpty) {
          final matchId = existing.first['id'] as int;
          await db.update('tasks', {
            'file_uploaded': 0,
            'is_submitted': 0,
            'submission_files': '[]',
            'submission_status': null,
            'last_submission_check': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [matchId]);
        }
      }

      await Logger.instance.log('REMOVE_SUB: Success=$remoteSuccess');
      return {
        'success': remoteSuccess,
        'message': remoteSuccess
            ? 'Submission removed successfully.'
            : 'Could not remove submission on Moodle. It may already be graded. Please try in your browser.',
      };
    } catch (e) {
      await Logger.instance.log('REMOVE_SUB: Exception: $e');
      try {
        final db = await DatabaseService.instance.database;
        List<Map<String, dynamic>> existing;
        if (taskId != null) {
          existing = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
        } else {
          existing = await db.query('tasks', where: 'url = ?', whereArgs: [taskUrl]);
        }
        if (existing.isNotEmpty) {
          final matchId = existing.first['id'] as int;
          await db.update('tasks', {
            'file_uploaded': 0,
            'is_submitted': 0,
            'submission_files': '[]',
            'submission_status': null,
            'last_submission_check': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [matchId]);
        }
      } catch (_) {}
      return {'success': false, 'message': 'Failed to remove submission: $e'};
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
    int? taskId,
    String? sessionCookie,
  }) async {
    final client = _createClient();
    try {
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        try {
          await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
        } catch (_) {
          _cookies.clear();
          await _login(moodleUrl, username, password);
        }
      } else {
        await _login(moodleUrl, username, password);
      }

      final uri = Uri.parse(taskUrl);
      final cmid = uri.queryParameters['id'];
      if (cmid == null) {
        return {'success': false, 'message': 'Invalid task URL.'};
      }

      final assignResp = await _get(client, '$_baseUrl/mod/assign/view.php?id=$cmid');
      final assignDoc = html_parser.parse(assignResp.body);

      bool hasSubmission = false;
      String? submissionStatus;
      List<Map<String, dynamic>> submissionFiles = [];
      String? quizGrade;
      String? quizFeedback;

      // --- Q) Quiz-specific check ---
      if (taskUrl.contains('/mod/quiz/')) {
        try {
          final gradeEl = assignDoc.querySelector('.graded, .quizgraded, .grade');
          if (gradeEl != null) {
            final g = gradeEl.text.trim();
            if (g.contains('/')) {
              quizGrade = g;
              quizFeedback = g;
            }
          }
        } catch (_) {}
      }

      // --- 1) Detect submission status from status text elements ---
      final statusEl = assignDoc.querySelector('[class*="submissionstatustext"], [class*="submissionstatus"], [class*="submission_status"], [data-region*="submission-status"]');
      if (statusEl != null) {
        final st = statusEl.text.trim().toLowerCase();
        if (st.contains('submitted') || st.contains('entregado') || st.contains('graded') || st.contains('calificado') || st.contains('for grading')) {
          hasSubmission = true;
          submissionStatus = statusEl.text.trim();
        }
      }

      // --- 2) Check for "Edit submission" button (proves there IS a submission) ---
      final editBtns = assignDoc.querySelectorAll('input[value="Edit submission"], a[href*="action=editsubmission"]');
      for (final btn in editBtns) {
        final btnText = btn.text.trim().toLowerCase();
        final btnVal = btn.attributes['value']?.toLowerCase() ?? '';
        if (btnText.contains('edit submission') || btnVal.contains('edit submission')) {
          hasSubmission = true;
          if (submissionStatus == null) submissionStatus = 'Submitted';
          break;
        }
      }

      // --- 3) Find submission files ONLY within submission-specific HTML regions ---
      final seenUrls = <String>{};

      // Helper: check if link is inside an intro/description container
      bool isInIntroArea(dynamic link) {
        var parent = link.parent;
        while (parent != null) {
          final classAttr = parent.attributes['class'] ?? '';
          if (parent.id == 'intro' ||
              parent.attributes['data-region'] == 'activity-info' ||
              parent.attributes['data-region'] == 'activity-header' ||
              classAttr.contains('no-overflow') ||
              classAttr.contains('activity-description')) {
            return true;
          }
          parent = parent.parent;
        }
        return false;
      }

      // Scan pluginfile links only inside known submission containers
      final submissionRegionSelectors = [
        '[data-region="submission-content"]',
        '[data-region="submission-received"]',
        '[data-region="submissions"]',
        '.submissionplugins',
        '.fileuploadsubmission',
      ];
      for (final sel in submissionRegionSelectors) {
        final elements = assignDoc.querySelectorAll(sel);
        for (final el in elements) {
          final links = el.querySelectorAll('a[href*="pluginfile.php"], a[href*="draftfile.php"], a[href*="tokenpluginfile.php"]');
          for (final link in links) {
            final href = link.attributes['href'];
            if (href == null) continue;

            // Double-check link is not in intro area (defensive)
            if (isInIntroArea(link)) continue;

            String filename = link.text.trim().replaceAll(RegExp(r'\s+'), ' ');

            if (filename.isEmpty || filename == 'Download' || filename == 'download') {
              final parent = link.parent;
              if (parent != null) {
                final siblingText = parent.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                if (siblingText.length > 1 && siblingText.length < 200) {
                  filename = siblingText;
                }
              }
            }

            if (filename.isEmpty || filename.length > 200) {
              final segments = href.split('/');
              filename = Uri.decodeComponent(segments.lastWhere((s) => s.contains('.'), orElse: () => segments.last));
            }

            final resolved = _resolveUrl(href);
            if (resolved.isNotEmpty && seenUrls.add(resolved)) {
              hasSubmission = true;
              submissionFiles.add({
                'filename': filename.replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
                'url': resolved,
                'checked_at': DateTime.now().toIso8601String(),
              });
            }
          }
        }
      }

      // --- 4) Check for actual online text submission (NOT homework description) ---
      bool hasOnlineText = false;
      String? onlineTextContent;
      // Only check elements that are specifically the text submission, not generic page content
      for (final sel in ['.online_text', '.onlinetext', '.submission_onlinetext', '[data-region*="submission-content"] .no-overflow']) {
        final el = assignDoc.querySelector(sel);
        if (el != null) {
          final text = el.text.trim();
          // Online text submissions are typically longer than 50 chars
          // and are found within the submission area, not the description area
          if (text.isNotEmpty && text.length > 50 && !text.startsWith('Description')) {
            hasOnlineText = true;
            onlineTextContent = text;
            break;
          }
        }
      }
      if (hasOnlineText && submissionFiles.isEmpty) {
        hasSubmission = true;
        submissionFiles.add({
          'filename': 'online_text_submission',
          'type': 'online_text',
          'preview': onlineTextContent!.substring(0, onlineTextContent.length.clamp(0, 200)),
          'checked_at': DateTime.now().toIso8601String(),
        });
      }

      // Update / clear local DB using taskId (preferred) or URL (fallback)
      final db = await DatabaseService.instance.database;
      List<Map<String, dynamic>> existing;
      if (taskId != null) {
        existing = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
      } else {
        existing = await db.query('tasks', where: 'url = ?', whereArgs: [taskUrl]);
      }
      if (existing.isNotEmpty) {
        final matchId = existing.first['id'] as int;
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
        } else {
          updates['file_uploaded'] = 0;
          updates['is_submitted'] = 0;
          updates['submission_files'] = '[]';
          updates['submission_status'] = null;
        }

        if (quizGrade != null) updates['quiz_grade'] = quizGrade;
        if (quizFeedback != null) updates['quiz_feedback'] = quizFeedback;

        await db.update('tasks', updates, where: 'id = ?', whereArgs: [matchId]);
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

  /// Scrapes course content from Moodle to find books, PDFs, videos, and other resources
  Future<List<Map<String, dynamic>>> scrapeCourseContent({
    required String moodleUrl,
    required String username,
    required String password,
    String? sessionCookie,
    required String courseName,
  }) async {
    final client = _createClient();
    final resources = <Map<String, dynamic>>[];
    
    try {
      await Logger.instance.log('COURSE_CONTENT: Starting scrape for course: $courseName');
      
      if (sessionCookie != null && sessionCookie.isNotEmpty) {
        try {
          await _loginWithSessionCookie(client, moodleUrl, sessionCookie);
        } catch (_) {
          await Logger.instance.log('COURSE_CONTENT: Saved session expired, logging in fresh');
          _cookies.clear();
          await _login(moodleUrl, username, password);
        }
      } else {
        await _login(moodleUrl, username, password);
      }

      // Navigate to course page
      final courseUrl = '$_baseUrl/course/view.php?name=${Uri.encodeComponent(courseName)}';
      await Logger.instance.log('COURSE_CONTENT: Fetching course page: $courseUrl');
      
      final courseResp = await _get(client, courseUrl);
      final courseDoc = html_parser.parse(courseResp.body);

      // Find all activity/resource links
      final activityLinks = courseDoc.querySelectorAll('.activity, .resource, .modtype_label, [class*="activity"]');
      await Logger.instance.log('COURSE_CONTENT: Found ${activityLinks.length} activities/resources');

      for (final activity in activityLinks) {
        try {
          final link = activity.querySelector('a[href]');
          if (link == null) continue;

          final href = link.attributes['href'] ?? '';
          final text = link.text.trim();
          final activityType = _detectResourceType(href, text, activity);

          if (href.isEmpty || text.isEmpty) continue;

          // Determine resource type and extract relevant info
          Map<String, dynamic>? resource;
          
          if (activityType == 'pdf') {
            resource = {
              'type': 'pdf',
              'title': text,
              'url': _resolveUrl(href),
              'source': 'Moodle Course',
            };
          } else if (activityType == 'video') {
            resource = {
              'type': 'video',
              'title': text,
              'url': _resolveUrl(href),
              'channel': 'Moodle Course',
              'description': 'Course video resource',
            };
          } else if (activityType == 'book') {
            resource = {
              'type': 'book',
              'title': text,
              'url': _resolveUrl(href),
              'source': 'Moodle Course',
            };
          } else if (activityType == 'link') {
            resource = {
              'type': 'link',
              'title': text,
              'url': _resolveUrl(href),
              'source': 'Moodle Course',
            };
          }

          if (resource != null) {
            resources.add(resource);
            await Logger.instance.log('COURSE_CONTENT: Found ${resource['type']}: ${resource['title']}');
          }
        } catch (e) {
          await Logger.instance.log('COURSE_CONTENT: Error parsing activity: $e');
        }
      }

      await Logger.instance.log('COURSE_CONTENT: Total resources found: ${resources.length}');
      return resources;
    } catch (e) {
      await Logger.instance.log('COURSE_CONTENT: Exception: $e');
      return resources;
    } finally {
      client.close();
    }
  }

  String _detectResourceType(String href, String text, dynamic element) {
    final hrefLower = href.toLowerCase();
    final textLower = text.toLowerCase();
    final classes = (element.attributes['class'] ?? '').toLowerCase();

    // PDF detection
    if (hrefLower.contains('.pdf') || 
        hrefLower.contains('/mod/resource/') ||
        textLower.contains('pdf') ||
        classes.contains('pdf')) {
      return 'pdf';
    }

    // Video detection
    if (hrefLower.contains('video') || 
        hrefLower.contains('youtube') ||
        hrefLower.contains('vimeo') ||
        textLower.contains('video') ||
        textLower.contains('vídeo') ||
        classes.contains('video')) {
      return 'video';
    }

    // Book detection
    if (hrefLower.contains('/mod/book/') ||
        textLower.contains('book') ||
        textLower.contains('libro') ||
        classes.contains('book')) {
      return 'book';
    }

    // Generic link
    if (hrefLower.startsWith('http') || hrefLower.startsWith('/')) {
      return 'link';
    }

    return 'unknown';
  }
}
