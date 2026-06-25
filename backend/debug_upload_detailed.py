from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def debug_upload_detailed():
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
        
        # Enable console logging
        page.on("console", lambda msg: print(f"Browser console: {msg.text}"))
        
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
            
            # Select upload repository
            print("[5] Selecting upload repository...")
            upload_repo = file_picker.query_selector('.fp-repo-name:has-text("Subir un archivo")')
            if not upload_repo:
                upload_repo = page.query_selector('text="Subir un archivo"')
            
            if upload_repo:
                upload_repo.click()
                time.sleep(3)
                print("Upload repository selected!")
            else:
                print("ERROR: Upload repository not found!")
                return
            print()
            
            # Find file input
            print("[6] Finding file input...")
            file_input = page.query_selector('input[type="file"]')
            if not file_input:
                print("ERROR: File input not found!")
                return
            
            print("File input found!")
            print()
            
            # Upload file
            print("[7] Uploading file...")
            file_input.set_input_files('test_upload.txt')
            time.sleep(2)
            print("File selected!")
            print()
            
            # Click upload button
            print("[8] Clicking upload button...")
            upload_submit_btn = file_picker.query_selector('.fp-upload-btn, button:has-text("Upload this file"), button:has-text("Subir este archivo")')
            if upload_submit_btn:
                print(f"Upload button found: {upload_submit_btn.inner_text()}")
                upload_submit_btn.click()
                print("Upload button clicked!")
                
                # Wait and check for changes
                print("\n[9] Waiting for upload to complete...")
                for i in range(10):
                    time.sleep(1)
                    print(f"  Check {i+1}:")
                    
                    # Check file manager
                    files_in_manager = file_manager.query_selector_all('.fp-file')
                    print(f"    Files in file manager: {len(files_in_manager)}")
                    
                    # Check for error messages
                    error_msg = page.query_selector('.alert-danger, .error, .fp-msg-text')
                    if error_msg:
                        print(f"    Error message: {error_msg.inner_text()}")
                    
                    # Check for loading indicators
                    loading = page.query_selector('.fp-content-loading, .filemanager-loading')
                    if loading and loading.is_visible():
                        print(f"    Loading indicator visible")
                    
                    if len(files_in_manager) > 0:
                        print("    File found in file manager!")
                        break
            else:
                print("ERROR: Upload button not found!")
                return
            print()
            
            # Take screenshot
            page.screenshot(path="upload_detailed_debug.png", full_page=True)
            print("[10] Screenshot saved: upload_detailed_debug.png")
            print()
            
            # Save HTML
            html = page.content()
            with open("upload_detailed_debug.html", "w", encoding="utf-8") as f:
                f.write(html)
            print("[11] HTML saved: upload_detailed_debug.html")
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
            page.screenshot(path="upload_detailed_error.png")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_upload_detailed()
