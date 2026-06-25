import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AiService {
  static final AiService instance = AiService._();
  AiService._();

  String? _apiKey;
  bool _available = false;

  bool get available => _available;

  Future<void> _loadApiKey() async {
    if (_apiKey != null) return;

    final appDataDir = await getApplicationSupportDirectory();
    final keyFile = File(p.join(appDataDir.path, 'HomeworkTracker', '.gemini_api_key'));

    if (await keyFile.exists()) {
      _apiKey = (await keyFile.readAsString()).trim();
      _available = true;
    }
  }

  Future<bool> checkStatus() async {
    await _loadApiKey();
    return _available;
  }

  Future<void> setApiKey(String apiKey) async {
    final appDataDir = await getApplicationSupportDirectory();
    final keyDir = Directory(p.join(appDataDir.path, 'HomeworkTracker'));
    if (!await keyDir.exists()) {
      await keyDir.create(recursive: true);
    }

    final keyFile = File(p.join(keyDir.path, '.gemini_api_key'));
    await keyFile.writeAsString(apiKey.trim());
    _apiKey = apiKey.trim();
    _available = true;
  }

  Future<Map<String, dynamic>> findMaterials({
    required String taskTitle,
    required String taskDescription,
    required String courseName,
    String? moodleUrl,
    String? username,
    String? password,
    String? sessionCookie,
  }) async {
    await _loadApiKey();

    if (!_available || _apiKey == null) {
      return {
        'videos': [],
        'articles': [],
        'pdfs': [],
        'key_concepts': [],
        'study_tips': '',
        'ai_generated': false,
        'error': 'Gemini API key not configured',
      };
    }

    List<Map<String, dynamic>> moodleResources = [];
    if (moodleUrl != null && moodleUrl.isNotEmpty) {
      try {
        moodleResources = await _scrapeMoodleCourseContent(
          moodleUrl: moodleUrl,
          username: username ?? '',
          password: password ?? '',
          sessionCookie: sessionCookie,
          courseName: courseName,
        );
      } catch (e) {
      }
    }

    final prompt = '''You are an educational AI assistant with Google Search access. Analyze this homework task and generate educational content.

Task Title: $taskTitle
Course: $courseName
Description: $taskDescription

Return ONLY a valid JSON object with this exact structure (no markdown, no extra text):

{
  "search_topics": [
    "topic 1 to search for",
    "topic 2 to search for",
    "topic 3 to search for"
  ],
  "key_concepts": [
    {
      "name": "Concept name",
      "explanation": "Clear explanation"
    }
  ],
  "study_tips": "Practical advice to complete this task",
  "article_suggestions": [
    {
      "title": "Descriptive article title",
      "description": "Brief description",
      "source": "Website name"
    }
  ]
}

Requirements:
- Generate 3 search topics relevant to the task
- 3-5 key concepts with brief explanations
- Practical study tips
- 2-3 article suggestions with clear, descriptive titles

Return ONLY the JSON object.''';

    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'tools': [
            {'googleSearch': {}}
          ],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Gemini API error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      var responseText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
      responseText = responseText.replaceAll(RegExp(r'^```(json)?\s*'), '').replaceAll(RegExp(r'\s*```$'), '').trim();

      final aiData = jsonDecode(responseText);
      var searchTopics = List<String>.from(aiData['search_topics'] ?? []);
      if (searchTopics.isEmpty) {
        searchTopics = List<String>.from(aiData['search_queries'] ?? []);
      }

      // 1. Search YouTube via Invidious API for each topic
      final allVideos = <Map<String, dynamic>>[];
      final seenIds = <String>{};

      for (final topic in searchTopics) {
        final videos = await _searchYouTubeInvidious(topic);
        for (final v in videos) {
          if (seenIds.add(v['video_id'])) {
            allVideos.add(v);
          }
        }
      }

      final validVideos = <Map<String, dynamic>>[];
      for (final v in allVideos) {
        validVideos.add({
          'title': v['title'] ?? 'YouTube Tutorial',
          'url': v['url'],
          'channel': v['channel'] ?? '',
          'description': '',
        });
        if (validVideos.length >= 5) break;
      }

      // 2. Find real article URLs via DuckDuckGo search
      final articleSuggestions = List<Map<String, dynamic>>.from(aiData['article_suggestions'] ?? []);
      final articles = <Map<String, dynamic>>[];
      final seenUrls = <String>{};

      for (final a in articleSuggestions) {
        final title = a['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        final searchResults = await _searchDuckDuckGo(title);
        final url = searchResults.isNotEmpty ? searchResults.first['url'] : null;
        if (url != null && seenUrls.add(url)) {
          articles.add({
            'title': title,
            'url': url,
            'description': a['description']?.toString() ?? '',
            'source': a['source']?.toString() ?? '',
          });
          if (articles.length >= 5) break;
        }
      }

      // 3. Also search for articles from search topics if we have room
      if (articles.length < 3) {
        for (final topic in searchTopics) {
          final searchResults = await _searchDuckDuckGo(topic);
          for (final r in searchResults) {
            if (seenUrls.add(r['url'])) {
              articles.add({
                'title': r['title'],
                'url': r['url'],
                'description': r['description'] ?? '',
                'source': r['source'] ?? '',
              });
              if (articles.length >= 5) break;
            }
          }
          if (articles.length >= 5) break;
        }
      }

      final allPdfs = <Map<String, dynamic>>[...moodleResources.where((r) => r['type'] == 'pdf')];
      final allVideosCombined = <Map<String, dynamic>>[
        ...validVideos,
        ...moodleResources.where((r) => r['type'] == 'video'),
      ];

      return {
        'videos': allVideosCombined.take(8).toList(),
        'articles': articles,
        'pdfs': allPdfs,
        'books': moodleResources.where((r) => r['type'] == 'book').toList(),
        'key_concepts': List<Map<String, dynamic>>.from(aiData['key_concepts'] ?? []),
        'study_tips': aiData['study_tips'] ?? '',
        'search_suggestions': searchTopics,
        'ai_generated': true,
        'moodle_resources': moodleResources,
      };
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('quota') || errorStr.contains('429') || errorStr.contains('resource exhausted')) {
        return {
          'videos': [],
          'articles': [],
          'pdfs': [],
          'key_concepts': [],
          'study_tips': '',
          'ai_generated': false,
          'error': 'You are out of AI tokens. Please wait or check your Gemini API quota.',
        };
      }
      return {
        'videos': [],
        'articles': [],
        'pdfs': [],
        'key_concepts': [],
        'study_tips': '',
        'ai_generated': false,
        'error': 'AI error: $e',
      };
    }
  }

  Future<List<Map<String, dynamic>>> _searchYouTubeInvidious(String query, {int maxResults = 5}) async {
    try {
      final response = await http.get(
        Uri.parse('https://inv.thepixora.com/api/v1/search?q=${Uri.encodeComponent(query)}&type=video'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      if (data is! List) return [];

      final videos = <Map<String, dynamic>>[];
      for (final v in data) {
        if (v is! Map) continue;
        if (v['type'] != 'video') continue;
        final videoId = v['videoId']?.toString() ?? '';
        if (videoId.isEmpty || videoId.length != 11) continue;
        videos.add({
          'url': 'https://www.youtube.com/watch?v=$videoId',
          'video_id': videoId,
          'title': v['title']?.toString() ?? 'YouTube Tutorial',
          'channel': v['author']?.toString() ?? '',
        });
        if (videos.length >= maxResults) break;
      }

      return videos;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchDuckDuckGo(String query, {int maxResults = 3}) async {
    try {
      final response = await http.post(
        Uri.parse('https://html.duckduckgo.com/html/'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'q': query},
      );

      if (response.statusCode != 200) return [];

      final body = response.body;
      final results = <Map<String, dynamic>>[];

      final resultRegex = RegExp(
        r'<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>(.*?)</a>.*?'
        r'class="result__snippet"[^>]*>(.*?)</(?:a|td)>',
        dotAll: true,
      );

      for (final match in resultRegex.allMatches(body)) {
        var rawUrl = match.group(1) ?? '';
        final title = _stripHtml(match.group(2) ?? '');
        var snippet = _stripHtml(match.group(3) ?? '');

        final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(rawUrl);
        if (uddgMatch != null) {
          rawUrl = Uri.decodeComponent(uddgMatch.group(1)!);
        }

        if (rawUrl.isEmpty || !rawUrl.startsWith('http')) continue;

        var host = '';
        try {
          host = Uri.parse(rawUrl).host;
        } catch (_) {
          continue;
        }

        results.add({
          'url': rawUrl,
          'title': title.isNotEmpty ? title : 'Article',
          'description': snippet,
          'source': host,
        });
        if (results.length >= maxResults) break;
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<List<Map<String, dynamic>>> _scrapeMoodleCourseContent({
    required String moodleUrl,
    required String username,
    required String password,
    String? sessionCookie,
    required String courseName,
  }) async {
    try {
      final resources = <Map<String, dynamic>>[];
      return resources;
    } catch (e) {
      return [];
    }
  }
}
