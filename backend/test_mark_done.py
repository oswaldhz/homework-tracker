from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
from pathlib import Path

def test_mark_done():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.title.contains("Scrum")).first()
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    user_data_dir = Path(__file__).parent / "browser_data"
    
    print(f"Task: {task.title}")
    print(f"Current DB state: completed={task.is_completed}")
    
    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(user_data_dir),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()
        
        try:
            print("\n[1] Logging in...")
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)
            
            if "login" in page.url.lower():
                login_url = moodle_url.rstrip("/") + "/login/index.php"
                page.goto(login_url, timeout=30000)
                page.fill('input[name="username"]', username)
                page.fill('input[name="password"]', password)
                page.click('#loginbtn')
                page.wait_for_load_state("networkidle", timeout=15000)
            
            print(f"\n[2] Navigating to task: {task.url}")
            page.goto(task.url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            
            print("\n[3] Checking button state:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                toggle_type = btn.get_attribute('data-toggletype') or ""
                btn_text = btn.inner_text().strip()
                print(f"    Text: '{btn_text}'")
                print(f"    Toggle type: '{toggle_type}'")
                print(f"    Enabled: {btn.is_enabled()}")
            else:
                print("    No button found!")
            
            print("\n[4] Trying to mark as DONE (complete=True)...")
            print("    Looking for: mark-done or marcar como hecha")
            if btn:
                toggle_type = btn.get_attribute('data-toggletype') or ""
                btn_text = btn.inner_text().strip().lower()
                
                should_click = "mark-done" in toggle_type or "marcar como hecha" in btn_text
                print(f"    Should click? {should_click}")
                
                if should_click:
                    print("    Clicking...")
                    btn.click()
                    page.wait_for_timeout(2000)
                    print("    Clicked!")
                    
                    btn2 = page.query_selector('button[data-action="toggle-manual-completion"]')
                    if btn2:
                        print(f"    New text: '{btn2.inner_text().strip()}'")
                        print(f"    New toggle type: {btn2.get_attribute('data-toggletype')}")
                else:
                    print("    Already done, not clicking")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
        finally:
            context.close()
    
    db.close()

if __name__ == "__main__":
    test_mark_done()
