from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def debug_upload():
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
        page = browser.new_page()
        
        try:
            # Login
            print("Logging in...")
            page.goto(moodle_url.rstrip("/") + "/login/index.php")
            page.fill('input[name="username"]', username)
            page.fill('input[name="password"]', password)
            page.click('#loginbtn')
            page.wait_for_load_state("networkidle")
            print("Logged in successfully")
            print()
            
            # Navigate to task
            print(f"Navigating to: {task.url}")
            page.goto(task.url)
            page.wait_for_load_state("networkidle")
            time.sleep(2)
            print("Page loaded")
            print()
            
            # Take screenshot
            page.screenshot(path="upload_debug.png", full_page=True)
            print("Screenshot saved: upload_debug.png")
            print()
            
            # Look for file inputs
            print("Searching for file inputs...")
            file_inputs = page.query_selector_all('input[type="file"]')
            print(f"Found {len(file_inputs)} file input(s)")
            
            for i, fi in enumerate(file_inputs):
                name = fi.get_attribute('name')
                id_attr = fi.get_attribute('id')
                print(f"  File input {i}: name={name}, id={id_attr}")
            print()
            
            # Look for file manager
            print("Searching for file manager...")
            file_managers = page.query_selector_all('.filemanager')
            print(f"Found {len(file_managers)} file manager(s)")
            
            for i, fm in enumerate(file_managers):
                class_name = fm.get_attribute('class')
                print(f"  File manager {i}: class={class_name}")
            print()
            
            # Look for add buttons
            print("Searching for add/upload buttons...")
            add_buttons = page.query_selector_all('button:has-text("Add"), input[value*="Add"], button:has-text("Upload"), input[value*="Upload"]')
            print(f"Found {len(add_buttons)} add/upload button(s)")
            
            for i, btn in enumerate(add_buttons):
                text = btn.inner_text() if btn.inner_text() else btn.get_attribute('value')
                print(f"  Button {i}: {text}")
            print()
            
            # Get page HTML for analysis
            print("Saving page HTML...")
            html = page.content()
            with open("upload_debug.html", "w", encoding="utf-8") as f:
                f.write(html)
            print("HTML saved: upload_debug.html")
            print()
            
            print("Debug complete. Check upload_debug.png and upload_debug.html")
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            browser.close()
    
    db.close()

if __name__ == "__main__":
    debug_upload()
