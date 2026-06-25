from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
from datetime import datetime, timedelta
from models import SessionLocal, Course, Task
import re
import json
import os
from pathlib import Path
from config import BROWSER_DATA_DIR

if 'PLAYWRIGHT_BROWSERS_PATH' not in os.environ:
    import sys
    if getattr(sys, 'frozen', False):
        candidates = [
            Path(os.environ.get('LOCALAPPDATA', '')) / 'ms-playwright',
            Path(os.environ.get('APPDATA', '')) / 'ms-playwright',
            Path(os.environ.get('USERPROFILE', '')) / 'AppData' / 'Local' / 'ms-playwright',
        ]
        for p in candidates:
            if p.exists():
                os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(p)
                break

def get_current_week_range():
    today = datetime.now()
    start = today - timedelta(days=today.weekday())
    end = start + timedelta(days=6)
    return start, end

def scrape_moodle_assignments(moodle_url: str, username: str, password: str):
    BROWSER_DATA_DIR.mkdir(exist_ok=True)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(BROWSER_DATA_DIR),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()

        try:
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)

            needs_login = "login" in page.url.lower() or page.query_selector('input[name="username"]') is not None

            if needs_login:
                login_url = moodle_url.rstrip("/") + "/login/index.php"
                page.goto(login_url, timeout=30000)
                page.fill('input[name="username"]', username)
                page.fill('input[name="password"]', password)
                page.click('#loginbtn')
                page.wait_for_load_state("networkidle", timeout=15000)

                if "/login/index.php" in page.url:
                    raise Exception("Login failed. Check credentials.")

            assignments = extract_assignments(page, moodle_url)

            db = SessionLocal()
            try:
                save_assignments(db, assignments, moodle_url)
            finally:
                db.close()

            return {"success": True, "count": len(assignments)}

        except PlaywrightTimeout:
            raise Exception("Timeout while accessing Moodle. Check URL and connection.")
        except Exception as e:
            raise Exception(f"Scraping error: {str(e)}")
        finally:
            context.close()

def extract_assignments(page, moodle_url):
    assignments = []

    try:
        page.goto(f"{moodle_url.rstrip('/')}/calendar/view.php?view=upcoming", timeout=15000)
        page.wait_for_load_state("networkidle", timeout=10000)

        events = page.query_selector_all('div.event[data-type="event"]')

        for event in events:
            try:
                title_elem = event.query_selector('h3.name')
                if not title_elem:
                    continue

                title = title_elem.inner_text().strip()
                if not title:
                    continue

                date_elem = event.query_selector('span.date[data-timestamp]')
                due_date = None
                if date_elem:
                    timestamp = date_elem.get_attribute('data-timestamp')
                    if timestamp:
                        due_date = datetime.fromtimestamp(int(timestamp))

                course_link = event.query_selector('a[href*="/course/view.php"]')
                course_name = course_link.inner_text().strip() if course_link else "ITLA"
                course_url = course_link.get_attribute('href') if course_link else ""

                action_link = event.query_selector('div.card-footer a.card-link')
                url = action_link.get_attribute('href') if action_link else ""

                description_elem = event.query_selector('div.description-content')
                description = description_elem.inner_text().strip()[:500] if description_elem else ""

                assignments.append({
                    "title": title,
                    "course_name": course_name,
                    "course_url": course_url,
                    "due_date": due_date,
                    "url": url,
                    "description": description,
                    "status": "open"
                })
            except Exception as e:
                print(f"Error parsing event: {e}")
                continue

    except Exception as e:
        print(f"Error accessing calendar: {e}")

    return assignments

