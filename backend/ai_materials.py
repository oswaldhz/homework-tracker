import google.generativeai as genai
import json
import os
import re
import requests
from typing import List, Dict
from pathlib import Path
from config import GEMINI_KEY_PATH

def search_youtube_invidious(query: str, max_results: int = 5) -> List[Dict]:
    """Search YouTube via Invidious API and return real video URLs with titles"""
    invidious_url = f"https://inv.thepixora.com/api/v1/search?q={requests.utils.quote(query)}&type=video"

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }

    try:
        r = requests.get(invidious_url, headers=headers, timeout=10)
        if r.status_code != 200:
            return []

        data = r.json()
        if not isinstance(data, list):
            return []

        videos = []
        for item in data:
            if not isinstance(item, dict):
                continue
            if item.get('type') != 'video':
                continue
            vid = item.get('videoId', '')
            if not vid or len(vid) != 11:
                continue
            videos.append({
                "url": f"https://www.youtube.com/watch?v={vid}",
                "video_id": vid,
                "title": item.get('title', 'YouTube Video'),
                "channel": item.get('author', ''),
            })
            if len(videos) >= max_results:
                break

        return videos
    except Exception as e:
        print(f"Invidious search error: {e}")
        return []


def search_duckduckgo(query: str, max_results: int = 3) -> List[Dict]:
    """Search DuckDuckGo and return real article URLs with titles"""
    try:
        r = requests.post(
            "https://html.duckduckgo.com/html/",
            data={"q": query},
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"},
            timeout=10,
        )
        if r.status_code != 200:
            return []

        results = []
        pattern = re.compile(
            r'<a rel="nofollow" class="result__a" href="([^"]*)"[^>]*>(.*?)</a>.*?'
            r'class="result__snippet"[^>]*>(.*?)</(?:a|td)>',
            re.DOTALL,
        )

        for match in pattern.finditer(r.text):
            raw_url = match.group(1)
            title = re.sub(r'<[^>]*>', '', match.group(2)).strip()
            snippet = re.sub(r'<[^>]*>', '', match.group(3)).strip()

            uddg = re.search(r'uddg=([^&]+)', raw_url)
            if uddg:
                from urllib.parse import unquote
                raw_url = unquote(uddg.group(1))

            if not raw_url or not raw_url.startswith('http'):
                continue

            try:
                from urllib.parse import urlparse
                host = urlparse(raw_url).netloc
            except Exception:
                continue

            results.append({
                "url": raw_url,
                "title": title if title else "Article",
                "description": snippet,
                "source": host,
            })
            if len(results) >= max_results:
                break

        return results
    except Exception as e:
        print(f"DuckDuckGo search error: {e}")
        return []

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

        # Step 1: Use Gemini to generate search topics and educational content
        prompt = f"""You are an educational AI assistant. Analyze this homework task and generate search topics and educational content.

Task Title: {task_title}
Course: {course_name}
Description: {task_description}

Return ONLY a valid JSON object with this exact structure (no markdown, no extra text):

{{
  "search_topics": [
    "topic 1 to search for",
    "topic 2 to search for",
    "topic 3 to search for"
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
      "title": "Descriptive article title",
      "description": "Brief description",
      "source": "Website name"
    }}
  ]
}}

Requirements:
- Generate 3 search topics relevant to the task
- 3-5 key concepts with brief explanations
- Practical study tips
- 2-3 article suggestions with clear, descriptive titles

Return ONLY the JSON object."""

        try:
            response = self.model.generate_content(prompt, tools=[self.search_tool])
            response_text = response.text.strip()
            response_text = re.sub(r'^```(json)?\s*', '', response_text)
            response_text = re.sub(r'\s*```$', '', response_text)
            response_text = response_text.strip()

            data = json.loads(response_text)

            # Step 2: Extract search topics (handle both key names for compatibility)
            search_topics = data.get('search_topics', [])
            if not search_topics:
                search_topics = data.get('search_queries', [])
            if not search_topics:
                search_topics = [
                    f"{task_title} tutorial",
                    f"{task_title} {course_name}",
                    f"{task_title} explained"
                ]

            # Step 3: Search YouTube via Invidious for each topic
            all_videos = []
            seen_ids = set()
            for topic in search_topics[:3]:
                videos = search_youtube_invidious(topic, max_results=3)
                for v in videos:
                    vid = v.get('video_id', '')
                    if vid and vid not in seen_ids:
                        seen_ids.add(vid)
                        all_videos.append(v)

            videos = []
            for v in all_videos[:5]:
                videos.append({
                    "title": v.get("title", "YouTube Video"),
                    "url": v['url'],
                    "channel": v.get("channel", ""),
                    "description": ""
                })

            # Step 4: Find real article URLs via DuckDuckGo
            articles_raw = data.get('article_suggestions', [])
            articles = []
            seen_urls = set()

            for a in articles_raw:
                title = a.get('title', '')
                if not title:
                    continue
                search_results = search_duckduckgo(title, max_results=1)
                url = search_results[0]['url'] if search_results else None
                if url and url not in seen_urls:
                    seen_urls.add(url)
                    articles.append({
                        "title": title,
                        "url": url,
                        "description": a.get('description', ''),
                        "source": a.get('source', ''),
                    })
                if len(articles) >= 5:
                    break

            # Fill remaining article slots with topic searches
            if len(articles) < 3:
                for topic in search_topics:
                    search_results = search_duckduckgo(topic, max_results=2)
                    for r in search_results:
                        url = r['url']
                        if url not in seen_urls:
                            seen_urls.add(url)
                            articles.append({
                                "title": r['title'],
                                "url": url,
                                "description": r['description'],
                                "source": r['source'],
                            })
                        if len(articles) >= 5:
                            break
                    if len(articles) >= 5:
                        break

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
                'search_suggestions': search_topics,
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
