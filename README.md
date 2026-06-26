# 📚 Homework Tracker

> **Never miss a deadline again.** Automatically syncs with **Moodle**-based classrooms to keep you on top of every assignment, quiz, and due date.

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Python-3.10+-3776AB?logo=python" alt="Python">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Android%20%7C%20Linux-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/status-active-success" alt="Status">
</p>

---

## 🎯 The Problem

Moodle is great for teachers, but **students get lost** — assignments spread across different courses, deadlines sneak up, and there's no unified "what's due?" view. You end up logging into Moodle 5 times a day, clicking through each course, writing deadlines on sticky notes...

## 💡 The Solution

**Homework Tracker** is a desktop app that pulls all your Moodle assignments into one clean dashboard — with **automatic sync**, **one-click completion toggling**, **file uploads**, **quiz support**, and **AI-powered study materials** for each task.

---

## ✨ Features at a Glance

<p align="center">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&pause=1000&color=00BFFF&center=true&vCenter=true&width=600&lines=Auto-sync+with+Moodle+calendar;AI-powered+study+materials;File+uploads+%2B+quiz+support;Smart+notifications+%2B+dark+mode;Built+with+Flutter+%2B+Python+FastAPI" alt="Typing animation">
</p>

### 📋 Task Management
| Feature | Description |
|---|---|
| 🔄 **Auto-sync** | Assignments appear automatically after login — no manual importing |
| 🎯 **Filters** | By course, status (pending/completed/overdue), or date range |
| 📅 **Calendar View** | Color-coded monthly view — 🔴 overdue, 🟠 due soon, 🟢 completed |
| 📊 **Stats Bar** | Total tasks, completed ✅, due soon ⏰, overdue 🚨 counts |
| 📆 **Week Toggle** | Focus on just this week's work |

### ✅ Completion Toggle
- ⚡ **Instant local toggle** — check the box, it's done immediately
- 🔄 **Background sync** to Moodle with retry (up to 5 attempts, 3s delay)
- 🔁 **Smart sync button** in task detail to force-reconcile

### 📤 File Upload
- Upload files (PDF, DOC, DOCX, TXT, ZIP, RAR, JPG, PNG) directly to Moodle
- 🔄 Multi-step flow: draft upload → `savesubmission` → verification by re-scraping
- 📊 Progress indicators and status messages

### 📝 Quiz Support
- Fetch quiz questions from Moodle (multiple choice, checkbox, text input)
- ✏️ Submit answers directly from the app
- 🏆 View quiz grades and feedback (tracked locally in your device)

### 🤖 AI-Powered Study Assistant (Gemini)
| Feature | Description |
|---|---|
| 🧠 **Key Concepts** | Automatically extracted from assignment titles |
| 💡 **Study Tips** | AI-generated suggestions tailored to the task |
| 🎬 **YouTube Videos** | Real title extraction from `ytInitialData` |
| 📰 **Article Suggestions** | Curated educational links |
| 🔍 **Search Chips** | Quick Google search queries for deeper learning |

