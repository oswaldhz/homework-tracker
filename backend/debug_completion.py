from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value

def debug_task_completion():
    db = SessionLocal()
    cred = db.query(Credential).first()
    if not cred:
        print("No credentials found")
        return
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    task = db.query(Task).filter(Task.title.contains("Scrum")).first()
    if not task:
        print("No task found")
        return
    
    print(f"Task: {task.title}")
    print(f"URL: {task.url}")
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1920, "height": 1080})
        page = context.new_page()
        
        try:
            print("\n[1] Logging in...")
            login_url = moodle_url.rstrip("/") + "/login/index.php"
            page.goto(login_url, timeout=30000)
            page.fill('input[name="username"]', username)
            page.fill('input[name="password"]', password)
            page.click('#loginbtn')
            page.wait_for_load_state("networkidle", timeout=15000)
            print(f"    Logged in, URL: {page.url}")
            
            print(f"\n[2] Navigating to task: {task.url}")
            page.goto(task.url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.screenshot(path="debug_task_page.png", full_page=True)
            print("    Saved: debug_task_page.png")
            
            print("\n[3] Looking for completion elements...")
            
            completion_checkbox = page.query_selector('input[type="checkbox"][name*="completion"]')
            if completion_checkbox:
                print("    Found completion checkbox")
            
            mark_done_button = page.query_selector('button:has-text("Mark as done"), a:has-text("Mark as done")')
            if mark_done_button:
                print("    Found 'Mark as done' button")
            
            submit_button = page.query_selector('button:has-text("Submit"), input[type="submit"][value*="Submit"]')
            if submit_button:
                print("    Found submit button")
            
            completion_status = page.query_selector('.completion-info, .activity-completion, [data-region="completion"]')
            if completion_status:
                print("    Found completion status element")
                print(f"    Text: {completion_status.inner_text()[:100]}")
            
            print("\n[4] Extracting page HTML for analysis...")
            html = page.evaluate("() => document.body.innerHTML")
            with open("debug_task_html.txt", "w", encoding="utf-8") as f:
                f.write(html[:100000])
            print("    Saved: debug_task_html.txt")
            
            print("\n[5] Looking for manual completion toggle...")
            toggle_btn = page.query_selector('button[data-action="toggle-manual-completion"], .completion-manual button')
            if toggle_btn:
                print(f"    Found toggle button: {toggle_btn.inner_text()}")
                print(f"    Button HTML: {toggle_btn.evaluate('el => el.outerHTML')[:200]}")
            
            print("\n[DONE]")
            
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
            page.screenshot(path="debug_error.png")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_task_completion()
