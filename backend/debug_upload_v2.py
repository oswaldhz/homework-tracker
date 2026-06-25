from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def debug_upload_v2():
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
            
            # Wait for navigation after login
            page.wait_for_load_state("networkidle")
            time.sleep(3)
            
            print(f"Current URL after login: {page.url}")
            print(f"Is login page? {'login' in page.url.lower()}")
            print()
            
            # Check if logged in
            if "login" in page.url.lower():
                print("ERROR: Still on login page!")
                page.screenshot(path="upload_debug_login_failed.png")
                return
            
            print("Login successful!")
            print()
            
            # Navigate to task
            print(f"[2] Navigating to: {task.url}")
            page.goto(task.url, wait_until="networkidle")
            time.sleep(3)
            
            print(f"Current URL: {page.url}")
            print()
            
            # Take screenshot
            page.screenshot(path="upload_debug_v2.png", full_page=True)
            print("[3] Screenshot saved: upload_debug_v2.png")
            print()
            
            # Check page title
            title = page.title()
            print(f"Page title: {title}")
            print()
            
            # Look for various file upload elements
            print("[4] Searching for upload elements...")
            
            # File inputs
            file_inputs = page.query_selector_all('input[type="file"]')
            print(f"  File inputs: {len(file_inputs)}")
            
            # File manager
            file_managers = page.query_selector_all('.filemanager, .file-picker, [data-filemanager]')
            print(f"  File managers: {len(file_managers)}")
            
            # Add file buttons
            add_buttons = page.query_selector_all('.fp-btn-add, button:has-text("Agregar"), input[value*="Agregar"], button:has-text("Add"), .filemanager .btn')
            print(f"  Add buttons: {len(add_buttons)}")
            
            # Submission status
            submission_status = page.query_selector_all('.submissionstatus, .assign-submission-summary, .submission')
            print(f"  Submission elements: {len(submission_status)}")
            
            # Edit submission button
            edit_buttons = page.query_selector_all('a:has-text("Editar entrega"), a:has-text("Add submission"), a[href*="action=editsubmission"]')
            print(f"  Edit submission buttons: {len(edit_buttons)}")
            
            for btn in edit_buttons:
                text = btn.inner_text()
                href = btn.get_attribute('href')
                print(f"    Button: '{text}' -> {href}")
            
            print()
            
            # If we found edit submission button, click it
            if edit_buttons:
                print("[5] Found edit submission button, clicking...")
                edit_buttons[0].click()
                page.wait_for_load_state("networkidle")
                time.sleep(3)
                
                print(f"URL after click: {page.url}")
                page.screenshot(path="upload_debug_v2_after_click.png", full_page=True)
                print("Screenshot saved: upload_debug_v2_after_click.png")
                print()
                
                # Now look for file inputs again
                print("[6] Searching for upload elements after click...")
                file_inputs = page.query_selector_all('input[type="file"]')
                print(f"  File inputs: {len(file_inputs)}")
                
                file_managers = page.query_selector_all('.filemanager, .file-picker, [data-filemanager]')
                print(f"  File managers: {len(file_managers)}")
                
                add_buttons = page.query_selector_all('.fp-btn-add, button:has-text("Agregar"), .filemanager .btn')
                print(f"  Add buttons: {len(add_buttons)}")
                
                for btn in add_buttons:
                    text = btn.inner_text() if btn.is_visible() else "(hidden)"
                    print(f"    Button: '{text}'")
            
            print()
            print("[7] Saving HTML...")
            html = page.content()
            with open("upload_debug_v2.html", "w", encoding="utf-8") as f:
                f.write(html)
            print("HTML saved: upload_debug_v2.html")
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
            page.screenshot(path="upload_debug_v2_error.png")
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_upload_v2()