def parse_date(date_text):
    date_patterns = [
        r'(\d{1,2})\s+(\w+)\s+(\d{4})',
        r'(\d{1,2})/(\d{1,2})/(\d{4})',
        r'(\d{4})-(\d{2})-(\d{2})',
    ]

    months = {
        'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4,
        'mayo': 5, 'junio': 6, 'julio': 7, 'agosto': 8,
        'septiembre': 9, 'octubre': 10, 'noviembre': 11, 'diciembre': 12,
        'ene': 1, 'feb': 2, 'mar': 3, 'abr': 4,
        'may': 5, 'jun': 6, 'jul': 7, 'ago': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dic': 12,
        'january': 1, 'february': 2, 'march': 3, 'april': 4,
        'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
        'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    }

    for pattern in date_patterns:
        match = re.search(pattern, date_text, re.IGNORECASE)
        if match:
            groups = match.groups()
            try:
                if len(groups[0]) == 4:
                    return datetime(int(groups[0]), int(groups[1]), int(groups[2]))
                elif groups[1].isdigit():
                    return datetime(int(groups[2]), int(groups[1]), int(groups[0]))
                else:
                    month = months.get(groups[1].lower()[:4])
                    if month:
                        return datetime(int(groups[2]), month, int(groups[0]))
            except (ValueError, IndexError):
                continue

    return None

def toggle_moodle_completion(moodle_url: str, username: str, password: str, task_url: str, complete: bool):
    BROWSER_DATA_DIR.mkdir(exist_ok=True)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(BROWSER_DATA_DIR),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()

        try:
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)

            needs_login = "login" in page.url.lower() or page.query_selector('input[name="username"]') is not None

            if needs_login:
                login_success = False
                max_login_attempts = 3
                
                for attempt in range(max_login_attempts):
                    try:
                        login_url = moodle_url.rstrip("/") + "/login/index.php"
                        page.goto(login_url, timeout=30000)
                        page.wait_for_load_state("networkidle", timeout=10000)
                        
                        page.fill('input[name="username"]', username)
                        page.fill('input[name="password"]', password)
                        page.click('#loginbtn')
                        page.wait_for_load_state("networkidle", timeout=15000)
                        
                        if "/login/index.php" not in page.url:
                            login_success = True
                            break
                        else:
                            print(f"Login attempt {attempt + 1} failed, retrying...")
                            page.wait_for_timeout(2000)
                    except Exception as e:
                        print(f"Login attempt {attempt + 1} error: {e}")
                        if attempt < max_login_attempts - 1:
                            page.wait_for_timeout(2000)
                
                if not login_success:
                    context.close()
                    return {"success": False, "message": "Login failed after multiple attempts"}

            page.goto(task_url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.wait_for_timeout(1000)

            completion_btn = page.query_selector('button[data-action="toggle-manual-completion"]')

            if completion_btn:
                toggle_type = completion_btn.get_attribute('data-toggletype') or ""
                btn_text = completion_btn.inner_text().strip().lower()

                should_click = False

                if complete:
                    if "mark-done" in toggle_type or "marcar como hecha" in btn_text:
                        should_click = True
                else:
                    if "undo" in toggle_type or "hecho" in btn_text:
                        should_click = True

                if should_click:
                    completion_btn.click()
                    page.wait_for_timeout(2000)
                    return {"success": True, "message": "Completion status updated on Moodle"}
                else:
                    return {"success": True, "message": "Already in desired state"}
            else:
                return {"success": False, "message": "No completion toggle found on this task"}

        except Exception as e:
            raise Exception(f"Error updating Moodle completion: {str(e)}")
        finally:
            context.close()

def _get_accepted_file_types(page):
    try:
        accepted_extensions = []
        
        # Look for the "Tipos de archivo aceptados" text
        page_text = page.inner_text('body')
        
        # Try to find the accepted file types section
        # Pattern: "Tipos de archivo aceptados:" followed by file extensions
        if 'Tipos de archivo aceptados' in page_text or 'Accepted file types' in page_text:
            # Extract the section after "Tipos de archivo aceptados:"
            lines = page_text.split('\n')
            for i, line in enumerate(lines):
                if 'Tipos de archivo aceptados' in line or 'Accepted file types' in line:
                    # Look at the next few lines for file extensions
                    for j in range(i+1, min(i+10, len(lines))):
                        next_line = lines[j]
                        # Look for patterns like ".pdf", ".doc", ".docx"
                        extensions = re.findall(r'\.([a-zA-Z0-9]{2,5})\b', next_line)
                        accepted_extensions.extend([ext.lower() for ext in extensions])
                    break
        
        # Also try to get from file input accept attribute
        upload_input = page.query_selector('input[type="file"]')
        if upload_input:
            accept_attr = upload_input.get_attribute('accept')
            if accept_attr:
                # Parse accept attribute like ".pdf,.doc,.docx"
                accept_exts = re.findall(r'\.([a-zA-Z0-9]{2,5})\b', accept_attr)
                accepted_extensions.extend([ext.lower() for ext in accept_exts])
        
        # Remove duplicates
        accepted_extensions = list(set(accepted_extensions))
        
        if accepted_extensions:
            return ", ".join([f".{ext}" for ext in sorted(accepted_extensions)])
        return None
    except Exception as e:
        print(f"Error getting accepted file types: {e}")
        return None

def upload_file_to_moodle(moodle_url: str, username: str, password: str, task_url: str, file_path: str):
    import os
    file_ext = os.path.splitext(file_path)[1].lower().lstrip('.')
    file_name = os.path.basename(file_path)
    file_size = os.path.getsize(file_path) if os.path.exists(file_path) else 0

    BROWSER_DATA_DIR.mkdir(exist_ok=True)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(BROWSER_DATA_DIR),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()

        step = "initialization"
        try:
            step = "navigating to moodle"
            page.goto(moodle_url.rstrip("/"), timeout=30000)
            page.wait_for_load_state("networkidle", timeout=15000)

            needs_login = "login" in page.url.lower() or page.query_selector('input[name="username"]') is not None

            if needs_login:
                step = "logging in"
                login_success = False
                max_login_attempts = 3
                
                for attempt in range(max_login_attempts):
                    try:
                        login_url = moodle_url.rstrip("/") + "/login/index.php"
                        page.goto(login_url, timeout=30000)
                        page.wait_for_load_state("networkidle", timeout=10000)
                        
                        # Fill credentials
                        page.fill('input[name="username"]', username)
                        page.fill('input[name="password"]', password)
                        page.click('#loginbtn')
                        
                        # Wait for login to complete
                        page.wait_for_load_state("networkidle", timeout=15000)
                        page.wait_for_timeout(2000)
                        
                        # Check if login succeeded
                        if "/login/index.php" not in page.url:
                            login_success = True
                            break
                        else:
                            print(f"Login attempt {attempt + 1} failed, retrying...")
                            page.wait_for_timeout(2000)
                    except Exception as e:
                        print(f"Login attempt {attempt + 1} error: {e}")
                        if attempt < max_login_attempts - 1:
                            page.wait_for_timeout(2000)
                
                if not login_success:
                    context.close()
                    return {"success": False, "message": "Login failed after multiple attempts. Please verify your credentials in Settings."}

            if "action=editsubmission" not in task_url:
                task_url = task_url.split("?")[0] + "?action=editsubmission"

            step = "opening assignment page"
            page.goto(task_url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=15000)
            page.wait_for_timeout(2000)

            step = "finding file manager"
            file_manager = page.query_selector('.filemanager')
            if not file_manager:
                context.close()
                return {"success": False, "message": "This assignment does not have a file upload area. It may be a text submission or quiz."}

            accepted_info = _get_accepted_file_types(page)
            
            # Validate file type before attempting upload
            if accepted_info:
                accepted_list = [ext.strip().lower().lstrip('.') for ext in accepted_info.split(',')]
                if file_ext.lower() not in accepted_list:
                    context.close()
                    return {
                        "success": False, 
                        "message": f"File type '.{file_ext}' is not accepted. Accepted types: {accepted_info}"
                    }

            step = "clicking add button"
            add_btn = file_manager.query_selector('.fp-btn-add, button:has-text("Add"), .fp-btn-addfile')
            if not add_btn:
                add_btn = page.query_selector('.fp-btn-add, button:has-text("Add"), .fp-btn-addfile')

            if not add_btn:
                context.close()
                return {"success": False, "message": "Could not find the 'Add' button. The page layout may have changed."}

            add_btn.click()
            page.wait_for_timeout(2000)

            step = "opening file picker"
            file_picker = None
            for wait_ms in [1000, 2000, 3000]:
                page.wait_for_timeout(wait_ms if wait_ms == 1000 else 1000)
                file_picker = page.query_selector('.file-picker')
                if not file_picker:
                    file_picker = page.query_selector('.moodle-dialogue-content:visible')
                if file_picker:
                    break

            if not file_picker:
                context.close()
                return {"success": False, "message": "File picker dialog did not open. Please try again."}

            step = "selecting upload repository"
            upload_repo = None
            for selector in [
                '.fp-repo-name:has-text("Subir un archivo")',
                '.fp-repo-name:has-text("Upload a file")',
                '.fp-repo-name:has-text("Upload file")',
                '[title*="Subir"]',
                '[title*="Upload"]',
            ]:
                upload_repo = file_picker.query_selector(selector) or page.query_selector(selector)
                if upload_repo:
                    break

            if not upload_repo:
                context.close()
                return {"success": False, "message": "Could not find the 'Upload a file' option. The dialog structure may have changed."}

            upload_repo.click()
            page.wait_for_timeout(2000)

            step = "selecting file"
            file_input = page.query_selector('input[type="file"]')
            if not file_input:
                context.close()
                return {"success": False, "message": "No file input found in the upload dialog."}

            file_input.set_input_files(file_path)
            page.wait_for_timeout(2000)

            step = "clicking upload button"
            upload_submit_btn = None
            for selector in [
                '.fp-upload-btn',
                'button:has-text("Upload this file")',
                'button:has-text("Subir este archivo")',
                'input[type="submit"][value*="Upload"]',
                'input[type="submit"][value*="Subir"]',
            ]:
                upload_submit_btn = file_picker.query_selector(selector) or page.query_selector(selector)
                if upload_submit_btn:
                    break

            if not upload_submit_btn:
                context.close()
                return {"success": False, "message": "Could not find the 'Upload' button. The dialog structure may have changed."}

            upload_submit_btn.click()
            page.wait_for_timeout(4000)

            step = "handling confirmation dialog"
            confirm_dialog = page.query_selector('.moodle-dialogue-confirm, .confirmation-dialogue')
            if confirm_dialog:
                confirm_msg_el = confirm_dialog.query_selector('.confirmation-message')
                if confirm_msg_el:
                    msg_text = confirm_msg_el.inner_text().strip()
                    msg_lower = msg_text.lower()
                    print(f"Confirmation dialog message: {msg_text}")
                    if "no se acepta" in msg_lower or "not accepted" in msg_lower or "not allowed" in msg_lower:
                        context.close()
                        extra = f" Accepted: {accepted_info}." if accepted_info else ""
                        return {"success": False, "message": f"File type '{file_ext}' not accepted by Moodle.{extra} {msg_text}"}
                    if "exceeded" in msg_lower or "maximum" in msg_lower:
                        context.close()
                        return {"success": False, "message": f"Upload limit reached: {msg_text}"}
                    if "too large" in msg_lower or "size" in msg_lower:
                        context.close()
                        return {"success": False, "message": f"File too large: {msg_text}"}
                    if "error" in msg_lower or "failed" in msg_lower:
                        context.close()
                        return {"success": False, "message": f"Upload error: {msg_text}"}

                confirm_btn = confirm_dialog.query_selector(
                    '.fp-confirm-submit button, button:has-text("OK"), button:has-text("Continue"), button:has-text("Confirmar"), .yui3-button.yui3-button-primary, input[type="button"][value="OK"]'
                )
                if confirm_btn:
                    confirm_btn.click()
                    page.wait_for_timeout(2000)
                else:
                    page.keyboard.press('Enter')
                    page.wait_for_timeout(2000)
            
            # Check if file picker dialog is still open (might indicate upload failed)
            still_open = page.query_selector('.file-picker.moodle-dialogue-base:not(.moodle-dialogue-hidden)')
            if still_open:
                print("File picker dialog still open after upload")
                # Try to get any error messages from the dialog
                error_msg = still_open.query_selector('.moodle-dialogue-confirm .confirmation-message, .fp-content .error, .alert-danger')
                if error_msg:
                    error_text = error_msg.inner_text().strip()
                    context.close()
                    return {"success": False, "message": f"Upload failed: {error_text}"}

            step = "closing file picker dialog"
            try:
                close_btns = page.query_selector_all('.file-picker.moodle-dialogue-base .closebutton, .file-picker.moodle-dialogue-base button[aria-label="Close"], .file-picker.moodle-dialogue-base button[aria-label="Cerrar"]')
                for btn in close_btns:
                    if btn.is_visible():
                        btn.click()
                        page.wait_for_timeout(500)
                        break
            except Exception:
                pass

            page.evaluate("""
                document.querySelectorAll('.moodle-dialogue-base').forEach(dialog => {
                    if (!dialog.classList.contains('moodle-dialogue-hidden') && dialog.offsetParent !== null) {
                        const closeBtn = dialog.querySelector('.closebutton, button[aria-label="Close"], button[aria-label="Cerrar"]');
                        if (closeBtn) closeBtn.click();
                    }
                });
            """)

            page.wait_for_timeout(2000)

            step = "waiting for file in manager"
            files_in_manager = []
            for attempt in range(20):
                files_in_manager = file_manager.query_selector_all('.fp-file')
                if len(files_in_manager) > 0:
                    print(f"Found {len(files_in_manager)} file(s) in manager after {attempt + 1} seconds")
                    break
                page.wait_for_timeout(1000)

            if len(files_in_manager) == 0:
                # Try alternative selectors
                files_in_manager = file_manager.query_selector_all('.fp-filename, .fp-file-wrapper, .filemanager-container .fp-file')
                if len(files_in_manager) > 0:
                    print(f"Found {len(files_in_manager)} file(s) using alternative selectors")
                else:
                    # Save page content for debugging
                    page_content = page.content()
                    with open('debug_upload.html', 'w', encoding='utf-8') as f:
                        f.write(page_content)
                    print("Debug: Saved page content to debug_upload.html")
                    context.close()
                    extra = f" Accepted types: {accepted_info}." if accepted_info else ""
                    return {"success": False, "message": f"File '{file_name}' was not added to the file manager after upload. Check that the file type '.{file_ext}' is accepted.{extra}"}

            step = "clicking save button"
            save_btn = None
            for selector in [
                'input[type="submit"][value="Save changes"]',
                'input[type="submit"][value="Guardar cambios"]',
                'button:has-text("Save changes")',
                'button:has-text("Guardar cambios")',
                'button:has-text("Save submissions")',
                'input[name="submitbutton"]',
                'button[type="submit"]',
                'input[type="submit"]',
            ]:
                save_btn = page.query_selector(selector)
                if save_btn:
                    break

            if save_btn:
                try:
                    save_btn.scroll_into_view_if_needed()
                    page.wait_for_timeout(500)
                    save_btn.click(force=True)
                except Exception:
                    try:
                        save_btn.evaluate("el => el.click()")
                    except Exception:
                        pass

                try:
                    page.wait_for_load_state("networkidle", timeout=20000)
                except PlaywrightTimeout:
                    pass

                step = "verifying upload"
                page.wait_for_timeout(2000)
                success_indicator = page.query_selector('.alert-success, .submissionstatussubmitted, .text-success, .alert-info')
                context.close()
                if success_indicator:
                    return {"success": True, "message": "File uploaded successfully to Moodle"}
                return {"success": True, "message": "File upload submitted to Moodle (please verify in Moodle)"}

            context.close()
            return {"success": False, "message": "File was added to the file manager, but the 'Save changes' button could not be found."}

        except PlaywrightTimeout as e:
            context.close()
            return {"success": False, "message": f"Timeout during step '{step}'. Moodle may be slow. Please try again."}
        except Exception as e:
            context.close()
            error_msg = str(e)[:200]
            print(f"Upload error at step '{step}': {error_msg}")
            return {"success": False, "message": f"Error at step '{step}': {error_msg}"}


def get_quiz_questions(moodle_url: str, username: str, password: str, quiz_url: str):
    BROWSER_DATA_DIR.mkdir(exist_ok=True)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(BROWSER_DATA_DIR),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()

        try:
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)

            needs_login = "login" in page.url.lower() or page.query_selector('input[name="username"]') is not None

            if needs_login:
                login_success = False
                max_login_attempts = 3
                
                for attempt in range(max_login_attempts):
                    try:
                        login_url = moodle_url.rstrip("/") + "/login/index.php"
                        page.goto(login_url, timeout=30000)
                        page.wait_for_load_state("networkidle", timeout=10000)
                        
                        page.fill('input[name="username"]', username)
                        page.fill('input[name="password"]', password)
                        page.click('#loginbtn')
                        page.wait_for_load_state("networkidle", timeout=15000)
                        
                        if "/login/index.php" not in page.url:
                            login_success = True
                            break
                        else:
                            print(f"Login attempt {attempt + 1} failed, retrying...")
                            page.wait_for_timeout(2000)
                    except Exception as e:
                        print(f"Login attempt {attempt + 1} error: {e}")
                        if attempt < max_login_attempts - 1:
                            page.wait_for_timeout(2000)
                
                if not login_success:
                    context.close()
                    return {"success": False, "message": "Login failed after multiple attempts"}

            page.goto(quiz_url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.wait_for_timeout(2000)

            start_btn = page.query_selector('input[type="submit"][value="Attempt quiz now"], button:has-text("Attempt quiz"), a:has-text("Attempt quiz")')
            if start_btn:
                start_btn.click()
                page.wait_for_load_state("networkidle", timeout=15000)
                page.wait_for_timeout(2000)

            questions = []
            question_elements = page.query_selector_all('.que')

            for idx, q_elem in enumerate(question_elements):
                try:
                    question_text = q_elem.query_selector('.qtext, .questiontext')
                    question_title = question_text.inner_text().strip() if question_text else ""

                    q_type = "unknown"
                    if q_elem.query_selector('.answer input[type="radio"]'):
                        q_type = "multiple_choice"
                    elif q_elem.query_selector('.answer input[type="checkbox"]'):
                        q_type = "checkbox"
                    elif q_elem.query_selector('.answer textarea, .answer input[type="text"]'):
                        q_type = "text"

                    answers = []
                    answer_elements = q_elem.query_selector_all('.answer .r1, .answer label')
                    for ans_elem in answer_elements:
                        ans_text = ans_elem.inner_text().strip()
                        input_elem = ans_elem.query_selector('input')
                        if input_elem:
                            ans_name = input_elem.get_attribute('name') or ""
                            ans_value = input_elem.get_attribute('value') or ""
                            answers.append({
                                "text": ans_text,
                                "name": ans_name,
                                "value": ans_value
                            })

                    questions.append({
                        "id": idx,
                        "text": question_title,
                        "type": q_type,
                        "answers": answers
                    })
                except Exception as e:
                    print(f"Error parsing question: {e}")
                    continue

            return {"success": True, "questions": questions, "url": page.url}

        except Exception as e:
            raise Exception(f"Error fetching quiz questions: {str(e)}")
        finally:
            context.close()

def submit_quiz_answers(moodle_url: str, username: str, password: str, quiz_url: str, answers: dict):
    BROWSER_DATA_DIR.mkdir(exist_ok=True)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(BROWSER_DATA_DIR),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()

        try:
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)

            needs_login = "login" in page.url.lower() or page.query_selector('input[name="username"]') is not None

            if needs_login:
                login_success = False
                max_login_attempts = 3
                
                for attempt in range(max_login_attempts):
                    try:
                        login_url = moodle_url.rstrip("/") + "/login/index.php"
                        page.goto(login_url, timeout=30000)
                        page.wait_for_load_state("networkidle", timeout=10000)
                        
                        page.fill('input[name="username"]', username)
                        page.fill('input[name="password"]', password)
                        page.click('#loginbtn')
                        page.wait_for_load_state("networkidle", timeout=15000)
                        
                        if "/login/index.php" not in page.url:
                            login_success = True
                            break
                        else:
                            print(f"Login attempt {attempt + 1} failed, retrying...")
                            page.wait_for_timeout(2000)
                    except Exception as e:
                        print(f"Login attempt {attempt + 1} error: {e}")
                        if attempt < max_login_attempts - 1:
                            page.wait_for_timeout(2000)
                
                if not login_success:
                    context.close()
                    return {"success": False, "message": "Login failed after multiple attempts"}

            page.goto(quiz_url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.wait_for_timeout(2000)

            for q_id, answer_value in answers.items():
                try:
                    q_selector = f'.que[id="q{q_id}"]'
                    q_elem = page.query_selector(q_selector)

                    if q_elem:
                        radio_btn = q_elem.query_selector(f'input[type="radio"][value="{answer_value}"]')
                        if radio_btn:
                            radio_btn.check()
                            continue

                        checkbox = q_elem.query_selector(f'input[type="checkbox"][value="{answer_value}"]')
                        if checkbox:
                            checkbox.check()
                            continue

                        text_input = q_elem.query_selector('textarea, input[type="text"]')
                        if text_input:
                            text_input.fill(str(answer_value))
                            continue
                except Exception as e:
                    print(f"Error filling answer for question {q_id}: {e}")
                    continue

            submit_btn = page.query_selector('input[type="submit"][value="Submit all and finish"], button:has-text("Submit"), input[name="next"]')
            if submit_btn:
                submit_btn.click()
                page.wait_for_timeout(1000)

                confirm_btn = page.query_selector('input[type="submit"][value="Submit all and finish"], button:has-text("Submit")')
                if confirm_btn:
                    confirm_btn.click()
                    page.wait_for_load_state("networkidle", timeout=15000)

                return {"success": True, "message": "Quiz submitted successfully"}
            else:
                return {"success": False, "message": "Could not find submit button"}

        except Exception as e:
            raise Exception(f"Error submitting quiz: {str(e)}")
        finally:
            context.close()

def scrape_moodle_course_resources(moodle_url: str, username: str, password: str, course_url: str):
    """Scrape resources and materials from a Moodle course page"""
    BROWSER_DATA_DIR.mkdir(exist_ok=True)

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(
            user_data_dir=str(BROWSER_DATA_DIR),
            headless=True,
            args=['--disable-blink-features=AutomationControlled']
        )
        page = context.new_page()

        try:
            page.goto(moodle_url.rstrip("/"), timeout=15000)
            page.wait_for_load_state("networkidle", timeout=10000)

            needs_login = "login" in page.url.lower() or page.query_selector('input[name="username"]') is not None

            if needs_login:
                login_success = False
                max_login_attempts = 3
                
                for attempt in range(max_login_attempts):
                    try:
                        login_url = moodle_url.rstrip("/") + "/login/index.php"
                        page.goto(login_url, timeout=30000)
                        page.wait_for_load_state("networkidle", timeout=10000)
                        
                        page.fill('input[name="username"]', username)
                        page.fill('input[name="password"]', password)
                        page.click('#loginbtn')
                        page.wait_for_load_state("networkidle", timeout=15000)
                        
                        if "/login/index.php" not in page.url:
                            login_success = True
                            break
                        else:
                            print(f"Login attempt {attempt + 1} failed, retrying...")
                            page.wait_for_timeout(2000)
                    except Exception as e:
                        print(f"Login attempt {attempt + 1} error: {e}")
                        if attempt < max_login_attempts - 1:
                            page.wait_for_timeout(2000)
                
                if not login_success:
                    context.close()
                    return {"success": False, "message": "Login failed after multiple attempts"}

            page.goto(quiz_url, timeout=30000)
            page.wait_for_load_state("networkidle", timeout=10000)
            page.wait_for_timeout(2000)

            resources = []

            resource_elements = page.query_selector_all('.activity.modtype_resource, .activity.modtype_url, .activity.modtype_page')

            for resource_elem in resource_elements:
                try:
                    title_elem = resource_elem.query_selector('.instancename, .activityname')
                    if not title_elem:
                        continue

                    title = title_elem.inner_text().strip()
                    if not title or len(title) < 3:
                        continue

                    link_elem = resource_elem.query_selector('a[href]')
                    url = link_elem.get_attribute('href') if link_elem else ""

                    resource_type = "document"
                    if "modtype_resource" in resource_elem.get_attribute('class') or "":
                        resource_type = "document"
                    elif "modtype_url" in resource_elem.get_attribute('class') or "":
                        resource_type = "link"
                    elif "modtype_page" in resource_elem.get_attribute('class') or "":
                        resource_type = "page"

                    resources.append({
                        "title": title,
                        "url": url,
                        "type": resource_type
                    })
                except Exception as e:
                    continue

            return {"success": True, "resources": resources}

        except Exception as e:
            return {"success": False, "error": str(e), "resources": []}
        finally:
            context.close()

def save_assignments(db, assignments, moodle_url):
    for assignment in assignments:
        moodle_id = re.sub(r'[^\w]', '_', assignment['title'][:50])

        course = db.query(Course).filter(Course.name == assignment['course_name']).first()
        if not course:
            course_url = assignment.get('course_url', '')
            if course_url and not course_url.startswith('http'):
                course_url = f"{moodle_url.rstrip('/')}/{course_url.lstrip('/')}"

            course = Course(
                moodle_id=f"course_{assignment['course_name'][:30]}",
                name=assignment['course_name'],
                short_name=assignment['course_name'][:10],
                url=course_url
            )
            db.add(course)
            db.flush()
        elif not course.url and assignment.get('course_url'):
            course_url = assignment.get('course_url', '')
            if course_url and not course_url.startswith('http'):
                course_url = f"{moodle_url.rstrip('/')}/{course_url.lstrip('/')}"
            course.url = course_url

        existing = db.query(Task).filter(Task.moodle_id == moodle_id).first()
        if existing:
            existing.title = assignment['title']
            existing.due_date = assignment['due_date']
            existing.status = assignment['status']
            existing.url = assignment['url']
            existing.description = assignment.get('description', '')
        else:
            task = Task(
                moodle_id=moodle_id,
                course_id=course.id,
                title=assignment['title'],
                due_date=assignment['due_date'],
                status=assignment['status'],
                url=assignment['url'],
                description=assignment.get('description', '')
            )
            db.add(task)

    db.commit()
