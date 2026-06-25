from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
from pathlib import Path

def debug_toggle_states():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.title.contains("Scrum")).first()
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    user_data_dir = Path(__file__).parent / "browser_data"
    
    print(f"Task: {task.title}")
    print(f"URL: {task.url}")
    
    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(user_data_dir),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()
        
        try:
            print("\n[1] Logging in (using persistent session)...")
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)
            
            if "login" in page.url.lower():
                print("    Session expired, logging in...")
                login_url = moodle_url.rstrip("/") + "/login/index.php"
                page.goto(login_url, timeout=30000)
                page.fill('input[name="username"]', username)
                page.fill('input[name="password"]', password)
                page.click('#loginbtn')
                page.wait_for_load_state("networkidle", timeout=15000)
            else:
                print("    Using existing session")
            
            print(f"\n[2] Navigating to task: {task.url}")
            page.goto(task.url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            
            print("\n[3] Checking completion button state...")
            completion_btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            
            if completion_btn:
                toggle_type = completion_btn.get_attribute('data-toggletype')
                btn_text = completion_btn.inner_text().strip()
                print(f"    Button text: '{btn_text}'")
                print(f"    Toggle type: {toggle_type}")
                
                print("\n[4] Clicking button to toggle state...")
                completion_btn.click()
                page.wait_for_load_state("networkidle", timeout=5000)
                
                print("\n[5] Checking button state after click...")
                new_btn = page.query_selector('button[data-action="toggle-manual-completion"]')
                if new_btn:
                    new_toggle_type = new_btn.get_attribute('data-toggletype')
                    new_btn_text = new_btn.inner_text().strip()
                    print(f"    New button text: '{new_btn_text}'")
                    print(f"    New toggle type: {new_toggle_type}")
            else:
                print("    No completion button found")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
        finally:
            context.close()
    
    db.close()

if __name__ == "__main__":
    debug_toggle_states()
