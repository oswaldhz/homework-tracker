from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential, Task
from auth import decrypt_value
import time

def verify_upload():
    db = SessionLocal()
    cred = db.query(Credential).first()
    task = db.query(Task).filter(Task.id == 2).first()
    
    p = sync_playwright().start()
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    
    page.goto(cred.moodle_url.rstrip('/') + '/login/index.php')
    page.fill('input[name="username"]', decrypt_value(cred.encrypted_username))
    page.fill('input[name="password"]', decrypt_value(cred.encrypted_password))
    page.click('#loginbtn')
    page.wait_for_load_state('networkidle')
    
    page.goto(task.url)
    page.wait_for_load_state('networkidle')
    time.sleep(2)
    
    files = page.query_selector_all('.filemanager .fp-file')
    print(f'Files found: {len(files)}')
    
    for f in files:
        filename_elem = f.query_selector('.fp-filename')
        if filename_elem:
            print(f'  - {filename_elem.inner_text()}')
    
    browser.close()
    p.stop()
    db.close()

if __name__ == "__main__":
    verify_upload()
