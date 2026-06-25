# Homework Tracker

A cross-platform desktop application that automatically syncs with **Moodle** (ITLA Virtual) to track assignments, deadlines, and grades. Features AI-powered study assistance, file uploads, quiz solving, and calendar visualization.

Built with **Flutter** (frontend) + **Python FastAPI** (backend scraper).

---

## Features

### 📋 Task Management
- **Auto-sync** with Moodle calendar — assignments appear automatically after login
- **Filters** by course, status (pending/completed/overdue), and date range
- **Calendar view** with color-coded markers (red = overdue, orange = due soon, green = completed)
- **Stats bar**: total tasks, completed, due soon, overdue counts
- **Week-only toggle** for focused views

### ✅ Completion Toggle
- Click to mark tasks done locally (instant)
- Background retry sync to Moodle (up to 5 attempts, 3s delay)
- Smart sync button in task detail to force-reconcile

### 📤 File Upload
- Upload homework files (PDF, DOC, DOCX, TXT, ZIP, RAR, JPG, PNG) directly to Moodle assignments
- Multi-step: draft upload → savesubmission → verification by re-scraping
- Progress indicators and status messages

### 📝 Quiz Support
- Fetch quiz questions from Moodle (multiple choice, checkbox, text input)
- Submit answers directly from the app
- View quiz grades and feedback (tracked locally)

### 🤖 AI-Powered Study Assistant (Gemini)
- **Key Concepts**: automatically extracted from assignment titles
- **Study Tips**: AI-generated suggestions
- **YouTube Videos**: real title extraction from `ytInitialData`
- **Article Suggestions**: curated educational links
- **Search Chips**: quick Google search queries
- Requires a free Google Gemini API key

### 🔐 Authentication
- **Remember Me**: saves credentials encrypted with AES-256
- **Office 365 SSO** auto-detection and cookie-based login flow
- **Session cookies** persisted for uninterrupted use
- **Credential management**: save, switch, delete saved accounts

### 🔔 Notifications
- Due-soon reminders
- Overdue task alerts
- Timezone-aware scheduling via `flutter_local_notifications`

### 🎨 UI/UX
- Material 3 design with light/dark/system theme toggle
- Responsive layout for desktop and mobile
- Pull-to-refresh for manual sync

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Desktop App                      │
│  ┌────────────┐  ┌──────────┐  ┌────────────┐             │
│  │   Screens  │  │ Providers│  │  Services   │             │
│  │  (8 views) │◄─┤ (Theme)  │◄─│ API Service │──HTTP────┐ │
│  └────────────┘  └──────────┘  │ Moodle     │  direct  │ │
│                                 │ Database   │ scraping │ │
│  ┌────────────┐  ┌──────────┐  │ AI/Gemini  │          │ │
│  │   Widgets  │  │  Models  │  │ Auth (AES) │          │ │
│  │  (2 files) │  │ (2 files)│  │ Notify     │          │ │
│  └────────────┘  └──────────┘  │ Logger     │          │ │
│                                └────────────┘          │ │
│  Local SQLite DB (sqflite) ◄───────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Python Backend (FastAPI :8000)                 │
│  ┌──────────┐  ┌──────────┐  ┌─────────────────────┐      │
│  │  main.py │  │ models.py│  │    scraper.py       │      │
│  │ (18 API) │─►│ (SQLAlch)│─►│ (Playwright auto)   │──►   │
│  └──────────┘  └──────────┘  │ toggleCompletion()   │MOODLE│
│  ┌──────────┐  ┌──────────┐  │ uploadFile()         │◄─────│
│  │auth.py   │  │scheduler │  │ getQuizQuestions()   │      │
│  │(Fernet)  │  │(30min)   │  │ scrapeAssignments()  │      │
│  └──────────┘  └──────────┘  └─────────────────────┘      │
│  ┌──────────────────────────────────────────────────┐      │
│  │           ai_materials.py (Gemini API)           │      │
│  └──────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Choice |
|---|---|
| **Scraping approach** | Direct Flutter HTTP (`dart:io`) for desktop; Python Playwright as fallback |
| **State management** | Provider + ChangeNotifier |
| **Local storage** | SQLite via `sqflite_common_ffi` (desktop-compatible) |
| **Credential encryption** | AES-256 via `encrypt` package, key stored in app support dir |
| **File upload** | Moodle repository API (webservice `upload_file`) + `savesubmission` |
| **Quiz grades** | Local DB tracking only (not scraped) |
| **Notifications** | `flutter_local_notifications` + `timezone` for scheduled alerts |

---

## Screenshots

