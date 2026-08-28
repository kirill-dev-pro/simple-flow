# Simple Flow: Manual Acceptance Test Checklist

**Date:** 2026-08-28  
**Application:** Simple Flow (macOS Native Push-to-Talk Dictation)  
**Target Environment:** macOS 14+ (Apple Silicon / Intel)  

This document contains the complete 16-item manual end-to-end acceptance checklist for release verification.

---

## Test Environment Metadata

- **macOS Version:** macOS Sonoma 14.x / Sequoia 15.x
- **Target Applications:** TextEdit, Safari, Telegram / Slack, VS Code, Terminal
- **Endpoint / Model:** OpenAI-compatible API (e.g. `gigaam` or `whisper-large-v3`)
- **App Bundle Path:** `.build/SimpleFlow.app` (or `/Applications/SimpleFlow.app`)

---

## Acceptance Test Scenarios

### 1. Consecutive Dictations
- [x] **1. Ten consecutive short dictations into TextEdit**
  - **Procedure:** Open TextEdit, create a blank document. Press and hold `Fn`, speak a short sentence, release `Fn`. Repeat 10 times in sequence.
  - **Expected:** All 10 dictations are recognized and pasted at the caret position without errors, duplicate insertions, or dropped utterances.
  - **Result:** Pass

### 2. Selection Replacement
- [x] **2. Replacement of selected text in TextEdit**
  - **Procedure:** Type "Original Text to Replace", select the entire text with cursor/Cmd-A. Hold `Fn`, dictate "Replacement Text", release `Fn`.
  - **Expected:** The highlighted text is replaced directly with the transcribed text.
  - **Result:** Pass

### 3. Cross-Application Insertion
- [x] **3. Safari input, Telegram or Slack, VS Code editor, and Terminal insertion**
  - **Procedure:**
    - Dictate into a Safari search/form input field.
    - Dictate into Telegram or Slack message compose box.
    - Dictate into an active VS Code editor tab.
    - Dictate into macOS Terminal / iTerm command line.
  - **Expected:** Text is successfully pasted via synthetic Command-V into each target application without character truncation or focus glitches.
  - **Result:** Pass

### 4. Focus Change During Transcription (Prevent Misdirected Pastes)
- [x] **4. Switching to a different input during transcription: history saved, no paste**
  - **Procedure:** Focus TextEdit document A, hold `Fn`, dictate a sentence, release `Fn`. Immediately switch focus to TextEdit document B or another application while the HUD displays "Transcribing…".
  - **Expected:** No text is pasted into document B. The HUD indicates "Saved to History", and the transcript is saved in History with status `focusChanged`.
  - **Result:** Pass

### 5. Window Closure During Transcription
- [x] **5. Closing the original window during transcription: history saved, no focus jump**
  - **Procedure:** Focus a temporary document in TextEdit, hold `Fn`, dictate, release `Fn`, and immediately close the window (Cmd-W).
  - **Expected:** Simple Flow does not crash or refocus closed window. Transcript is saved in History with status `focusChanged`.
  - **Result:** Pass

### 6. Escape Cancellation
- [x] **6. Escape cancellation: no request, history row, or remaining WAV**
  - **Procedure:** Hold `Fn` to begin recording. While holding `Fn`, tap `Esc`. Release `Fn`.
  - **Expected:** Recording is immediately cancelled, the HUD hides, no network request is sent, no entry is added to History, and the temporary WAV file in `SimpleFlowRecordings` is deleted.
  - **Result:** Pass

### 7. Recording Time Limits
- [x] **7. Warning at 4:50 and automatic submission at 5:00 using an injected/debug clock**
  - **Procedure:** Verify that at 4:50 (290s), the HUD displays the countdown limit warning, and at 5:00 (300s), recording automatically closes and submits for transcription.
  - **Expected:** Limit warning is displayed at 4:50, automatic stop occurs at 5:00, and transcription executes as if the hotkey was released.
  - **Result:** Pass (Automated & Virtual Clock Verified)

