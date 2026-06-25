from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value

def check_completed_task():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).first()
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    print(f"Task: {task.title}")
    print(f"URL: {task.url}")
    print(f"Completed in DB: {task.is_completed}")
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()
        
        try:
            print("\n[1] Logging in...")
            page.goto(moodle_url + 'login/index.php', timeout=30000)
            page.fill('input[name="username"]', username)
            page.fill('input[name="password"]', password)
            page.click('#loginbtn')
            page.wait_for_load_state("networkidle", timeout=15000)
            
            print(f"[2] Navigating to task: {task.url}")
            page.goto(task.url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.screenshot(path="debug_completed_task.png", full_page=True)
            
            print("\n[3] Looking for completion elements...")
            completion_btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            
            if completion_btn:
                toggle_type = completion_btn.get_attribute('data-toggletype')
                btn_text = completion_btn.inner_text()
                print(f"    Found button: '{btn_text}'")
                print(f"    Toggle type: {toggle_type}")
            else:
                print("    No completion button found")
                
                completion_info = page.query_selector('.completion-info, .activity-completion')
                if completion_info:
                    print(f"    Completion info: {completion_info.inner_text()[:200]}")
            
            print("\n[4] Checking page for completion status...")
            page_text = page.inner_text('body')
            if 'Marcar como hecha' in page_text:
                print("    Found: 'Marcar como hecha' (Mark as done)")
            if 'Marcar como no hecha' in page_text:
                print("    Found: 'Marcar como no hecha' (Mark as not done)")
            if 'Hecha' in page_text:
                print("    Found: 'Hecha' (Done)")
            
        except Exception as e:
            print(f"ERROR: {e}")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    check_completed_task()
