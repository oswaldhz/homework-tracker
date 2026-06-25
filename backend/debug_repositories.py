from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def debug_repositories():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.id == 2).first()
    
    moodle_url = cred.moodle_url
    username = decrypt_value(cred.encrypted_username)
    password = decrypt_value(cred.encrypted_password)
    
    print(f"Task: {task.title}")
    print(f"URL: {task.url}")
    print()
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context()
        page = context.new_page()
        
        try:
            # Login
            print("[1] Logging in...")
            page.goto(moodle_url.rstrip("/") + "/login/index.php")
            page.wait_for_load_state("networkidle")
            page.fill('input[name="username"]', username)
            page.fill('input[name="password"]', password)
            page.click('#loginbtn')
            page.wait_for_load_state("networkidle")
            time.sleep(2)
            print("Login successful!")
            print()
            
            # Navigate to task
            print(f"[2] Navigating to: {task.url}")
            page.goto(task.url, wait_until="networkidle")
            time.sleep(3)
            print("Page loaded")
            print()
            
            # Find file manager and add button
            print("[3] Finding file manager...")
            file_manager = page.query_selector('.filemanager')
            add_btn = file_manager.query_selector('.fp-btn-add, button:has-text("Add"), .fp-btn-addfile')
            print("Add button found, clicking...")
            add_btn.click()
            time.sleep(3)
            print("Add button clicked!")
            print()
            
            # Find file picker dialog
            print("[4] Finding file picker dialog...")
            file_picker = page.query_selector('.file-picker')
            if not file_picker:
                file_picker = page.query_selector('.moodle-dialogue-content')
            
            print("File picker found!")
            print()
            
            # List all repositories
            print("[5] Available repositories:")
            repos = file_picker.query_selector_all('.fp-repo-name')
            for i, repo in enumerate(repos):
                text = repo.inner_text()
                print(f"  {i+1}. '{text}'")
            print()
            
            # Try to find upload repository with different selectors
            print("[6] Trying different selectors for 'Subir un archivo':")
            
            # Selector 1: exact text
            repo1 = file_picker.query_selector('.fp-repo-name:has-text("Subir un archivo")')
            print(f"  Selector 1 (.fp-repo-name:has-text): {repo1 is not None}")
            
            # Selector 2: contains text
            repo2 = file_picker.query_selector('span:has-text("Subir un archivo")')
            print(f"  Selector 2 (span:has-text): {repo2 is not None}")
            
            # Selector 3: by text content
            repo3 = page.query_selector('text="Subir un archivo"')
            print(f"  Selector 3 (text=): {repo3 is not None}")
            
            # Selector 4: by role
            repo4 = file_picker.query_selector('[role="tab"]:has-text("Subir un archivo")')
            print(f"  Selector 4 ([role=tab]:has-text): {repo4 is not None}")
            
            # List all elements with text
            print("\n[7] All elements with 'Subir':")
            all_elements = page.query_selector_all('*:has-text("Subir")')
            for i, elem in enumerate(all_elements[:10]):
                tag = elem.evaluate('el => el.tagName')
                text = elem.inner_text()[:50]
                class_name = elem.get_attribute('class') or ''
                print(f"  {i+1}. <{tag}> class='{class_name[:50]}' text='{text}'")
            
            # Take screenshot
            page.screenshot(path="repositories_debug.png", full_page=True)
            print("\n[8] Screenshot saved: repositories_debug.png")
            
            # Save HTML
            html = page.content()
            with open("repositories_debug.html", "w", encoding="utf-8") as f:
                f.write(html)
            print("[9] HTML saved: repositories_debug.html")
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
            page.screenshot(path="repositories_error.png")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_repositories()
