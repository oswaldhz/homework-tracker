# Homework Tracker

A cross-platform homework tracker that connects to your Moodle virtual classroom, scrapes assignments for the current week, and displays them in a clean dashboard with completion tracking and notifications.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Flutter App                         │
│  ├─ Windows 11 / 10 desktop                         │
│  ├─ Android (future)                                │
│  └─ iOS (future)                                    │
│                                                      │
│  Login & scrape Moodle directly with Dart HTTP       │
│  SQLite local database (sqflite_common_ffi)         │
│  Encrypted credential storage                        │
└─────────────────────────────────────────────────────┘
```

> **Note:** A Python FastAPI backend exists in the `backend/` folder, but the
> current Flutter frontend scrapes Moodle directly. The backend is kept for
> future expansion (e.g. a hosted API for mobile).

## Features

- **Moodle Integration**: Automatically logs into your Moodle site and extracts assignments
- **Task Dashboard**: View pending, completed, and overdue tasks
- **Completion Tracking**: Mark tasks as done with a single click (syncs to Moodle!)
- **Auto-Refresh**: Backend checks Moodle every 30 minutes for new assignments
- **Notifications**: Desktop and mobile alerts for due-soon tasks
- **Cross-Platform**: Windows desktop + iOS (via Codemagic CI)
- **Encrypted Credentials**: Your login info is stored securely
- **Dark Mode**: Toggle between light and dark themes
- **Calendar View**: See tasks in a calendar layout with tasks inside day boxes
- **Task Filtering**: Filter by course, status, or date range
- **Task Details**: Full description view with web access
- **AI Learning Materials**: Google Gemini AI analyzes tasks and suggests relevant videos, articles, and PDFs
- **Moodle Sync**: Toggle completion status syncs back to Moodle automatically

## Project Structure

```
homework-tracker/
├── backend/              # Python FastAPI
│   ├── main.py           # API server
│   ├── scraper.py        # Playwright Moodle automation
│   ├── models.py         # SQLite models
│   ├── scheduler.py      # Periodic task checks
│   ├── auth.py           # Credential encryption
│   └── requirements.txt
├── frontend/             # Flutter app
│   └── lib/
│       ├── main.dart
│       ├── screens/      # Login, Dashboard
│       ├── models/       # Task model
│       ├── services/     # API client, notifications
│       └── widgets/      # Task cards
└── start_backend.bat     # Quick start script
```

## Setup

### Frontend (Flutter)

1. **Install Flutter SDK**:
   - Download from https://docs.flutter.dev/get-started/install/windows
   - Add to PATH: `C:\flutter\bin`
   - Run `flutter doctor` to verify

2. **Get dependencies**:
   ```bash
   cd frontend
   flutter pub get
   ```

3. **Run on Windows**:
   ```bash
   flutter run -d windows
   ```

4. **Build for Windows**:
   ```bash
   flutter build windows
   ```

### Optional: Python Backend

The backend in `backend/` is **not required** for the current Flutter app. If you
want to experiment with it or host an API later:

```bash
cd backend
venv\Scripts\activate
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### iOS (Later)

Since you're on Windows, you'll use **Codemagic** (free tier) to build the iOS app:

1. Push your code to GitHub
2. Connect your repo to Codemagic
3. Configure iOS build workflow
4. Codemagic will build the `.ipa` file using their Mac infrastructure

## Usage

1. **Launch the Flutter app**
2. **Login** with your Moodle credentials:
   - Moodle URL (e.g., `https://your-school.moodle.com`)
   - Username
   - Password
   - If your school uses **Office 365 / Microsoft SSO**, tap *Login with Office 365* and paste your Moodle session cookie after logging in through the browser.
3. The app will automatically fetch your assignments
4. Tasks are grouped by: Pending, Completed, Overdue
5. Click on a task to mark it as complete

## Optional Backend API Endpoints

If you choose to run the Python backend, these endpoints are available:

- `POST /api/login` - Save credentials and fetch tasks
- `GET /api/tasks` - Get all tasks (optional: `?week=true` for current week only)
- `PATCH /api/tasks/{id}/complete` - Toggle task completion
- `POST /api/tasks/{id}/sync-completion` - Sync completion status to Moodle
- `POST /api/refresh` - Manually refresh from Moodle
- `GET /api/courses` - Get list of courses
- `GET /api/stats` - Get task statistics
- `GET /api/tasks/{id}/materials` - Get AI-generated learning materials for a task
- `POST /api/set-gemini-key` - Configure Gemini API key
- `GET /api/gemini-status` - Check if Gemini AI is configured

## AI Learning Materials (Google Gemini)

The app uses Google Gemini AI to analyze your tasks and suggest relevant learning resources.

### Setup

1. **Get a free API key**:
   - Go to https://aistudio.google.com/app/apikey
   - Sign in with your Google account
   - Click "Create API Key"
   - Copy the key

2. **Configure in the app**:
   - Open the app
   - Click the menu (⋮) → Settings
   - Paste your Gemini API key
   - Click "Save API Key"

   Or run the setup script:
   ```bash
   cd backend
   python setup_gemini.py
   ```

3. **Use the feature**:
   - Open any task detail screen
   - Click "Find Related Materials"
   - Gemini will analyze the task and suggest:
     - Key concepts to learn
     - Study tips
     - Video tutorials (with thumbnails)
     - Articles and reading materials
     - PDF documents

### Free Tier Limits
- 15 requests per minute
- 1 million tokens per minute
- More than enough for personal use!

## Notes

- **Credentials are encrypted** using AES and stored locally
- **SQLite** stores tasks and courses locally via `sqflite_common_ffi`
- The scraper extracts assignments from Moodle's upcoming events calendar
- The app supports both standard Moodle login and Office 365 / Microsoft SSO login

## Troubleshooting

**Login fails with timeout**:
- Verify your Moodle URL is correct (include `https://`)
- Check that your credentials work in a regular browser
- If your school uses Office 365 SSO, use the *Login with Office 365* button
- Some Moodle sites may have different login page structures

**No tasks showing**:
- The scraper looks for assignments in Moodle's calendar view
- Your Moodle site may have a different HTML structure
- Check the app debug console for scraping errors

**Office 365 login doesn't work**:
- Make sure you copy the correct `MoodleSession` cookie value
- The cookie expires; you may need to log in again when it does

## Next Steps

- [x] Install Flutter SDK
- [x] Run `flutter pub get` in `frontend/`
- [x] Test the app with `flutter run -d windows`
- [ ] Build the Windows installer with `build_installer.bat`
- [ ] Test with your school's Moodle URL
- [ ] Customize the scraper for your specific Moodle theme if needed
- [ ] Set up Codemagic for iOS builds when ready
