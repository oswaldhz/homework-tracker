import google.generativeai as genai
import json
import os
import re
import requests
from typing import List, Dict
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from config import GEMINI_KEY_PATH

def search_youtube(query: str, max_results: int = 5) -> List[Dict]:
    """Search YouTube and return real video URLs with titles"""
    search_url = f"https://www.youtube.com/results?search_query={requests.utils.quote(query)}"
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
    
    try:
        r = requests.get(search_url, headers=headers, timeout=10)
        if r.status_code != 200:
            return []
        
        # Extract video IDs and titles from the ytInitialData JSON blob
        videos = []
        seen_ids = set()

        # Try to extract from ytInitialData for richer metadata
        init_data_match = re.search(r'var ytInitialData\s*=\s*(\{.+?\});\s*</script>', r.text, re.DOTALL)
        if init_data_match:
            try:
                data = json.loads(init_data_match.group(1))
                contents = (
                    data.get('contents', {})
                    .get('twoColumnSearchResultsRenderer', {})
                    .get('primaryContents', {})
                    .get('sectionListRenderer', {})
                    .get('contents', [])
                )
                for section in contents:
                    items = section.get('itemSectionRenderer', {}).get('contents', [])
                    for item in items:
                        vr = item.get('videoRenderer', {})
                        vid = vr.get('videoId')
                        if not vid or vid in seen_ids:
                            continue
                        title_runs = vr.get('title', {}).get('runs', [])
                        title = ''.join(r.get('text', '') for r in title_runs) or 'YouTube Video'
                        channel_runs = vr.get('ownerText', {}).get('runs', [])
                        channel = ''.join(r.get('text', '') for r in channel_runs)
                        seen_ids.add(vid)
                        videos.append({
                            "url": f"https://www.youtube.com/watch?v={vid}",
                            "video_id": vid,
                            "title": title,
                            "channel": channel,
                        })
                        if len(videos) >= max_results:
                            return videos
            except (json.JSONDecodeError, KeyError):
                pass

        # Fallback: regex extraction without titles
        if not videos:
            watch_pattern = r'"watch\?v=([a-zA-Z0-9_-]{11})"'
            matches = re.findall(watch_pattern, r.text)
            video_id_pattern = r'"videoId":"([a-zA-Z0-9_-]{11})"'
            matches += re.findall(video_id_pattern, r.text)
            for vid in dict.fromkeys(matches):
                if vid not in seen_ids:
                    seen_ids.add(vid)
                    videos.append({
                        "url": f"https://www.youtube.com/watch?v={vid}",
                        "video_id": vid,
                        "title": f"YouTube Video",
                        "channel": "",
                    })
                    if len(videos) >= max_results:
                        break

        return videos
    except Exception as e:
        print(f"YouTube search error: {e}")
        return []

