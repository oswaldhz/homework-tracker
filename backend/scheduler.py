from apscheduler.schedulers.background import BackgroundScheduler
from datetime import datetime, timedelta
from models import SessionLocal, Task, Credential
from auth import decrypt_value
from scraper import scrape_moodle_assignments

scheduler = BackgroundScheduler()

def scheduled_scrape():
    db = SessionLocal()
    try:
        cred = db.query(Credential).first()
        if not cred:
            return
        
        moodle_url = cred.moodle_url
        username = decrypt_value(cred.encrypted_username)
        password = decrypt_value(cred.encrypted_password)
        
        scrape_moodle_assignments(moodle_url, username, password)
        
        check_due_soon_tasks(db)
    except Exception as e:
        print(f"Scheduled scrape error: {e}")
    finally:
        db.close()

def check_due_soon_tasks(db):
    now = datetime.now()
    soon = now + timedelta(hours=24)
    
    due_soon = db.query(Task).filter(
        Task.due_date.between(now, soon),
        Task.is_completed == False
    ).all()
    
    for task in due_soon:
        print(f"NOTIFICATION: '{task.title}' is due soon ({task.due_date})")

def start_scheduler():
    scheduler.add_job(scheduled_scrape, 'interval', minutes=30, id='moodle_scrape')
    scheduler.start()

def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown()
