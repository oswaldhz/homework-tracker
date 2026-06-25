from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential
from auth import decrypt_value
import os

def debug_moodle():
    db = SessionLocal()
    cred = db.query(Credential).first()
    if not cred:
        print("No credentials found. Login first via the app.")
        return
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    print(f"Moodle URL: {moodle_url}")
    print(f"Username: {username}")
    
    screenshot_dir = os.path.dirname(os.path.abspath(__file__))
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1920, "height": 1080})
        page = context.new_page()
        
        try:
            print("\n[1] Navigating to login page...")
            login_url = moodle_url.rstrip("/") + "/login/index.php"
            page.goto(login_url, timeout=30000)
            page.screenshot(path=os.path.join(screenshot_dir, "debug_01_login_page.png"))
            print("    Saved: debug_01_login_page.png")
            
            print("[2] Filling credentials and logging in...")
            page.fill('input[name="username"]', username)
            page.fill('input[name="password"]', password)
            page.click('#loginbtn')
            page.wait_for_load_state("networkidle", timeout=15000)
            page.screenshot(path=os.path.join(screenshot_dir, "debug_02_after_login.png"))
            print(f"    Current URL: {page.url}")
            print("    Saved: debug_02_after_login.png")
            
            print("[3] Navigating to upcoming calendar...")
            page.goto(f"{moodle_url.rstrip('/')}/calendar/view.php?view=upcoming", timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.screenshot(path=os.path.join(screenshot_dir, "debug_03_calendar_upcoming.png"), full_page=True)
            print(f"    Current URL: {page.url}")
            print("    Saved: debug_03_calendar_upcoming.png")
            
            print("[4] Extracting calendar HTML structure...")
            calendar_html = page.evaluate("""() => {
                const cal = document.querySelector('.maincalendar') || document.querySelector('#calendar') || document.querySelector('[data-region="calendar"]');
                return cal ? cal.innerHTML : 'NO CALENDAR FOUND';
            }""")
            
            with open(os.path.join(screenshot_dir, "debug_04_calendar_html.txt"), "w", encoding="utf-8") as f:
                f.write(calendar_html[:50000])
            print("    Saved: debug_04_calendar_html.txt")
            
            print("[5] Navigating to dashboard/my page...")
            page.goto(f"{moodle_url.rstrip('/')}/my/", timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.screenshot(path=os.path.join(screenshot_dir, "debug_05_dashboard.png"), full_page=True)
            print(f"    Current URL: {page.url}")
            print("    Saved: debug_05_dashboard.png")
            
            print("[6] Extracting dashboard timeline HTML...")
            timeline_html = page.evaluate("""() => {
                const timeline = document.querySelector('[data-region="timeline"]') || document.querySelector('.block_timeline') || document.querySelector('.dashboard-card');
                return timeline ? timeline.innerHTML : 'NO TIMELINE FOUND';
            }""")
            
            with open(os.path.join(screenshot_dir, "debug_06_timeline_html.txt"), "w", encoding="utf-8") as f:
                f.write(timeline_html[:50000])
            print("    Saved: debug_06_timeline_html.txt")
            
            print("[7] Navigating to course list...")
            page.goto(f"{moodle_url.rstrip('/')}/my/courses.php", timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.screenshot(path=os.path.join(screenshot_dir, "debug_07_courses.png"), full_page=True)
            print(f"    Current URL: {page.url}")
            print("    Saved: debug_07_courses.png")
            
            print("[8] Extracting course list HTML...")
            courses_html = page.evaluate("""() => {
                const courses = document.querySelector('[data-region="courses-view"]') || document.querySelector('.course-listitem') || document.querySelector('.card-grid');
                return courses ? courses.innerHTML : 'NO COURSES FOUND';
            }""")
            
            with open(os.path.join(screenshot_dir, "debug_08_courses_html.txt"), "w", encoding="utf-8") as f:
                f.write(courses_html[:50000])
            print("    Saved: debug_08_courses_html.txt")
            
            print("\n[DONE] All debug files saved to backend folder.")
            
        except Exception as e:
            print(f"ERROR: {e}")
            page.screenshot(path=os.path.join(screenshot_dir, "debug_error.png"))
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_moodle()