def verify_youtube_video(url: str) -> bool:
    """Verify a YouTube video is actually available"""
    try:
        r = requests.get(url, timeout=10, allow_redirects=True,
                        headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"})
        if r.status_code != 200:
            return False
        content = r.text
        # Check for error indicators
        if '"status":"ERROR"' in content and '"reason":"Video unavailable"' in content:
            return False
        return True
    except Exception:
        return False

class GeminiMaterialFinder:
    def __init__(self):
        self.available = False
        self.model = None
        self.search_tool = None
        if GEMINI_KEY_PATH.exists():
            try:
                api_key = GEMINI_KEY_PATH.read_text().strip()
                if api_key:
                    genai.configure(api_key=api_key)
                    self.model = genai.GenerativeModel('gemini-2.5-flash')
                    self.search_tool = genai.protos.Tool(google_search=genai.protos.Tool.GoogleSearch())
                    self.available = True
            except Exception as e:
                print(f"Warning: Failed to initialize Gemini with saved key: {e}")

    def set_api_key(self, api_key: str):
        GEMINI_KEY_PATH.write_text(api_key.strip())
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel('gemini-2.5-flash')
        self.search_tool = genai.protos.Tool(google_search=genai.protos.Tool.GoogleSearch())
        self.available = True

    def _verify_url(self, url: str) -> bool:
        if not url or not url.startswith("http"):
            return False
        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Accept-Encoding": "gzip, deflate, br",
                "Connection": "keep-alive",
                "Upgrade-Insecure-Requests": "1"
            }
            r = requests.get(url, timeout=15, allow_redirects=True, headers=headers)
            
            # Check HTTP status
            if r.status_code == 404:
                return False
            if r.status_code != 200:
                return False
            
            # Check for common 404 indicators in the page title and content
            content = r.text
            content_lower = content.lower()
            
            # Check page title for 404 indicators
            title_match = re.search(r'<title[^>]*>(.*?)</title>', content, re.IGNORECASE | re.DOTALL)
            if title_match:
                title = title_match.group(1).lower()
                if any(indicator in title for indicator in [
                    '404', 'not found', 'page not found', 'error 404',
                    'page introuvable', 'seite nicht gefunden'
                ]):
                    return False
            
            # Check for 404 indicators in the first part of the page (before dynamic content)
            first_part = content_lower[:15000]
            if any(indicator in first_part for indicator in [
                '<h1>404', '<h2>404', '404 not found', 'page not found',
                'the page you requested', 'cannot be found', 'doesn\'t exist',
                'no longer exists', 'has been removed'
            ]):
                return False
            
            # Check if page has meaningful content (not just an error page)
            if len(content) < 1000:
                return False
            
            return True
        except requests.exceptions.Timeout:
            return False
        except requests.exceptions.ConnectionError:
            return False
        except Exception:
            return False

    def _verify_urls_parallel(self, urls: List[str]) -> List[str]:
        unique = list(dict.fromkeys([u for u in urls if u]))
        if not unique:
            return []
        valid = []
        with ThreadPoolExecutor(max_workers=8) as ex:
            futures = {ex.submit(self._verify_url, u): u for u in unique}
            for fut in as_completed(futures):
                u = futures[fut]
                try:
                    if fut.result():
                        valid.append(u)
                except Exception:
                    pass
        return valid

    def find_materials(self, task_title: str, task_description: str, course_name: str) -> Dict:
        if not self.available:
            return {
                'videos': [],
                'articles': [],
                'pdfs': [],
                'key_concepts': [],
                'study_tips': '',
                'ai_generated': False,
                'error': 'Gemini API key not configured'
            }

        # Step 1: Use Gemini to generate search queries and educational content
        prompt = f"""You are an educational AI assistant. Analyze this homework task and generate search queries and educational content.

Task Title: {task_title}
Course: {course_name}
Description: {task_description}

Return ONLY a valid JSON object with this exact structure (no markdown, no extra text):

{{
  "search_queries": [
    "query1 for YouTube search",
    "query2 for YouTube search",
    "query3 for YouTube search"
  ],
  "key_concepts": [
    {{
      "name": "Concept name",
      "explanation": "Clear explanation"
    }}
  ],
  "study_tips": "Practical advice to complete this task",
  "article_suggestions": [
    {{
      "title": "Article title",
      "url": "https://...",
      "description": "Brief description",
      "source": "Website name"
    }}
  ]
}}

Requirements:
- Generate 3 specific YouTube search queries in English or Spanish
- 3-5 key concepts with brief explanations
- Practical study tips
- 2-3 article suggestions from educational websites (W3Schools, MDN, GeeksforGeeks, tutorialspoint, Real Python, freeCodeCamp, Khan Academy, etc.)
- All article URLs MUST be real, existing pages from those sites

Return ONLY the JSON object."""

        try:
            response = self.model.generate_content(prompt, tools=[self.search_tool])
            response_text = response.text.strip()
            response_text = re.sub(r'^```(json)?\s*', '', response_text)
            response_text = re.sub(r'\s*```$', '', response_text)
            response_text = response_text.strip()

            data = json.loads(response_text)

            # Step 2: Search YouTube using the generated queries
            search_queries = data.get('search_queries', [])
            if not search_queries:
                # Fallback queries based on task
                search_queries = [
                    f"{task_title} tutorial",
                    f"{task_title} {course_name}",
                    f"{task_title} explained"
                ]

            # Search YouTube for each query
            all_videos = []
            for query in search_queries[:3]:
                videos = search_youtube(query, max_results=3)
                all_videos.extend(videos)

            # Remove duplicates
            unique_videos = []
            seen_ids = set()
            for v in all_videos:
                if v['video_id'] not in seen_ids:
                    seen_ids.add(v['video_id'])
                    unique_videos.append(v)

            # Verify videos are actually available
            valid_videos = []
            with ThreadPoolExecutor(max_workers=8) as ex:
                futures = {ex.submit(verify_youtube_video, v['url']): v for v in unique_videos[:10]}
                for fut in as_completed(futures):
                    v = futures[fut]
                    try:
                        if fut.result():
                            valid_videos.append(v)
                    except Exception:
                        pass

            # Format videos for response
            videos = []
            for v in valid_videos[:5]:
                videos.append({
                    "title": v.get("title", "YouTube Video"),
                    "url": v['url'],
                    "channel": v.get("channel", ""),
                    "description": ""
                })

            # Step 3: Verify article URLs
            articles_raw = data.get('article_suggestions', [])
            article_urls = [a.get('url', '') for a in articles_raw]
            valid_article_urls = set(self._verify_urls_parallel(article_urls))

            articles = []
            for a in articles_raw:
                if a.get('url') in valid_article_urls:
                    articles.append({
                        "title": a.get('title', 'Article'),
                        "url": a.get('url'),
                        "description": a.get('description', ''),
                        "source": a.get('source', '')
                    })

            key_concepts = data.get('key_concepts', [])
            if not isinstance(key_concepts, list):
                key_concepts = []

            return {
                'videos': videos,
                'articles': articles[:5],
                'pdfs': [],
                'key_concepts': key_concepts,
                'study_tips': data.get('study_tips', ''),
                'learning_path': [],
                'practice_questions': [],
                'search_suggestions': search_queries,
                'ai_generated': True
            }

        except json.JSONDecodeError as e:
            print(f"JSON parse error: {e}")
            print(f"Response: {response.text[:500] if 'response' in dir() else 'N/A'}")
            return {
                'videos': [], 'articles': [], 'pdfs': [],
                'key_concepts': [], 'study_tips': '',
                'ai_generated': False, 'error': f'Failed to parse AI response: {str(e)}'
            }
        except Exception as e:
            error_str = str(e).lower()
            print(f"Gemini API error: {e}")
            
            # Check for quota/rate limit errors
            if 'quota' in error_str or 'rate limit' in error_str or 'resource exhausted' in error_str or '429' in error_str:
                return {
                    'videos': [], 'articles': [], 'pdfs': [],
                    'key_concepts': [], 'study_tips': '',
                    'ai_generated': False, 
                    'error': 'You are out of AI tokens. Please wait or check your Gemini API quota.'
                }
            
            return {
                'videos': [], 'articles': [], 'pdfs': [],
                'key_concepts': [], 'study_tips': '',
                'ai_generated': False, 'error': f'AI error: {str(e)}'
            }


gemini_finder = GeminiMaterialFinder()
