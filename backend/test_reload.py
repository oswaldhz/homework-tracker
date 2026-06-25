from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
from pathlib import Path

def test_with_reload():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.title.contains("Scrum")).first()
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    user_data_dir = Path(__file__).parent / "browser_data"
    
    print(f"Task: {task.title}")
    
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
            
            print("\n[3] Initial state:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                print(f"    Text: '{btn.inner_text().strip()}'")
                print(f"    Toggle type: {btn.get_attribute('data-toggletype')}")
            
            print("\n[4] Clicking button...")
            btn.click()
            
            print("\n[5] Waiting for button to update...")
            page.wait_for_timeout(2000)
            
            print("\n[6] Checking button after wait:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                print(f"    Text: '{btn.inner_text().strip()}'")
                print(f"    Toggle type: {btn.get_attribute('data-toggletype')}")
            
            print("\n[7] Reloading page...")
            page.reload()
            page.wait_for_load_state("networkidle", timeout=10000)
            
            print("\n[8] Checking button after reload:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                print(f"    Text: '{btn.inner_text().strip()}'")
                print(f"    Toggle type: {btn.get_attribute('data-toggletype')}")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
        finally:
            context.close()
    
    db.close()

if __name__ == "__main__":
    test_with_reload()
