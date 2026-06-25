from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value

def check_assignment_completion():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.title.contains("Scrum")).first()
    
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
            page.screenshot(path="debug_assignment_completion.png", full_page=True)
            
            print("\n[3] Looking for completion button...")
            completion_btn = page.query_selector('button[data-action="toggle-manual-completion"]')
            
            if completion_btn:
                toggle_type = completion_btn.get_attribute('data-toggletype')
                btn_text = completion_btn.inner_text()
                print(f"    Found button: '{btn_text}'")
                print(f"    Toggle type: {toggle_type}")
                
                if toggle_type == "manual:mark-done":
                    print("\n[4] Clicking to mark as done...")
                    completion_btn.click()
                    page.wait_for_load_state("networkidle", timeout=5000)
                    page.screenshot(path="debug_after_mark_done.png", full_page=True)
                    print("    Marked as done!")
                    
                    new_btn = page.query_selector('button[data-action="toggle-manual-completion"]')
                    if new_btn:
                        new_toggle_type = new_btn.get_attribute('data-toggletype')
                        new_btn_text = new_btn.inner_text()
                        print(f"    New button: '{new_btn_text}'")
                        print(f"    New toggle type: {new_toggle_type}")
                else:
                    print("\n[4] Task already marked as done")
            else:
                print("    No completion button found")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    check_assignment_completion()
