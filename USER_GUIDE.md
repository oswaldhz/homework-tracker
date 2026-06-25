# Homework Tracker - User Guide

## 🎯 Overview

Your Homework Tracker is a cross-platform app that connects to your Moodle virtual classroom (ITLA) and helps you manage assignments, quizzes, and learning materials.

---

## 🔑 Setting Up Gemini AI (Required for AI Features)

The AI feature uses Google Gemini to find relevant learning materials for your homework.

### Step 1: Get Your Free API Key

1. Go to **https://aistudio.google.com/app/apikey**
2. Sign in with your Google account
3. Click **"Create API Key"**
4. Copy the key (it looks like: `AIzaSy...`)

### Step 2: Add It to the App

**Option A: Through the App (Easiest)**
1. Open the app
2. Click the **menu (⋮)** in the top right
3. Click **"Settings"**
4. Paste your API key
5. Click **"Save API Key"**
6. You'll see a green "Active" badge when it's working

**Option B: Manual Setup**
Create a file at:
```
C:\Users\oswal\Desktop\homework-tracker\backend\.gemini_api_key
```
Paste your API key in it (no quotes, just the key).

### Step 3: Verify It's Working

After saving, open any task and click **"Find Related Materials"**. The AI will analyze your homework and suggest videos, articles, and PDFs.

---

## 📱 App Features

### 1. **Task Dashboard**
- View all your assignments in one place
- Filter by: All tasks, This week, Pending, Completed, Overdue
- Tasks show course name, due date, and status
- Color-coded: 🔴 Overdue, 🟠 Due soon, 🟢 Completed

### 2. **Task Details**
Click any task to see:
- Full description
- Course information
- Due date
- Action buttons (see below)

### 3. **Smart Action Buttons**
The app automatically shows relevant buttons based on task type:

**For Assignments (file uploads):**
- 📤 **Upload Homework** - Upload files directly to Moodle
- 🤖 **Find Related Materials** - AI-powered learning resources

**For Quizzes:**
- 📝 **Answer Quiz** - Answer quiz questions inside the app
- 🤖 **Find Related Materials** - AI-powered learning resources

**For All Tasks:**
- ✅ **Mark as Complete** - Toggle completion (syncs to Moodle!)
- 🔗 **Open in Moodle** - Open the task in your browser

### 4. **File Upload Feature**
For assignments that accept file uploads:
1. Click **"Upload Homework"**
2. Select a file (PDF, DOC, DOCX, TXT, ZIP, RAR, JPG, PNG)
3. Click **"Upload to Moodle"**
4. File is submitted directly to your Moodle assignment

### 5. **Quiz Feature**
For quizzes and questionnaires:
1. Click **"Answer Quiz"**
2. Answer multiple choice, checkbox, or text questions
3. Click **"Submit Quiz"**
4. Answers are submitted to Moodle

### 6. **AI Learning Materials**
Click **"Find Related Materials"** to get:
- 🎥 **Video tutorials** from YouTube
- 📰 **Articles** from the web
- 📄 **PDF documents**
- 📚 **Your course materials** from Moodle
- 💡 **Key concepts** to focus on
- 📝 **Study tips**

The AI analyzes your task and finds the best resources to help you complete it.

### 7. **Calendar View**
- See all tasks in a calendar layout
- Tasks appear on their due dates
- Click any day to see tasks for that date
- Color-coded by status

### 8. **Dark Mode**
- Click the sun/moon icon to toggle
- Saves your preference

### 9. **Notifications**
- Automatic alerts for tasks due within 24 hours
- Works on mobile (iOS/Android)
- Desktop notifications on Windows

---

## 🔄 How It Works

### Backend (Python)
- Runs on your PC at `http://localhost:8000`
- Uses Playwright to automate Moodle interactions
- Stores data in SQLite database
- Encrypts your credentials
- Auto-refreshes every 30 minutes

### Frontend (Flutter)
- Cross-platform app (Windows + iOS)
- Communicates with backend via API
- Beautiful Material Design UI

### Moodle Integration
- Logs in automatically using saved credentials
- Scrapes assignments from calendar
- Syncs completion status
- Uploads files to assignments
- Submits quiz answers

---

## 🚀 Starting the App

### 1. Start the Backend
```bash
cd C:\Users\oswal\Desktop\homework-tracker
start_backend.bat
```
Or manually:
```bash
cd C:\Users\oswal\Desktop\homework-tracker\backend
venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Start the Frontend
```bash
cd C:\Users\oswal\Desktop\homework-tracker\frontend
C:\flutter\bin\flutter.bat run -d windows
```

---

## 📋 API Endpoints

All endpoints are available at `http://localhost:8000/docs`

- `POST /api/login` - Login to Moodle
- `GET /api/tasks` - Get all tasks
- `PATCH /api/tasks/{id}/complete` - Toggle completion
- `POST /api/tasks/{id}/sync-completion` - Sync to Moodle
- `POST /api/tasks/{id}/upload` - Upload file
- `GET /api/tasks/{id}/quiz` - Get quiz questions
- `POST /api/tasks/{id}/quiz/submit` - Submit quiz
- `GET /api/tasks/{id}/materials` - Get AI materials
- `POST /api/set-gemini-key` - Set Gemini API key
- `GET /api/gemini-status` - Check AI status

---

## 🔒 Security

- Credentials are encrypted using Fernet encryption
- Stored locally in encrypted format
- Never sent to external services (except Moodle)
- API key stored locally in `.gemini_api_key` file

---

## 🐛 Troubleshooting

### Backend won't start
- Make sure port 8000 is not in use
- Check that `venv` folder exists in `backend/`

### Login fails
- Verify your Moodle URL is correct
- Check that your credentials work in a browser
- Some Moodle sites may have different login structures

### AI features not working
- Make sure you set up your Gemini API key
- Check Settings to see if it shows "Active"
- Try restarting the backend

### File upload fails
- Make sure the task is an assignment (not a quiz or survey)
- Check file size limits on your Moodle site
- Verify the assignment accepts file uploads

### Quiz doesn't load
- Make sure the task is a quiz
- Some quiz types may not be supported yet
- Try opening the quiz in Moodle directly

---

## 📞 Support

If you encounter issues:
1. Check the backend console for errors
2. Check the app console (if running in debug mode)
3. Verify your Moodle credentials are correct
4. Make sure the backend is running

---

## 🎓 Tips

- **Set up Gemini API first** - The AI features are the most powerful
- **Use the calendar view** - Great for seeing what's due when
- **Mark tasks complete in the app** - It syncs to Moodle automatically
- **Upload files early** - Don't wait until the last minute
- **Use AI materials** - They can help you understand the topics better

---

## 🔄 Updates

The app is actively being developed. New features coming soon:
- Moodle content search (find materials within your courses)
- More quiz types support
- Better file upload progress indicators
- Offline mode
- iOS app release

---

Enjoy your Homework Tracker! 🎉
