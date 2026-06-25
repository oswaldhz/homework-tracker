from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential
from auth import decrypt_value

db = SessionLocal()
cred = db.query(Credential).first()
moodle_url = cred.moodle_url
username = decrypt_value(cred.encrypted_username)
password = decrypt_value(cred.encrypted_password)

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    login_url = moodle_url.rstrip('/') + '/login/index.php'
    page.goto(login_url, timeout=30000)
    page.fill('input[name="username"]', username)
    page.fill('input[name="password"]', password)
    page.click('#loginbtn')
    page.wait_for_load_state('networkidle', timeout=15000)
    print(f'Final URL: {page.url}')
    print(f'Contains /login/: {"/login/" in page.url}')
    browser.close()
db.close()
