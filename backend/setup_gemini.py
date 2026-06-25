import sys
from pathlib import Path

def setup_gemini_key():
    print("=" * 60)
    print("Google Gemini AI Setup")
    print("=" * 60)
    print()
    print("To enable AI-powered learning materials, you need a")
    print("Google Gemini API key (FREE tier available).")
    print()
    print("Steps:")
    print("1. Go to: https://aistudio.google.com/app/apikey")
    print("2. Sign in with your Google account")
    print("3. Click 'Create API Key'")
    print("4. Copy the key")
    print()
    
    api_key = input("Paste your Gemini API key here: ").strip()
    
    if not api_key:
        print("No API key provided. Exiting.")
        return
    
    api_key_file = Path(__file__).parent / ".gemini_api_key"
    api_key_file.write_text(api_key)
    
    print()
    print("✓ API key saved successfully!")
    print()
    print("You can now use the AI materials feature in the app.")
    print("The key is stored locally in: .gemini_api_key")
    print()
    print("Free tier limits:")
    print("- 15 requests per minute")
    print("- 1 million tokens per minute")
    print("- More than enough for personal use!")
    print()

if __name__ == "__main__":
    setup_gemini_key()
