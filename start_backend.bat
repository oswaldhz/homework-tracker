@echo off
echo Starting Homework Tracker Backend...
cd /d "%~dp0backend"
call venv\Scripts\activate
echo Server running at http://localhost:8000
echo API docs at http://localhost:8000/docs
start http://localhost:8000/docs
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pause
