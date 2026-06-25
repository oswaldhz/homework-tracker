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

    // First, scrape Moodle course content if credentials are available
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
        // Continue even if Moodle scraping fails
      }
    }

    final prompt = '''You are an educational AI assistant. Analyze this homework task and generate search queries and educational content.

Task Title: $taskTitle
Course: $courseName
Description: $taskDescription

CRITICAL INSTRUCTIONS FOR URLs:
- ONLY provide URLs that you are 100% CERTAIN exist and are accessible
- DO NOT make up or hallucinate URLs
- ONLY use URLs from well-known educational sites: W3Schools, MDN Web Docs, GeeksforGeeks, Tutorialspoint, Real Python, freeCodeCamp, Khan Academy, Coursera, edX, MIT OpenCourseWare
- If you're unsure about a URL, DO NOT include it
- Prefer general documentation pages over specific articles

Return ONLY a valid JSON object with this exact structure (no markdown, no extra text):

{
  "search_queries": [
    "query1 for YouTube search",
    "query2 for YouTube search",
    "query3 for YouTube search"
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
      "title": "Article title",
      "url": "https://...",
      "description": "Brief description",
      "source": "Website name"
    }
  ]
}

Requirements:
- Generate 3 specific YouTube search queries in English or Spanish
- 3-5 key concepts with brief explanations
- Practical study tips
- 2-3 article suggestions from educational websites ONLY if you are certain the URLs exist
- All article URLs MUST be real, existing pages from trusted educational sites

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

      final searchQueries = List<String>.from(aiData['search_queries'] ?? []);
      final allVideos = <Map<String, dynamic>>[];

      for (final query in searchQueries.take(3)) {
        final videos = await _searchYouTube(query);
        allVideos.addAll(videos);
      }

      final seenIds = <String>{};
      final uniqueVideos = <Map<String, dynamic>>[];
      for (final v in allVideos) {
        if (!seenIds.contains(v['video_id'])) {
          seenIds.add(v['video_id']);
          uniqueVideos.add(v);
        }
      }

      final validVideos = <Map<String, dynamic>>[];
      for (final v in uniqueVideos.take(10)) {
        if (await _verifyYouTubeVideo(v['url'])) {
          validVideos.add({
            'title': v['title'] ?? 'YouTube Tutorial',
            'url': v['url'],
            'channel': v['channel'] ?? '',
            'description': '',
          });
          if (validVideos.length >= 5) break;
        }
      }

      final articleSuggestions = List<Map<String, dynamic>>.from(aiData['article_suggestions'] ?? []);
      final articleUrls = articleSuggestions
          .map((a) => a['url']?.toString() ?? '')
          .where((String u) => u.isNotEmpty)
          .toList();
      final validArticleUrls = <String>{};
      for (final url in articleUrls) {
        if (await _verifyUrl(url)) {
          validArticleUrls.add(url);
        }
      }

      final articles = <Map<String, dynamic>>[];
      for (final a in articleSuggestions) {
        if (validArticleUrls.contains(a['url'])) {
          articles.add({
            'title': a['title'] ?? 'Article',
            'url': a['url'],
            'description': a['description'] ?? '',
            'source': a['source'] ?? '',
          });
          if (articles.length >= 5) break;
        }
      }

      // Combine Moodle resources with AI-generated content
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
        'search_suggestions': searchQueries,
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

  Future<List<Map<String, dynamic>>> _scrapeMoodleCourseContent({
    required String moodleUrl,
    required String username,
    required String password,
    String? sessionCookie,
    required String courseName,
  }) async {
    try {
      final resources = <Map<String, dynamic>>[];
      
      // This would need to be implemented in moodle_service.dart
      // For now, return empty list
      // In a real implementation, you would:
      // 1. Login to Moodle
      // 2. Navigate to the course page
      // 3. Scrape all resources (books, PDFs, videos, links)
      // 4. Return them as a list
      
      return resources;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchYouTube(String query, {int maxResults = 5}) async {
    try {
      final searchUrl = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}';
      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      );

      if (response.statusCode != 200) return [];

      final videos = <Map<String, dynamic>>[];
      final seenIds = <String>{};

      // Try extracting from ytInitialData JSON
      final initDataMatch = RegExp(r'window\.ytInitialData\s*=\s*({.*?});\s*</script>', dotAll: true).firstMatch(response.body);
      if (initDataMatch != null) {
        try {
          final initData = jsonDecode(initDataMatch.group(1)!);
          const searchPath = ['contents', 'twoColumnSearchResultsRenderer', 'primaryContents', 'sectionListRenderer', 'contents'];
          var sectionContents = initData;
          for (final key in searchPath) {
            sectionContents = sectionContents?[key];
            if (sectionContents is List) break;
          }
          if (sectionContents is List) {
            for (final section in sectionContents) {
              final contents = section?['itemSectionRenderer']?['contents'];
              if (contents is! List) continue;
              for (final item in contents) {
                final videoRenderer = item?['videoRenderer'];
                if (videoRenderer == null) continue;
                final videoId = videoRenderer['videoId']?.toString();
                if (videoId == null || seenIds.contains(videoId)) continue;
                seenIds.add(videoId);
                final titleObj = videoRenderer['title']?['runs'];
                final title = (titleObj is List ? titleObj.map((r) => r['text']?.toString() ?? '').join() : videoRenderer['title']?['simpleText']?.toString()) ?? 'YouTube Tutorial';
                final channel = videoRenderer['ownerText']?['runs']?.first?['text']?.toString() ?? '';
                videos.add({
                  'url': 'https://www.youtube.com/watch?v=$videoId',
                  'video_id': videoId,
                  'title': title,
                  'channel': channel,
                });
                if (videos.length >= maxResults) break;
              }
              if (videos.length >= maxResults) break;
            }
          }
        } catch (_) {}
      }

      // Fallback: extract from HTML attributes
      if (videos.isEmpty) {
        final linkPattern = RegExp(r'<a[^>]*href="/watch\?v=([a-zA-Z0-9_-]{11})"[^>]*title="([^"]*)"');
        for (final match in linkPattern.allMatches(response.body)) {
          final videoId = match.group(1)!;
          if (seenIds.contains(videoId)) continue;
          seenIds.add(videoId);
          final title = match.group(2)?.trim() ?? 'YouTube Tutorial';
          videos.add({
            'url': 'https://www.youtube.com/watch?v=$videoId',
            'video_id': videoId,
            'title': title,
            'channel': '',
          });
          if (videos.length >= maxResults) break;
        }
      }

      return videos;
    } catch (e) {
      return [];
    }
  }

  Future<bool> _verifyYouTubeVideo(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      );
      if (response.statusCode != 200) return false;
      if (response.body.contains('"status":"ERROR"') && response.body.contains('"reason":"Video unavailable"')) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _verifyUrl(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return false;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      );
      if (response.statusCode == 404) return false;
      if (response.statusCode != 200) return false;
      if (response.body.length < 1000) return false;
      return true;
    } catch (e) {
      return false;
    }
  }
}
