from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
from pathlib import Path

def debug_current_state():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.title.contains("Scrum")).first()
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    user_data_dir = Path(__file__).parent / "browser_data"
    
    print(f"Task: {task.title}")
    print(f"DB state: completed={task.is_completed}")
    
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
            
            print(f"\n[2] Navigating to task...")
            page.goto(task.url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            
            print("\n[3] Current button state:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                toggle_type = btn.get_attribute('data-toggletype') or ""
                btn_text = btn.inner_text().strip()
                print(f"    Text: '{btn_text}'")
                print(f"    Toggle type: '{toggle_type}'")
                
                print("\n[4] Testing logic:")
                print(f"    Want to mark as NOT DONE (complete=False)")
                
                should_click = False
                if "undo" in toggle_type or "hecho" in btn_text.lower():
                    should_click = True
                    print(f"    Should click: YES (found undo/hecho)")
                else:
                    print(f"    Should click: NO")
                
                if should_click:
                    print("\n[5] Clicking button to mark as NOT DONE...")
                    btn.click()
                    page.wait_for_timeout(2000)
                    
                    btn2 = page.query_selector('button[data-action="toggle-manual-completion"]')
                    if btn2:
                        print(f"    New text: '{btn2.inner_text().strip()}'")
                        print(f"    New toggle type: {btn2.get_attribute('data-toggletype')}")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
        finally:
            context.close()
    
    db.close()

if __name__ == "__main__":
    debug_current_state()
