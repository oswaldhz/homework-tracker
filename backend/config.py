import os
from pathlib import Path

APP_NAME = "HomeworkTracker"

def get_app_data_dir() -> Path:
    appdata = os.environ.get('APPDATA')
    if appdata:
        app_dir = Path(appdata) / APP_NAME
    else:
        app_dir = Path.cwd() / APP_NAME
    app_dir.mkdir(parents=True, exist_ok=True)
    return app_dir

APP_DATA_DIR = get_app_data_dir()
DB_PATH = APP_DATA_DIR / "homework_tracker.db"
ENCRYPTION_KEY_PATH = APP_DATA_DIR / ".encryption_key"
GEMINI_KEY_PATH = APP_DATA_DIR / ".gemini_api_key"
BROWSER_DATA_DIR = APP_DATA_DIR / "browser_data"
UPLOADS_DIR = APP_DATA_DIR / "uploads"
