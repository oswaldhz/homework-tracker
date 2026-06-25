from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
from pathlib import Path

def simple_toggle_test():
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
            
            print("\n[3] Looking for completion button...")
            btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            
            if btn:
                toggle_type = btn.get_attribute('data-toggletype') or ""
                btn_text = btn.inner_text().strip()
                print(f"    Found button!")
                print(f"    Text: '{btn_text}'")
                print(f"    Toggle type: '{toggle_type}'")
                print(f"    Enabled: {btn.is_enabled()}")
                
                print("\n[4] Clicking button...")
                btn.click()
                page.wait_for_load_state("networkidle", timeout=5000)
                print("    Clicked!")
                
                print("\n[5] Checking button after click...")
                btn2 = page.query_selector('button[data-action="toggle-manual-completion"]')
                if btn2:
                    toggle_type2 = btn2.get_attribute('data-toggletype') or ""
                    btn_text2 = btn2.inner_text().strip()
                    print(f"    Text: '{btn_text2}'")
                    print(f"    Toggle type: '{toggle_type2}'")
                else:
                    print("    No button found after click")
            else:
                print("    No button found")
                
                print("\n[4] Checking page for completion status...")
                page_text = page.inner_text('body')
                if 'hecho' in page_text.lower():
                    print("    Found 'Hecho' (Done) in page")
                if 'pendiente' in page_text.lower():
                    print("    Found 'Pendiente' (Pending) in page")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
        finally:
            context.close()
    
    db.close()

if __name__ == "__main__":
    simple_toggle_test()
