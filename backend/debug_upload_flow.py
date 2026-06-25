from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def debug_upload_flow():
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
            time.sleep(2)
            print("Add button clicked!")
            print()
            
            # Find file picker dialog
            print("[4] Finding file picker dialog...")
            file_picker = page.query_selector('.file-picker')
            if not file_picker:
                file_picker = page.query_selector('.moodle-dialogue-content')
            
            print("File picker found!")
            print()
            
            # Look for upload repository
            print("[5] Looking for upload repository...")
            upload_repo = file_picker.query_selector('.fp-repo-name:has-text("Subir un archivo")')
            if upload_repo:
                print("Found 'Subir un archivo' repository, clicking...")
                upload_repo.click()
                time.sleep(3)
                print("Clicked!")
            else:
                print("ERROR: Upload repository not found!")
                
                # List all repositories
                print("\nAvailable repositories:")
                repos = file_picker.query_selector_all('.fp-repo-name')
                for repo in repos:
                    print(f"  - {repo.inner_text()}")
            print()
            
            # Take screenshot
            page.screenshot(path="upload_flow_step1.png", full_page=True)
            print("[6] Screenshot saved: upload_flow_step1.png")
            print()
            
            # Look for file input immediately after selecting repository
            print("[7] Looking for file input after selecting repository...")
            file_input = page.query_selector('input[type="file"]')
            
            if file_input:
                print("File input found!")
                print(f"  Name: {file_input.get_attribute('name')}")
                print(f"  ID: {file_input.get_attribute('id')}")
                print(f"  Visible: {file_input.is_visible()}")
            else:
                print("File input not found yet, checking for upload button...")
                
                # Look for upload button
                upload_btn = file_picker.query_selector('.fp-tb-uploadfile a')
                if upload_btn:
                    print("Found upload button, but it's not visible, checking if we need to wait...")
                    time.sleep(2)
                    
                    # Try again
                    file_input = page.query_selector('input[type="file"]')
                    if file_input:
                        print("File input found after waiting!")
                    else:
                        print("Still no file input found")
                else:
                    print("No upload button found either")
            
            # Take screenshot
            page.screenshot(path="upload_flow_step2.png", full_page=True)
            print("[8] Screenshot saved: upload_flow_step2.png")
            print()
            
            # Save HTML
            print("[10] Saving HTML...")
            html = page.content()
            with open("upload_flow_debug.html", "w", encoding="utf-8") as f:
                f.write(html)
            print("HTML saved: upload_flow_debug.html")
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
            page.screenshot(path="upload_flow_error.png")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_upload_flow()