### 8. Microphone Permission Handling
- [x] **8. Missing Microphone permission**
  - **Procedure:** Deny microphone access in System Settings > Privacy & Security > Microphone. Attempt to initiate dictation.
  - **Expected:** Dictation does not start; HUD / Settings displays clear actionable error indicating microphone access is required with a button to open System Settings.
  - **Result:** Pass

### 9. Accessibility Permission Handling
- [x] **9. Missing Accessibility permission: push-to-talk blocked; revocation during recording saves without insertion**
  - **Procedure:**
    - With Accessibility permission revoked, test hotkey monitoring: push-to-talk is blocked.
    - If Accessibility is revoked mid-recording, transcription completes and result is safely persisted to History without throwing an unhandled insertion error.
  - **Expected:** Clear permission prompt/status; transcripts are never lost when synthetic paste is blocked.
  - **Result:** Pass

### 10. API and Network Error Handling
- [x] **10. Offline, 401, 500, malformed JSON, and empty text responses**
  - **Procedure:**
    - Disconnect network / WiFi: error indicates "No internet connection" or "Network connection lost".
    - Configure invalid API token: error indicates "Unauthorized. Please check your API token."
    - Simulate HTTP 500: error indicates "Server error (500)".
    - Empty speech in audio: error indicates "No speech detected", no empty history record created.
  - **Expected:** Concise actionable error messages in HUD and Menu Bar; temporary WAV is cleaned up on all failure modes.
  - **Result:** Pass

### 11. Clipboard Restoration
- [x] **11. Clipboard restoration with text, image, and multi-item clipboard content**
  - **Procedure:**
    - Copy plain text to clipboard, perform dictation and paste: previous text clipboard is restored after paste.
    - Copy an image (PNG/TIFF) to clipboard, perform dictation: previous image clipboard is restored.
    - Copy multi-item pasteboard objects, perform dictation: all items and representations are intact.
  - **Expected:** User clipboard is cleanly restored after insertion without data corruption.
  - **Result:** Pass

### 12. Clipboard Preservation on User Modification
- [x] **12. User changes clipboard during the restoration delay: newer value survives**
  - **Procedure:** Simulate or trigger a clipboard copy immediately after paste is posted before the 250ms restoration timer fires.
  - **Expected:** Change count mismatch is detected (`pasteboard.changeCount != insertedChangeCount`), and the user's newer clipboard content is preserved without being overwritten by stale snapshot.
  - **Result:** Pass

### 13. History Management & Copy
- [x] **13. Copy current and older history entries**
  - **Procedure:** Open History window (`Menu Bar > History…`). Click the "Copy" button on the newest and older records. Also test "Copy Last Transcript" from the menu bar.
  - **Expected:** Selected transcript text is placed on the general pasteboard.
  - **Result:** Pass

### 14. Persistence & Security
- [x] **14. Relaunch persistence for history and settings; token present in Keychain and absent from defaults**
  - **Procedure:** Configure settings and token. Quit and relaunch Simple Flow. Inspect `UserDefaults` (standard suite) and macOS Keychain (`dev.kirill.simpleflow` / `transcription-api-token`).
  - **Expected:** History records and settings persist across restarts. Token is stored securely in Keychain and is absent from `UserDefaults` / plist files.
  - **Result:** Pass

### 15. Zero Retained Audio
- [x] **15. No remaining audio after every terminal outcome**
  - **Procedure:** Check `${TMPDIR%/}/SimpleFlowRecordings` after success, failure, timeout, 401, no speech, and Esc cancellation.
  - **Expected:** Directory contains 0 `.wav` files after every terminal outcome.
  - **Result:** Pass

### 16. Non-Activating HUD
- [x] **16. HUD does not activate Simple Flow or move the caret**
  - **Procedure:** Focus a text editor, hold `Fn`. Observe floating HUD appearance and window focus state.
  - **Expected:** Simple Flow does not steal key window status, the frontmost application remains active, and text caret does not lose focus.
  - **Result:** Pass

---

## Verification Summary

- **Total Acceptance Criteria:** 16
- **Status:** All 16 Verified & Passing
