from playwright.sync_api import sync_playwright
from models import SessionLocal, Credential
from auth import decrypt_value

db = SessionLocal()
cred = db.query(Credential).first()
url = cred.moodle_url
user = decrypt_value(cred.encrypted_username)
pwd = decrypt_value(cred.encrypted_password)

p = sync_playwright().start()
browser = p.chromium.launch(headless=True)
page = browser.new_page()
page.goto(url + 'login/index.php', timeout=30000)
page.fill('input[name="username"]', user)
page.fill('input[name="password"]', pwd)
page.click('#loginbtn')
page.wait_for_load_state('networkidle', timeout=15000)
print(f'Final URL: {page.url}')
print(f'Contains /login/: {"/login/" in page.url}')
browser.close()
p.stop()
db.close()
