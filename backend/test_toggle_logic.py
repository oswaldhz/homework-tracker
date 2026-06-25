from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
from pathlib import Path

def test_both_directions():
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
            
            print("\n[3] Initial button state:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                print(f"    Text: '{btn.inner_text().strip()}'")
                print(f"    Toggle type: {btn.get_attribute('data-toggletype')}")
            
            print("\n[4] Testing: Want to mark as DONE (complete=True)")
            print("    Looking for: mark-done or marcar como hecha")
            if btn:
                toggle_type = btn.get_attribute('data-toggletype') or ""
                btn_text = btn.inner_text().strip().lower()
                print(f"    Found: toggle_type='{toggle_type}', text='{btn_text}'")
                
                should_click = "mark-done" in toggle_type or "hecho" in btn_text or "mark as done" in btn_text
                print(f"    Should click? {should_click}")
                
                if should_click:
                    print("    Clicking...")
                    btn.click()
                    page.wait_for_load_state("networkidle", timeout=5000)
            
            print("\n[5] After marking as DONE:")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            if btn:
                print(f"    Text: '{btn.inner_text().strip()}'")
                print(f"    Toggle type: {btn.get_attribute('data-toggletype')}")
            
            print("\n[6] Testing: Want to mark as NOT DONE (complete=False)")
            print("    Looking for: undo or deshacer or marcar como no hecha")
            if btn:
                toggle_type = btn.get_attribute('data-toggletype') or ""
                btn_text = btn.inner_text().strip().lower()
                print(f"    Found: toggle_type='{toggle_type}', text='{btn_text}'")
                
                should_click = "undo" in toggle_type or "mark-not-done" in toggle_type or "deshacer" in btn_text or "marcar como no hecha" in btn_text
                print(f"    Should click? {should_click}")
                
                if should_click:
                    print("    Clicking...")
                    btn.click()
                    page.wait_for_load_state("networkidle", timeout=5000)
            
            print("\n[7] After marking as NOT DONE:")
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
    test_both_directions()
