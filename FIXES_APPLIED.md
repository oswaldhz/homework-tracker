# Fixes Applied

## 1. Overdue Tasks Showing in Pending Tab ✓

**Issue:** Overdue tasks were appearing in the Pending tab even though they should only appear in the Overdue tab.

**Fix:** Updated the frontend filtering logic in `dashboard_screen.dart`:
- Changed the Pending tab filter from `!t.isCompleted` to `!t.isCompleted && !t.isOverdue`
- This ensures overdue tasks are excluded from the Pending tab and only shown in the Overdue tab

**Files Modified:**
- `frontend/lib/screens/dashboard_screen.dart` (line 103)

## 2. AI Token Quota Error Handling ✓

**Issue:** When the Gemini API quota was exceeded, the app showed a generic error instead of a clear message about being out of tokens.

**Fix:** Implemented comprehensive quota error handling:

### Backend (`ai_materials.py`):
- Added specific detection for quota/rate limit errors (429, "quota", "rate limit", "resource exhausted")
- Returns a clear error message: "You are out of AI tokens. Please wait or check your Gemini API quota."
- Error is returned in the response body with `ai_generated: false`

### Frontend (`task_materials_screen.dart`):
- Updated `_loadMaterials()` to check for the `error` field in the API response
- Enhanced error display with:
  - Different icon for quota errors (battery_alert) vs generic errors (error_outline)
  - Orange color for quota errors, red for other errors
  - Centered text for better readability
  - Retry button remains available

**Files Modified:**
- `backend/ai_materials.py` (lines 294-315)
- `frontend/lib/screens/task_materials_screen.dart` (lines 28-56, 105-125)

## Testing

Both fixes have been tested and verified:
1. Overdue tasks now correctly appear only in the Overdue tab
2. When AI quota is exceeded, users see a clear message with appropriate icon
3. The app continues to function normally for all other features

## How to Test

### Test Pending/Overdue Filtering:
1. Create a task with a past due date
2. Check that it appears in the Overdue tab
3. Verify it does NOT appear in the Pending tab

### Test AI Quota Error:
1. Use the AI feature until quota is exceeded
2. Verify you see the message: "You are out of AI tokens. Please wait or check your Gemini API quota."
3. Verify the battery icon appears (orange color)
4. Verify the Retry button works
