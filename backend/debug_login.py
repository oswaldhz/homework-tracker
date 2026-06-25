"""
Debug script to test Moodle login flow using Python requests.
This mimics what the Flutter app does, so we can compare behavior.

Usage:
    cd backend
    venv\\Scripts\\activate
    python debug_login.py https://aulavirtual.itla.edu.do YOUR_USERNAME YOUR_PASSWORD
"""
import sys
import re
import requests


def main():
    if len(sys.argv) != 4:
        print("Usage: python debug_login.py <moodle_url> <username> <password>")
        sys.exit(1)

    moodle_url = sys.argv[1].rstrip('/')
    username = sys.argv[2]
    password = sys.argv[3]
    login_url = f"{moodle_url}/login/index.php"

    session = requests.Session()
    session.headers.update({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'es-DO,es;q=0.9,en;q=0.8',
    })

    print(f"GET {login_url}")
    resp = session.get(login_url, timeout=30)
    print(f"  status={resp.status_code}")
    print(f"  cookies={list(session.cookies.keys())}")

    match = re.search(r'<input[^>]*name="logintoken"[^>]*value="([^"]*)"', resp.text)
    logintoken = match.group(1) if match else ''
    print(f"  logintoken found={bool(logintoken)}")

    if not logintoken:
        print("ERROR: Could not find logintoken")
        sys.exit(1)

    print(f"\nPOST {login_url}")
    resp = session.post(
        login_url,
        data={
            'username': username,
            'password': password,
            'logintoken': logintoken,
            'anchor': '',
        },
        headers={
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': moodle_url,
            'Referer': login_url,
        },
        timeout=30,
        allow_redirects=True,
    )
    print(f"  status={resp.status_code}")
    print(f"  final_url={resp.url}")
    print(f"  cookies={list(session.cookies.keys())}")

    if '/login/' not in resp.url:
        print("\n✅ LOGIN SUCCESSFUL (redirected away from login page)")
    else:
        print("\n❌ LOGIN FAILED (still on login page)")

    # Look for visible error message
    error_match = re.search(
        r'<div[^>]*(?:loginerrormsg|alert alert-danger)[^>]*>(.*?)</div>',
        resp.text,
        re.DOTALL | re.IGNORECASE,
    )
    if error_match:
        error_text = re.sub(r'<[^>]+>', '', error_match.group(1)).strip()
        print(f"  Moodle error message: {error_text}")

    # Save response body for inspection
    with open('debug_login_response.html', 'w', encoding='utf-8') as f:
        f.write(resp.text)
    print("\nSaved response body to debug_login_response.html")


if __name__ == '__main__':
    main()
