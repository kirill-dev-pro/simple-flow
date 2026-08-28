# Simple Flow: macOS Push-to-Talk Dictation Design

**Status:** Approved

**Date:** 2026-08-28

**Target:** Personal macOS application, macOS 14+

## Summary

Simple Flow is a native menu bar application for push-to-talk dictation. The
user holds a global hotkey (Fn by default), speaks, and releases the key. The
application sends the captured audio to a configurable OpenAI-compatible
speech-to-text endpoint. If the original text input is still focused when the
response arrives, the transcript is pasted into it. Every successful transcript
is saved in a local history and can be copied later.

The first version is deliberately personal and minimal: no App Store release,
accounts, sync, analytics, auto-update, or retained audio.

## Goals

- Start and stop microphone recording with a global push-to-talk hotkey.
- Use Fn by default and allow the hotkey to be changed in Settings.
- Send recordings to a configurable OpenAI-compatible transcription API.
- Paste into the same input that was focused when recording began.
- Never redirect focus or paste into a different input.
- Keep a permanent, local history of successful transcripts.
- Provide clear recording, transcription, success, and error feedback.
- Use native macOS appearance and system controls.

## Non-goals

- Screen, system-audio, or camera recording.
- App Store distribution, code signing automation, or auto-update.
- Multiple simultaneous recordings or transcription requests.
- Streaming or partial transcription.
- Audio playback, audio history, or retrying failed audio.
- Accounts, cloud history, sync, analytics, or telemetry.
- AI rewriting, application-aware formatting, custom vocabulary, or search.

## Technology

Use Swift with SwiftUI for History and Settings, plus AppKit, CoreGraphics,
Accessibility, AVFoundation, and Security for system integration. Target macOS
14 or newer and avoid third-party dependencies.

A Swift implementation is the shortest path to microphone permissions, global
keyboard events, Accessibility APIs, pasteboard access, menu bar UI, Keychain,
and a single native `.app`. Rust/Tauri and Go/Wails would still require
macOS-specific native bridges for the core behavior.

The application is a menu bar agent with no normal Dock icon. It is not
sandboxed for the personal MVP.

## High-level architecture

### `AppCoordinator`

Owns the application state machine and coordinates all other components. Only
one dictation can be active at a time.

```text
idle -> recording -> transcribing -> completed -> idle
                   \-> cancelled -> idle
                   \-> error -> idle
```

Events that do not apply to the current state are ignored. In particular, a
new hotkey press while transcribing does not start another recording.

### `HotkeyMonitor`

Uses a global `CGEventTap` to observe key-down, key-up, and modifier flag
changes. It supports Fn as a standalone key and a user-configured key or key
combination. Repeated key-down events do not restart recording. Escape cancels
only while the application is recording.

The event tap must run without activating Simple Flow or changing the frontmost
application. Secure Keyboard Entry may prevent global shortcuts; that condition
should be surfaced as a diagnostic rather than silently ignored.

### `FocusTracker`

At the start of recording, captures a focus snapshot containing:

- the PID and name of the frontmost application;
- the focused Accessibility element, when available;
- enough Accessibility metadata to compare the element later without reading
  or storing its text.

Before insertion, it captures the current focus again. Insertion is allowed
only when the application PID and focused element match the original snapshot.
If no editable input was focused, the element disappeared, or focus changed,
the transcript is saved without insertion. Simple Flow never activates the old
application or moves focus back to it.

### `AudioRecorder`

Uses `AVAudioEngine` to read the selected microphone and `AVAudioConverter` to
produce mono, signed 16-bit PCM at 16 kHz. Blocks are written directly to a
temporary WAV file rather than accumulating the whole recording in memory.

This is GigaAM's native preprocessing format and uses approximately:

- 32 KB per second;
- 1.92 MB per minute;
- 9.6 MB for the five-minute maximum.