| Screen | Description |
|---|---|
| **Login** | Moodle URL, username/password fields, Office 365 SSO button, Remember Me with saved credentials dropdown |
| **Dashboard** | 3 tabs (Pending/Completed/Overdue), stats bar, week toggle, calendar nav |
| **Calendar** | Monthly view with color-coded task dots, day-selection task list |
| **Task Detail** | Full info, submission status, AI materials button, upload/quiz/open buttons |
| **File Upload** | File picker, progress bar, status messages |
| **Quiz Screen** | Questions with radio/checkbox/text inputs, submit button |
| **AI Materials** | Key concepts, study tips, YouTube thumbnails, article links |
| **Settings** | Gemini API key configuration, status indicator |

---

## Getting Started

### Prerequisites

- **Flutter SDK** (3.0+): [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Python 3.10+** (for backend): [Download Python](https://www.python.org/downloads/)
- **Moodle account** (e.g., ITLA Virtual at https://aulavirtual.itla.edu.do)

### Installation

#### Option 1: Pre-built Installer (Windows)

1. Download `HomeworkTracker_Setup_v1.0.0.exe` from the [releases page](https://github.com/oswaldhz/homework-tracker/releases)
2. Run the installer
3. A desktop shortcut will be created

> **Note**: Windows SmartScreen may show a warning — click "More info" → "Run anyway" (unsigned binary).

#### Option 2: Build from Source

**Backend setup:**

```bash
cd backend
python -m venv venv
venv\Scripts\activate      # Windows
# source venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
playwright install chromium
python main.py             # Starts on http://localhost:8000
```

**Frontend setup:**

```bash
cd frontend
flutter pub get
flutter run -d windows     # Or -d chrome, -d android, etc.
```

> The Flutter app expects the backend at `http://localhost:8000`. Set `BACKEND_URL` environment variable to override.

### Building the Installer

```bash
# 1. Build Flutter Windows release
cd frontend
flutter build windows --release

# 2. Compile Inno Setup installer
cd ..
build_installer.bat        # Requires Inno Setup installed
```

---

## Usage

### First Login
1. Launch the app
2. Enter your Moodle instance URL (e.g., `https://aulavirtual.itla.edu.do`)
3. Enter your username and password
4. Optionally check **Remember Me** to save credentials encrypted locally
5. If your Moodle uses Office 365 SSO, the app auto-detects and redirects through O365 login

### Managing Tasks
- **Dashboard** shows all pending tasks from Moodle
- Tap a **task card** to see details
- **Check the box** on a task card to toggle completion (synced to Moodle in background)
- Use the **filter icon** to filter by course, status, or date
- **Week toggle** restricts view to current week's tasks

### Uploading Files
1. Open a task's detail screen
2. Tap **"Upload Homework"**
3. Select a file from your computer
4. Wait for the progress indicator — the app uploads to Moodle and verifies

### Using AI Features
1. Go to **Settings** → tap **"Configure Gemini API"**
2. Obtain a free API key from [aistudio.google.com](https://aistudio.google.com/apikey)
3. Paste the key and save
4. On any task, tap **"Find Related Materials"** to get AI-generated study content

---

## Project Structure

```
homework-tracker/
├── frontend/                  # Flutter desktop app
│   ├── lib/
│   │   ├── main.dart          # App entry point
│   │   ├── models/            # Task, TaskFilter data classes
│   │   ├── providers/         # ThemeProvider (light/dark)
│   │   ├── screens/           # 8 screens (login, dashboard, detail, etc.)
│   │   ├── services/          # 7 services (API, Moodle, DB, AI, Auth, etc.)
│   │   └── widgets/           # TaskCard, FilterBottomSheet
│   ├── test/                  # Widget tests
│   └── pubspec.yaml           # Dependencies
├── backend/                   # Python FastAPI server
│   ├── main.py                # 18 REST API endpoints
│   ├── scraper.py             # Playwright Moodle automation
│   ├── ai_materials.py        # Gemini AI integration
│   ├── models.py              # SQLAlchemy ORM models
│   ├── auth.py                # Fernet encryption
│   ├── scheduler.py           # Background refresh (30 min)
│   └── requirements.txt       # Python dependencies
├── installer/                 # Inno Setup packaging
│   ├── installer.iss          # Installer script
│   └── installer_output/      # Built .exe
├── build_installer.bat        # One-click build script
└── README.md
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter 3.x, Dart |
| **State** | Provider + ChangeNotifier |
| **Backend** | Python 3.10+, FastAPI, Uvicorn |
| **Scraping** | Playwright (Chromium) |
| **Database (app)** | SQLite via sqflite_common_ffi |
| **Database (backend)** | SQLite via SQLAlchemy |
| **AI** | Google Gemini API (gemini-2.5-flash) |
| **Encryption** | AES-256 (encrypt package) + Fernet (Python) |
| **Notifications** | flutter_local_notifications |
| **Calendar** | table_calendar |
| **Packaging** | Inno Setup (Windows) |

---

## License

This project is for educational use. All third-party tools and libraries are used under their respective licenses.

---

## Acknowledgments

- Built for ITLA (Instituto Tecnológico de Las Américas) students
- Uses the Google Gemini API for AI features
- Uses Playwright for browser automation
