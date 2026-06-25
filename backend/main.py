from fastapi import FastAPI, Depends, HTTPException, BackgroundTasks, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional, List, Dict
import shutil
from pathlib import Path

from models import get_db, Task, Course, Credential
from auth import encrypt_value, decrypt_value
from scraper import scrape_moodle_assignments, toggle_moodle_completion, upload_file_to_moodle, get_quiz_questions, submit_quiz_answers, scrape_moodle_course_resources
from scheduler import start_scheduler, stop_scheduler
from ai_materials import gemini_finder
from config import UPLOADS_DIR

app = FastAPI(title="Homework Tracker API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class LoginRequest(BaseModel):
    moodle_url: str
    username: str
    password: str

class TaskResponse(BaseModel):
    id: int
    title: str
    course_name: str
    due_date: Optional[datetime]
    status: str
    is_completed: bool
    url: Optional[str]
    description: Optional[str]

    class Config:
        from_attributes = True

@app.on_event("startup")
def startup():
    start_scheduler()

@app.on_event("shutdown")
def shutdown():
    stop_scheduler()

@app.post("/api/login")
def login(req: LoginRequest, db: Session = Depends(get_db)):
    cred = db.query(Credential).first()
    if cred:
        cred.moodle_url = req.moodle_url
        cred.encrypted_username = encrypt_value(req.username)
        cred.encrypted_password = encrypt_value(req.password)
    else:
        cred = Credential(
            moodle_url=req.moodle_url,
            encrypted_username=encrypt_value(req.username),
            encrypted_password=encrypt_value(req.password)
        )
        db.add(cred)
    db.commit()
    
    try:
        result = scrape_moodle_assignments(req.moodle_url, req.username, req.password)
        return {"success": True, "message": "Login successful", "tasks_found": result["count"]}
    except Exception as e:
        error_msg = str(e)
        if "playwright" in error_msg.lower() or "browser" in error_msg.lower() or "executable" in error_msg.lower():
            raise HTTPException(status_code=500, detail="Browser engine not available. Please reinstall the application.")
        elif "timeout" in error_msg.lower():
            raise HTTPException(status_code=408, detail="Connection timed out. Check your internet and Moodle URL.")
        elif "login failed" in error_msg.lower() or "credentials" in error_msg.lower() or "login/index.php" in error_msg.lower():
            raise HTTPException(status_code=401, detail="Invalid username or password.")
        elif "connection" in error_msg.lower() or "network" in error_msg.lower() or "resolve" in error_msg.lower():
            raise HTTPException(status_code=503, detail="Cannot reach Moodle server. Check the URL and your connection.")
        else:
            raise HTTPException(status_code=500, detail=f"Login error: {error_msg}")

@app.get("/api/tasks", response_model=List[TaskResponse])
def get_tasks(
    status: Optional[str] = None,
    course_id: Optional[int] = None,
    week: Optional[bool] = False,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    db: Session = Depends(get_db)
):
    query = db.query(Task)
    
    if status:
        if status == 'pending':
            query = query.filter(Task.is_completed == False, Task.due_date >= datetime.now())
        elif status == 'completed':
            query = query.filter(Task.is_completed == True)
        elif status == 'overdue':
            query = query.filter(Task.due_date < datetime.now(), Task.is_completed == False)
    
    if course_id:
        query = query.filter(Task.course_id == course_id)
    
    if week:
        now = datetime.now()
        start = now - timedelta(days=now.weekday())
        start = start.replace(hour=0, minute=0, second=0, microsecond=0)
        end = start + timedelta(days=7)
        end = end.replace(hour=0, minute=0, second=0, microsecond=0)
        query = query.filter(Task.due_date >= start, Task.due_date < end)
    
    if start_date:
        try:
            start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
            query = query.filter(Task.due_date >= start_dt)
        except:
            pass
    
    if end_date:
        try:
            end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
            query = query.filter(Task.due_date <= end_dt)
        except:
            pass
    
    tasks = query.order_by(Task.due_date).all()
    
    result = []
    for task in tasks:
        course = db.query(Course).filter(Course.id == task.course_id).first()
        result.append(TaskResponse(
            id=task.id,
            title=task.title,
            course_name=course.name if course else "Unknown",
            due_date=task.due_date,
            status=task.status,
            is_completed=task.is_completed,
            url=task.url,
            description=task.description
        ))
    
    return result

@app.patch("/api/tasks/{task_id}/complete")
def toggle_complete(task_id: int, db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    task.is_completed = not task.is_completed
    db.commit()
    
    return {"id": task.id, "is_completed": task.is_completed}

@app.post("/api/tasks/{task_id}/sync-completion")
def sync_completion_to_moodle(task_id: int, db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    if not task.url:
        raise HTTPException(status_code=400, detail="Task has no URL to sync")
    
    cred = db.query(Credential).first()
    if not cred:
        raise HTTPException(status_code=400, detail="No credentials saved. Login first.")
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    try:
        result = toggle_moodle_completion(moodle_url, username, password, task.url, task.is_completed)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/refresh")
def refresh_tasks(background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    cred = db.query(Credential).first()
    if not cred:
        raise HTTPException(status_code=400, detail="No credentials saved. Login first.")
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    try:
        result = scrape_moodle_assignments(moodle_url, username, password)
        return {"success": True, "tasks_updated": result["count"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/courses")
def get_courses(db: Session = Depends(get_db)):
    courses = db.query(Course).all()
    return [{"id": c.id, "name": c.name, "short_name": c.short_name} for c in courses]

@app.get("/api/stats")
def get_stats(db: Session = Depends(get_db)):
    total = db.query(Task).count()
    completed = db.query(Task).filter(Task.is_completed == True).count()
    
    now = datetime.now()
    soon = now + timedelta(hours=24)
    due_soon = db.query(Task).filter(
        Task.due_date.between(now, soon),
        Task.is_completed == False
    ).count()
    
    overdue = db.query(Task).filter(
        Task.due_date < now,
        Task.is_completed == False
    ).count()
    
    return {
        "total": total,
        "completed": completed,
        "pending": total - completed,
        "due_soon": due_soon,
        "overdue": overdue
    }

@app.get("/api/health")
def health_check():
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            browser.close()
        return {"status": "ok", "playwright": True}
    except Exception as e:
        return {"status": "degraded", "playwright": False, "error": str(e)}

@app.get("/api/tasks/{task_id}/materials")
def get_task_materials(task_id: int, db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    course = db.query(Course).filter(Course.id == task.course_id).first()
    course_name = course.name if course else ""
    
    materials = {
        "videos": [],
        "articles": [],
        "pdfs": [],
        "moodle_resources": [],
        "key_concepts": [],
        "study_tips": "",
        "ai_generated": False
    }
    
    try:
        ai_materials = gemini_finder.find_materials(
            task_title=task.title,
            task_description=task.description or "",
            course_name=course_name
        )
        materials.update(ai_materials)
    except Exception as e:
        print(f"AI materials error: {e}")
    
    try:
        cred = db.query(Credential).first()
        if cred and course and course.url:
            moodle_url = cred.moodle_url
            username = decrypt_value(cred.encrypted_username)
            password = decrypt_value(cred.encrypted_password)
            
            moodle_resources = scrape_moodle_course_resources(moodle_url, username, password, course.url)
            if moodle_resources.get("success"):
                materials["moodle_resources"] = moodle_resources.get("resources", [])
    except Exception as e:
        print(f"Moodle resources error: {e}")
    
    return materials

class ApiKeyRequest(BaseModel):
    api_key: str

@app.post("/api/set-gemini-key")
def set_gemini_key(req: ApiKeyRequest):
    try:
        gemini_finder.set_api_key(req.api_key)
        return {"success": True, "message": "Gemini API key configured successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error setting API key: {str(e)}")

@app.get("/api/gemini-status")
def get_gemini_status():
    return {"configured": gemini_finder.available}

@app.post("/api/tasks/{task_id}/upload")
def upload_homework(task_id: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    if not task.url:
        raise HTTPException(status_code=400, detail="Task has no URL to upload to")
    
    cred = db.query(Credential).first()
    if not cred:
        raise HTTPException(status_code=400, detail="No credentials saved. Login first.")
    
    UPLOADS_DIR.mkdir(exist_ok=True)
    
    file_path = UPLOADS_DIR / file.filename
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    try:
        result = upload_file_to_moodle(moodle_url, username, password, task.url, str(file_path))
        if not result.get("success"):
            raise HTTPException(status_code=400, detail=result.get("message", "Upload failed"))
        return result
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if file_path.exists():
            file_path.unlink()

@app.get("/api/tasks/{task_id}/quiz")
def get_quiz(task_id: int, db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    if not task.url:
        raise HTTPException(status_code=400, detail="Task has no URL")
    
    cred = db.query(Credential).first()
    if not cred:
        raise HTTPException(status_code=400, detail="No credentials saved. Login first.")
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    try:
        result = get_quiz_questions(moodle_url, username, password, task.url)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class QuizAnswerRequest(BaseModel):
    answers: Dict[str, str]

@app.post("/api/tasks/{task_id}/quiz/submit")
def submit_quiz(task_id: int, req: QuizAnswerRequest, db: Session = Depends(get_db)):
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    
    if not task.url:
        raise HTTPException(status_code=400, detail="Task has no URL")
    
    cred = db.query(Credential).first()
    if not cred:
        raise HTTPException(status_code=400, detail="No credentials saved. Login first.")
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    try:
        result = submit_quiz_answers(moodle_url, username, password, task.url, req.answers)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import sys
    import os

    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w")

    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="warning")