> Requires a free [Google Gemini API key](https://aistudio.google.com/apikey) — configure in Settings.

### 🔐 Authentication & Security
- 🔑 **Remember Me** — credentials encrypted with AES-256
- 🏢 **Office 365 SSO** auto-detection + cookie-based login flow
- 🍪 **Session cookies** persisted for uninterrupted use
- 👥 **Credential management** — save, switch, and delete accounts

### 🔔 Smart Notifications
- ⏰ **Due-soon reminders**
- 🚨 **Overdue task alerts**
- 🌍 **Timezone-aware** scheduling

### 🎨 UI/UX
- 🌓 **Material 3** with light/dark/system theme toggle
- 📱 **Responsive** layout for desktop and mobile
- 🔄 **Pull-to-refresh** for manual sync

---

## 🏗️ Architecture

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

### 🔑 Key Design Decisions

| Decision | Choice | Why |
|---|---|---|
| 🕸️ **Scraping** | Direct Flutter HTTP (`dart:io`) | Faster, no backend dependency for simple ops |
| 🗄️ **State** | Provider + ChangeNotifier | Lightweight, well-supported by Flutter |
| 💾 **Local storage** | SQLite via `sqflite_common_ffi` | Desktop-compatible, offline-first |
| 🔒 **Encryption** | AES-256 + Fernet | Industry-standard credential protection |
| 📤 **File upload** | Moodle repository API | Reliable `upload_file` + `savesubmission` flow |
| 🏆 **Quiz grades** | Local DB tracking | Privacy-first, no scraping of grades |
| 🔔 **Notifications** | `flutter_local_notifications` | Cross-platform scheduled alerts |

---

## 🚀 Getting Started

### 📋 Prerequisites

| Requirement | Version | Link |
|---|---|---|
| 🎯 Flutter SDK | 3.0+ | [Install Flutter](https://docs.flutter.dev/get-started/install) |
| 🐍 Python | 3.10+ | [Download Python](https://www.python.org/downloads/) |
| 🎓 Moodle account | — | Your school's Moodle instance |

### 💾 Installation

#### Option 1: 📦 Pre-built Installer (Windows) — <ins>**Recommended**</ins>

1. 🚀 Download [`HomeworkTracker_Setup_v1.0.0.exe`](https://github.com/oswaldhz/homework-tracker/releases/latest) from the releases page
2. ▶️ Run the installer
3. 🖥️ A desktop shortcut will be created — double-click to launch!

> ⚠️ **Windows SmartScreen** may show a warning since the binary is unsigned. Click **"More info" → "Run anyway"** to proceed.

#### Option 2: 🔧 Build from Source

**🐍 Backend:**

```bash
cd backend
python -m venv venv
venv\Scripts\activate      # Windows
# source venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
playwright install chromium
python main.py             # Starts on http://localhost:8000
```

**🎯 Frontend:**

```bash
cd frontend
flutter pub get
flutter run -d windows     # or -d chrome, -d android, etc.
```

> 💡 The Flutter app expects the backend at `http://localhost:8000`. Override with the `BACKEND_URL` env variable.

### 🏗️ Building the Installer

```bash
# 1. Build Flutter Windows release
cd frontend
flutter build windows --release

# 2. Compile Inno Setup installer
cd ..
build_installer.bat        # Requires Inno Setup 6+
```

---

## 📖 Usage Guide

### 🔐 First Login

| Step | Action |
|---|---|
| 1️⃣ | Launch the app |
| 2️⃣ | Enter your Moodle URL  |
| 3️⃣ | Type your username and password |
| 4️⃣ | ✅ Check **Remember Me** to save credentials (encrypted) |
| 5️⃣ | 🔄 If your school uses **Office 365 SSO**, the app auto-detects and redirects |

### 📋 Managing Tasks

| Action | How |
|---|---|
| 👀 **View tasks** | Dashboard shows all pending assignments |
| 📄 **See details** | Tap any task card |
| ✅ **Mark done** | Check the box — instant locally, synced to Moodle in background |
| 🎯 **Filter** | Use the filter icon (course, status, date) |
| 📆 **This week** | Toggle week-view for focused work |

### 📤 Uploading Homework

```
1. Open a task → 2. Tap "Upload Homework" →
3. Pick a file → 4. Wait for verification ✓
```

### 🤖 Using AI Features

```
1. Settings → "Configure Gemini API" →
2. Get free key from aistudio.google.com →
3. Paste & save →
4. On any task, tap "Find Related Materials"
```

---

## 📁 Project Structure

```
homework-tracker/
├── frontend/                    # 🎯 Flutter desktop app
│   ├── lib/
│   │   ├── main.dart           # 🚀 App entry point
│   │   ├── models/             # 📊 Task, TaskFilter data classes
│   │   ├── providers/          # 🎨 ThemeProvider (light/dark)
│   │   ├── screens/            # 🖥️ 8 screens (login, dashboard, detail...)
│   │   ├── services/           # ⚙️ 7 services (API, Moodle, DB, AI...)
│   │   └── widgets/            # 🧩 TaskCard, FilterBottomSheet
│   ├── test/                   # ✅ Widget tests
│   └── pubspec.yaml            # 📦 Dependencies
├── backend/                     # 🐍 Python FastAPI server
│   ├── main.py                 # 🌐 18 REST API endpoints
│   ├── scraper.py              # 🕷️ Playwright Moodle automation
│   ├── ai_materials.py         # 🤖 Gemini AI integration
│   ├── models.py               # 🗄️ SQLAlchemy ORM models
│   ├── auth.py                 # 🔒 Fernet encryption
│   ├── scheduler.py            # ⏰ Background refresh (30 min)
│   └── requirements.txt        # 📋 Python dependencies
├── installer/                   # 📦 Inno Setup packaging
│   ├── installer.iss           # ⚙️ Installer script
│   └── installer_output/       # 📀 Built .exe
├── build_installer.bat         # 🔨 One-click build script
└── README.md                   # 📖 This file
```

---

## 🛠️ Tech Stack

| Layer | Technology | Badge |
|---|---|---|
| 🎯 **Frontend** | Flutter 3.x, Dart | ![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter) |
| 🗄️ **State** | Provider + ChangeNotifier | ![Provider](https://img.shields.io/badge/Provider-6.x-blue) |
| 🐍 **Backend** | Python 3.10+, FastAPI, Uvicorn | ![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi) |
| 🕷️ **Scraping** | Playwright (Chromium) | ![Playwright](https://img.shields.io/badge/Playwright-45ba4b?logo=playwright) |
| 💾 **App DB** | SQLite via sqflite_common_ffi | ![SQLite](https://img.shields.io/badge/SQLite-003B57?logo=sqlite) |
| 🗄️ **Backend DB** | SQLite via SQLAlchemy | ![SQLAlchemy](https://img.shields.io/badge/SQLAlchemy-red) |
| 🤖 **AI** | Google Gemini 2.5 Flash | ![Gemini](https://img.shields.io/badge/Gemini-8E75B2?logo=google) |
| 🔒 **Encryption** | AES-256 + Fernet | ![Encryption](https://img.shields.io/badge/AES--256-secure-green) |
| 🔔 **Notifications** | flutter_local_notifications | ![Notif](https://img.shields.io/badge/Notifications-local-blue) |
| 📅 **Calendar** | table_calendar | ![Cal](https://img.shields.io/badge/Calendar-table--calendar-orange) |
| 📦 **Packaging** | Inno Setup (Windows) | ![Inno](https://img.shields.io/badge/Inno%20Setup-6.x-blue) |

---

## 📄 License

This project is for **educational use** — built by students, for students. 📚

All third-party tools and libraries are used under their respective licenses.

---

## 🙏 Acknowledgments

| | |
|---|---|
| 🏫 **ITLA** | Instituto Tecnológico de Las Américas — the inspiration for this project |
| 🤖 **Gemini API** | Google's AI for generating study materials |
| 🕷️ **Playwright** | Microsoft's browser automation framework |
| 🎯 **Flutter** | Google's UI toolkit for cross-platform apps |
| 🐍 **FastAPI** | Modern Python web framework for the backend |

---

<p align="center">
  <b>⭐ Star this repo if you find it useful! ⭐</b><br>
  <sub>Made with ❤️ for students everywhere</sub>
</p>

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&height=100&section=footer" alt="Footer wave">
</p>
