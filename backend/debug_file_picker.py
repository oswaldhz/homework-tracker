from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def debug_file_picker():
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
            
            # Find file manager
            print("[3] Finding file manager...")
            file_manager = page.query_selector('.filemanager')
            if not file_manager:
                print("ERROR: No file manager found!")
                return
            
            print("File manager found!")
            print()
            
            # Find add button
            print("[4] Finding add button...")
            add_btn = file_manager.query_selector('.fp-btn-add, button:has-text("Add"), .fp-btn-addfile')
            if not add_btn:
                add_btn = page.query_selector('.fp-btn-add, button:has-text("Add"), .fp-btn-addfile')
            
            if not add_btn:
                print("ERROR: No add button found!")
                return
            
            print(f"Add button found!")
            print()
            
            # Click add button
            print("[5] Clicking add button...")
            add_btn.click()
            time.sleep(2)
            print("Add button clicked!")
            print()
            
            # Take screenshot
            page.screenshot(path="file_picker_debug.png", full_page=True)
            print("[6] Screenshot saved: file_picker_debug.png")
            print()
            
            # Find file picker dialog
            print("[7] Finding file picker dialog...")
            file_picker = page.query_selector('.file-picker')
            if not file_picker:
                file_picker = page.query_selector('.moodle-dialogue-content')
            
            if not file_picker:
                print("ERROR: File picker dialog not found!")
                return
            
            print("File picker dialog found!")
            print()
            
            # Look for upload tab
            print("[8] Looking for upload tab...")
            upload_tab = file_picker.query_selector('a:has-text("Upload file"), .fp-upload-btn, button:has-text("Upload")')
            if upload_tab:
                print("Upload tab found, clicking...")
                upload_tab.click()
                time.sleep(2)
                print("Upload tab clicked!")
            else:
                print("No upload tab found")
            print()
            
            # Take screenshot after clicking upload tab
            page.screenshot(path="file_picker_debug_after_upload_tab.png", full_page=True)
            print("[9] Screenshot saved: file_picker_debug_after_upload_tab.png")
            print()
            
            # Look for file input
            print("[10] Looking for file input...")
            file_input = file_picker.query_selector('input[type="file"]')
            if not file_input:
                file_input = page.query_selector('input[type="file"]')
            
            if file_input:
                print("File input found!")
                print(f"  Name: {file_input.get_attribute('name')}")
                print(f"  ID: {file_input.get_attribute('id')}")
            else:
                print("ERROR: File input not found!")
                
                # Debug: list all inputs
                print("\n[11] Debug: All inputs on page:")
                all_inputs = page.query_selector_all('input')
                for i, inp in enumerate(all_inputs):
                    input_type = inp.get_attribute('type')
                    input_name = inp.get_attribute('name')
                    input_id = inp.get_attribute('id')
                    visible = inp.is_visible()
                    print(f"  Input {i}: type={input_type}, name={input_name}, id={input_id}, visible={visible}")
            
            print()
            print("[12] Saving HTML...")
            html = page.content()
            with open("file_picker_debug.html", "w", encoding="utf-8") as f:
                f.write(html)
            print("HTML saved: file_picker_debug.html")
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
            page.screenshot(path="file_picker_debug_error.png")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_file_picker()