The recorder stops on hotkey release, Escape, microphone failure, or the
five-minute limit. A warning appears ten seconds before the limit. The temporary
file is deleted after every terminal outcome, including cancellation, network
failure, malformed response, and success.

### `TranscriptionClient`

Uses `URLSession` to send a multipart request:

```text
POST {baseURL}/audio/transcriptions
Authorization: Bearer {token}
Content-Type: multipart/form-data

file=<recording.wav>
model=<configured model>
response_format=json
```

The Base URL represents an OpenAI-style API root such as
`https://host.example/v1`; trailing slashes are normalized before appending
`audio/transcriptions`. The expected success response contains a non-empty
top-level `text` string. The client distinguishes invalid configuration,
transport errors, timeouts, non-2xx responses, malformed JSON, and empty speech.

The API token is fetched from Keychain only when needed and must never be
included in logs or UI diagnostics.

### `TextInserter`

Automatic insertion follows the broadly compatible macOS paste path:

1. Save every current `NSPasteboard` item, including all available data types.
2. Put the transcript on the pasteboard as text.
3. Synthesize the standard Command-V shortcut with CoreGraphics.
4. After a short delay, restore the previous pasteboard contents only if its
   change count shows that the user or another application did not modify it.

Accessibility permission is required to synthesize input in other applications.
Direct mutation through `AXUIElement` is not the primary insertion path because
many web views, Electron applications, terminals, and custom editors expose
incomplete writable Accessibility attributes.

The transcript is persisted before insertion is attempted, so paste failure can
never lose recognized text.

### `HistoryStore`

Uses SwiftData for successful transcript records. History is local and has no
automatic retention limit; expected text volume is small. New records sort
first.

```text
TranscriptRecord
- id: UUID
- text: String
- createdAt: Date
- sourceApplicationName: String?
- insertionStatus: inserted | focusChanged | pasteFailed
```

Failed API calls do not create empty history records because they contain no
recognized text. Individual records can be deleted, and the complete history
can be cleared after confirmation.

### `SettingsStore`

Stores Base URL, model, selected microphone identifier, hotkey, and launch-at-
login preference in `UserDefaults`. Stores the API token in macOS Keychain.
The default hotkey is Fn. Launch at Login is off by default.

### `FloatingHUDController`

Owns a small, non-activating panel centered near the bottom of the active
screen. It must not steal keyboard focus. Its states are:

- Recording: red indicator, elapsed time, and “Esc to cancel”.
- Limit warning: remaining seconds before the five-minute cutoff.
- Transcribing: progress spinner without a fabricated percentage.
- Inserted: short success confirmation.
- Saved to history: focus changed or insertion was unavailable.
- Error: concise actionable failure message.

The panel disappears automatically after terminal feedback.

## End-to-end flow

1. The user focuses a text input and presses Fn.
2. `HotkeyMonitor` sends `startRecording` once.
3. `FocusTracker` captures the current focus snapshot.
4. `AudioRecorder` creates a temporary WAV and begins writing microphone audio.
5. The floating HUD shows Recording without activating Simple Flow.
6. The user releases Fn.
7. Recording closes and the HUD changes to Transcribing.
8. `TranscriptionClient` uploads the WAV.
9. The temporary WAV is deleted regardless of the request outcome.
10. A successful non-empty transcript is saved to history.
11. `FocusTracker` validates that the original input is still focused.
12. If it matches, `TextInserter` pastes and safely restores the clipboard.
13. Otherwise, no paste occurs and the HUD says the text was saved to history.

Escape during step 4 stops recording, deletes the file, creates no history
record, performs no request, and returns to Idle.

At five minutes, the application behaves as though the user released the
hotkey. A warning is shown during the final ten seconds.

## User interface

Use standard SwiftUI controls, system fonts, semantic colors, macOS spacing,
and native window materials. Do not introduce a custom visual design system.

### Menu bar

The microphone icon reflects Idle, Recording, Transcribing, and Error. Its menu
contains:

- current status or most recent actionable error;
- `History…`;
- `Copy Last Transcript`;
- `Settings…`;
- `Quit`.

### History window

Shows a native list sorted newest first. Each row shows a text preview, time,
source application, insertion status, and Copy button. Selecting a row reveals
the full text. The window supports deleting one record and clearing all history
with confirmation. Search and transcript editing are deferred.

### Settings window

Contains:

- Base URL;
- masked API token with show/hide control;
- model name;
- microphone picker;
- hotkey recorder;
- connection test;
- Microphone and Accessibility permission status with buttons to open the
  relevant System Settings panes;
- Launch at Login toggle, off by default.

The connection test should validate configuration and make a lightweight
OpenAI-compatible request where the server supports it. An unsupported models
endpoint must be reported distinctly from invalid credentials; it must not be
treated as proof that transcription is broken.

### First launch

Present a short native onboarding window that explains and requests Microphone
and Accessibility access. If a permission was denied, show its current status
and open the relevant System Settings page. Do not request unrelated access.

## Error handling

- Missing microphone permission: do not record; show an action to grant access.
- Missing Accessibility permission: global Fn monitoring and automatic
  insertion are unavailable, so push-to-talk does not start. If access is
  revoked during an active recording, finish transcription and save the result
  to history without attempting insertion.
- Microphone unavailable or disconnected: stop, delete audio, and show an error.
- Invalid URL, missing model, or missing token: fail before recording upload.
- Offline, timeout, or non-2xx response: delete audio and show a concise error.
- Empty transcript: report that no speech was recognized; save no history row.
- Changed or missing focus: save history normally and do not paste.
- Paste failure: keep history, leave the transcript recoverable through Copy,
  and show Saved to history.
- Clipboard changed after synthetic paste: preserve the user's newer clipboard
  instead of restoring stale content.

Errors remain available in the menu bar after the transient HUD disappears.

## Privacy and logging

- Audio exists only as a temporary local file during recording and the request.
- Audio is deleted on every success, failure, or cancellation path.
- Transcript history never leaves the Mac except through the configured API
  response flow and explicit user copying.
- Logs must not contain tokens, audio, clipboard contents, or transcript text.
- Safe diagnostics include timestamps, state transitions, duration, file size,
  target application name, HTTP status, and typed error categories.

## Testing strategy

Unit tests cover:

- valid and invalid `AppCoordinator` state transitions;
- duplicate key-down and unexpected key-up handling;
- five-minute cutoff and Escape cancellation;
- focus snapshot comparison;
- WAV output properties and duration calculations;
- multipart body construction and response decoding;
- network error mapping using `URLProtocol` mocks;
- SwiftData insertion, ordering, deletion, and clearing with an in-memory store;
- pasteboard restoration rules when the change count is unchanged or changed.

Manual integration checks cover TextEdit, Safari, Telegram or Slack, VS Code,
and Terminal. Each target is tested for normal insertion, selection replacement,
focus changes during transcription, missing permissions, offline behavior,
Escape, maximum duration, clipboard preservation, and Copy from History.

A real-endpoint smoke test performs ten consecutive short dictations. All ten
must either paste into the unchanged original input or, when focus is
intentionally changed, appear in history without being pasted elsewhere.

## Acceptance criteria

- Holding Fn starts one recording and releasing it submits one request.
- Escape cancels without a request or history entry.
- Recordings are 16 kHz, mono, PCM16 WAV and never exceed five minutes.
- No temporary audio remains after any terminal path.
- A valid API response is persisted before insertion is attempted.
- Text is pasted only when the original application and input remain focused.
- Changed focus never causes application activation or insertion elsewhere.
- The previous clipboard is restored unless a newer clipboard change occurred.
- Every successful transcript remains available in newest-first history with a
  one-click Copy action.
- Settings persist, while the API token is stored only in Keychain.
- The application uses native macOS visuals and does not steal focus with its
  menu bar UI or floating HUD.
