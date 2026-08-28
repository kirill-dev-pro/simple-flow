# Simple Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal native macOS menu bar application that records push-to-talk audio, transcribes it through a configurable OpenAI-compatible API, safely pastes into the unchanged focused input, and stores successful transcripts in local history.

**Architecture:** A SwiftUI menu bar agent owns an explicit dictation state machine. Small adapters isolate AVFoundation recording, CoreGraphics hotkeys, Accessibility focus tracking, pasteboard insertion, URLSession transcription, Keychain settings, and SwiftData history so deterministic behavior is unit-testable without global system side effects.

**Tech Stack:** Swift 5.9+, Swift Package Manager, SwiftUI, AppKit, AVFoundation, CoreGraphics, ApplicationServices, SwiftData, Security, ServiceManagement, OSLog, XCTest; macOS 14+; no third-party dependencies.

**Spec:** `docs/plans/2026-08-28-simple-flow-design.md`

## Global Constraints

- Target macOS 14 or newer.
- Build a personal, non-sandboxed menu bar agent with no normal Dock icon.
- Use only Apple frameworks and native macOS visuals.
- Default push-to-talk hotkey is standalone Fn; Escape cancels recording.
- Record mono 16 kHz signed PCM16 WAV, with a hard five-minute limit and a warning at 4:50.
- Allow only one active recording or transcription request.
- Send `POST {baseURL}/audio/transcriptions` as OpenAI-compatible multipart form data.
- Store the API token only in Keychain; do not log tokens, audio, transcript text, or clipboard contents.
- Delete temporary audio after success, failure, or cancellation.
- Persist every successful non-empty transcript before attempting insertion.
- Insert only if the application PID and focused Accessibility element still match the snapshot taken when recording began.
- Never reactivate an old application or redirect focus.
- Preserve every pasteboard item and restore it only if no newer clipboard change occurred.
- Keep successful transcript history locally without an automatic retention limit.
- Use test-driven development for each behavior-bearing task and commit after each task passes.

## File map

```text
Package.swift                                      SwiftPM products, targets, platform
Packaging/Info.plist                               app identity, LSUIElement, microphone text
scripts/build-app.sh                               build and ad-hoc-sign .build/SimpleFlow.app
Sources/SimpleFlow/
  App/SimpleFlowApp.swift                          SwiftUI scenes and app entry point
  App/AppDelegate.swift                            activation policy and startup wiring
  App/AppIdentity.swift                            stable bundle and Keychain identifiers
  App/AppCoordinator.swift                         end-to-end orchestration
  App/DictationStateMachine.swift                  legal phases and transitions
  Audio/AudioRecorder.swift                        AVAudioEngine capture and WAV conversion
  Audio/AudioRecording.swift                       recording protocol and value types
  Focus/FocusSnapshot.swift                        comparable captured focus identity
  Focus/SystemFocusTracker.swift                   Accessibility focus capture
  History/TranscriptRecord.swift                   SwiftData model and insertion status
  History/HistoryRepository.swift                  history operations
  Hotkey/Hotkey.swift                              Codable hotkey representation
  Hotkey/HotkeyMonitor.swift                       CGEventTap and Fn/Escape handling
  Insertion/PasteboardClient.swift                 full pasteboard snapshot and restoration
  Insertion/TextInserter.swift                     synthetic Command-V workflow
  Networking/MultipartFormData.swift               deterministic multipart encoding
  Networking/TranscriptionClient.swift             request execution and response decoding
  Networking/TranscriptionConfiguration.swift      validated endpoint configuration
  Settings/KeychainStore.swift                     token storage
  Settings/SettingsStore.swift                     UserDefaults-backed preferences
  System/LaunchAtLoginController.swift             SMAppService adapter
  System/MicrophoneCatalog.swift                    input device enumeration
  System/PermissionManager.swift                    microphone and Accessibility status/actions
  UI/FloatingHUDController.swift                   non-activating NSPanel lifecycle
  UI/FloatingHUDView.swift                         native HUD content
  UI/HistoryView.swift                             newest-first transcript list
  UI/MenuBarContent.swift                          status menu and window actions
  UI/OnboardingViewModel.swift                     testable first-run permission logic
  UI/OnboardingView.swift                          first-run permission flow
  UI/SettingsViewModel.swift                       validation and settings side effects
  UI/SettingsView.swift                            endpoint, microphone, hotkey, permissions
Tests/SimpleFlowTests/
  DictationStateMachineTests.swift
  AudioRecorderTests.swift
  FocusSnapshotTests.swift
  HistoryRepositoryTests.swift
  HotkeyTests.swift
  MultipartFormDataTests.swift
  PasteboardClientTests.swift
  SetupViewModelTests.swift
  SettingsStoreTests.swift
  TextInserterTests.swift
  TranscriptionClientTests.swift
  AppCoordinatorTests.swift
  BootstrapTests.swift
```

---

### Task 1: Bootstrap a runnable menu bar app bundle

**Files:**
- Create: `Package.swift`
- Create: `Packaging/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `Sources/SimpleFlow/App/SimpleFlowApp.swift`
- Create: `Sources/SimpleFlow/App/AppDelegate.swift`
- Create: `Sources/SimpleFlow/App/AppIdentity.swift`
- Create: `Sources/SimpleFlow/UI/MenuBarContent.swift`
- Create: `Tests/SimpleFlowTests/BootstrapTests.swift`

**Interfaces:**
- Produces: executable product `SimpleFlow` and `.build/SimpleFlow.app` with bundle identifier `dev.kirill.simpleflow`.
- Produces: `AppDelegate` as the single native application delegate.
- Produces: `MenuBarContent` as the root menu view used by later tasks.

- [ ] **Step 1: Create the package and minimal SwiftUI entry point**

Use this package declaration:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleFlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SimpleFlow", targets: ["SimpleFlow"])],
    targets: [
        .executableTarget(name: "SimpleFlow", path: "Sources/SimpleFlow"),
        .testTarget(
            name: "SimpleFlowTests",
            dependencies: ["SimpleFlow"],
            path: "Tests/SimpleFlowTests"
        )
    ]
)
```

Define `AppIdentity.bundleIdentifier` as `dev.kirill.simpleflow`. The app entry
point must expose a menu bar scene and minimal static History and
Settings windows without activating a Dock icon:

```swift
@main
struct SimpleFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Simple Flow", systemImage: "mic") {
            MenuBarContent()
        }
        Window("History", id: "history") { Text("No transcripts yet") }
        Window("Settings", id: "settings") { Text("Settings") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

Create `BootstrapTests` with
`XCTAssertEqual(AppIdentity.bundleIdentifier, "dev.kirill.simpleflow")` so the
test target exists from the first build and the identifier has one source of
truth.

- [ ] **Step 2: Add bundle metadata and packaging script**

`Packaging/Info.plist` must include `CFBundleIdentifier=dev.kirill.simpleflow`,
`CFBundleExecutable=SimpleFlow`, `CFBundlePackageType=APPL`,
`LSMinimumSystemVersion=14.0`, `LSUIElement=true`, and a clear
`NSMicrophoneUsageDescription` explaining push-to-talk recording.

`scripts/build-app.sh` must use `set -euo pipefail`, accept `debug` or `release`,
run `swift build`, copy the executable and Info.plist into the standard app
bundle layout, and run:

```bash
codesign --force --sign - .build/SimpleFlow.app
```

Use only paths rooted in the repository. Mark the script executable.

- [ ] **Step 3: Verify package, bundle, and agent metadata**

Run:

```bash
swift test
scripts/build-app.sh debug
plutil -extract CFBundleIdentifier raw .build/SimpleFlow.app/Contents/Info.plist
plutil -extract LSUIElement raw .build/SimpleFlow.app/Contents/Info.plist
codesign --verify --deep --strict .build/SimpleFlow.app
```

Expected: `swift test` and signing exit 0, bundle identifier is
`dev.kirill.simpleflow`, and `LSUIElement` is `true`.

- [ ] **Step 4: Launch the bundle for a smoke check**

Run `open .build/SimpleFlow.app`, confirm a microphone icon appears in the menu
bar, History and Settings open from the menu, and no Dock icon appears. Quit
through the menu before continuing.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Packaging scripts Sources/SimpleFlow/App Sources/SimpleFlow/UI/MenuBarContent.swift Tests/SimpleFlowTests/BootstrapTests.swift
git commit -m "build: bootstrap native menu bar app"
```

---

### Task 2: Implement the deterministic dictation state machine

**Files:**
- Create: `Sources/SimpleFlow/App/DictationStateMachine.swift`
- Create: `Tests/SimpleFlowTests/DictationStateMachineTests.swift`

**Interfaces:**
- Produces: `DictationPhase`, `DictationEvent`, `FeedbackKind`, and `DictationStateMachine.handle(_:) -> [DictationEffect]`.
- Produces: effects consumed by `AppCoordinator` in Task 9: `captureFocus`, `startAudio`, `stopAndTranscribe`, `cancelAudio`, and `returnToIdle`.

- [ ] **Step 1: Write failing transition tests**

Cover at minimum:

```swift
func testPressFromIdleStartsRecording() {
    var machine = DictationStateMachine()
    XCTAssertEqual(machine.handle(.hotkeyPressed), [.captureFocus, .startAudio])
    XCTAssertEqual(machine.phase, .recording)
}

func testRepeatedPressWhileRecordingIsIgnored() {
    var machine = DictationStateMachine(phase: .recording)
    XCTAssertEqual(machine.handle(.hotkeyPressed), [])
}

func testReleaseStopsAndTranscribes() {
    var machine = DictationStateMachine(phase: .recording)
    XCTAssertEqual(machine.handle(.hotkeyReleased), [.stopAndTranscribe])
    XCTAssertEqual(machine.phase, .transcribing)
}

func testEscapeCancelsOnlyWhileRecording() {
    var recording = DictationStateMachine(phase: .recording)
    XCTAssertEqual(recording.handle(.escapePressed), [.cancelAudio, .returnToIdle])
    var idle = DictationStateMachine()
    XCTAssertEqual(idle.handle(.escapePressed), [])
}

func testLimitReachedUsesNormalSubmissionPath() {
    var machine = DictationStateMachine(phase: .recording)
    XCTAssertEqual(machine.handle(.recordingLimitReached), [.stopAndTranscribe])
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `swift test --filter DictationStateMachineTests`

Expected: compilation fails because the state machine types do not exist.

- [ ] **Step 3: Implement the smallest explicit state machine**

Use value types with no timers or I/O:

```swift
enum DictationPhase: Equatable { case idle, recording, transcribing, feedback(FeedbackKind) }
enum FeedbackKind: Equatable { case inserted, savedToHistory, cancelled, error(String) }
enum DictationEvent: Equatable {
    case hotkeyPressed, hotkeyReleased, escapePressed, recordingLimitReached
    case transcriptionInserted, transcriptionSaved, failed(String), feedbackExpired
}
enum DictationEffect: Equatable {
    case captureFocus, startAudio, stopAndTranscribe, cancelAudio, returnToIdle
}

struct DictationStateMachine {
    private(set) var phase: DictationPhase = .idle
    init(phase: DictationPhase = .idle) { self.phase = phase }
    mutating func handle(_ event: DictationEvent) -> [DictationEffect] {
        switch (phase, event) {
        case (.idle, .hotkeyPressed):
            phase = .recording
            return [.captureFocus, .startAudio]
        case (.recording, .hotkeyReleased), (.recording, .recordingLimitReached):
            phase = .transcribing
            return [.stopAndTranscribe]
        case (.recording, .escapePressed):
            phase = .idle
            return [.cancelAudio, .returnToIdle]
        case (.transcribing, .transcriptionInserted):
            phase = .feedback(.inserted)
            return []
        case (.transcribing, .transcriptionSaved):
            phase = .feedback(.savedToHistory)
            return []
        case (.recording, .failed(let message)), (.transcribing, .failed(let message)):
            phase = .feedback(.error(message))
            return []
        case (.feedback, .feedbackExpired):
            phase = .idle
            return [.returnToIdle]
        default:
            return []
        }
    }
}
```

Ensure every phase/event pair is handled explicitly. Feedback expiration returns
to Idle; presses during Transcribing and Feedback are ignored.

- [ ] **Step 4: Run tests and confirm GREEN**

Run: `swift test --filter DictationStateMachineTests`

Expected: all transition tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleFlow/App/DictationStateMachine.swift Tests/SimpleFlowTests/DictationStateMachineTests.swift
git commit -m "feat: add dictation state machine"
```

---

### Task 3: Add settings validation and Keychain-backed token storage

**Files:**
- Create: `Sources/SimpleFlow/Hotkey/Hotkey.swift`
- Create: `Sources/SimpleFlow/Networking/TranscriptionConfiguration.swift`
- Create: `Sources/SimpleFlow/Settings/KeychainStore.swift`
- Create: `Sources/SimpleFlow/Settings/SettingsStore.swift`
- Create: `Tests/SimpleFlowTests/HotkeyTests.swift`
- Create: `Tests/SimpleFlowTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `Hotkey.functionKey` and Codable physical-key configurations.
- Produces: `TranscriptionConfiguration.validatedBaseURL() throws -> URL` and `validatedEndpoint() throws -> URL`.
- Produces: `SettingsStore.transcriptionConfiguration() throws -> TranscriptionConfiguration`.
- Produces: `TokenStoring` for a real Keychain adapter and in-memory tests.

- [ ] **Step 1: Write failing model and persistence tests**

Test Fn round-tripping, UserDefaults round-tripping in an isolated suite, token
storage through a fake, and URL normalization:

```swift
func testEndpointAppendsAudioTranscriptionsToV1Base() throws {
    let value = TranscriptionConfiguration(
        baseURL: "https://stt.example/v1/", token: "secret", model: "gigaam"
    )
    XCTAssertEqual(
        try value.validatedEndpoint().absoluteString,
        "https://stt.example/v1/audio/transcriptions"
    )
}

func testMissingTokenIsRejected() {
    let value = TranscriptionConfiguration(baseURL: "https://stt.example/v1", token: "", model: "gigaam")
    XCTAssertThrowsError(try value.validate())
}
```

Also assert that `SettingsStore` never writes the token into `UserDefaults`.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter 'HotkeyTests|SettingsStoreTests'`

Expected: compilation fails for missing configuration and settings types.

- [ ] **Step 3: Implement exact settings types**

Use:

```swift
struct Hotkey: Codable, Equatable {
    var keyCode: CGKeyCode?
    var modifiersRawValue: UInt64
    var isFunctionKeyOnly: Bool
    static let functionKey = Hotkey(keyCode: nil, modifiersRawValue: CGEventFlags.maskSecondaryFn.rawValue, isFunctionKeyOnly: true)
}

struct TranscriptionConfiguration: Equatable {
    let baseURL: String
    let token: String
    let model: String
    func validate() throws
    func validatedBaseURL() throws -> URL
    func validatedEndpoint() throws -> URL
}

protocol TokenStoring {
    func readToken() throws -> String?
    func writeToken(_ token: String) throws
    func deleteToken() throws
}
```

Implement `KeychainStore` with service `dev.kirill.simpleflow` and account
`transcription-api-token`. Store Base URL, model, microphone device UID, hotkey,
launch-at-login, and onboarding completion in `UserDefaults`.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter 'HotkeyTests|SettingsStoreTests'
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleFlow/Hotkey Sources/SimpleFlow/Networking/TranscriptionConfiguration.swift Sources/SimpleFlow/Settings Tests/SimpleFlowTests/HotkeyTests.swift Tests/SimpleFlowTests/SettingsStoreTests.swift
git commit -m "feat: persist transcription settings securely"
```

---

### Task 4: Implement the OpenAI-compatible transcription client

**Files:**
- Create: `Sources/SimpleFlow/Networking/MultipartFormData.swift`
- Create: `Sources/SimpleFlow/Networking/TranscriptionClient.swift`
- Create: `Tests/SimpleFlowTests/MultipartFormDataTests.swift`
- Create: `Tests/SimpleFlowTests/TranscriptionClientTests.swift`

**Interfaces:**
- Consumes: `TranscriptionConfiguration` from Task 3.
- Produces: `Transcribing.transcribe(fileURL:configuration:) async throws -> String`.
- Produces: `TranscriptionClient.testConnection(configuration:) async -> ConnectionTestResult`.

- [ ] **Step 1: Write failing multipart and response tests**

Use a fixed boundary in tests. Assert the body contains a WAV file part named
`file`, a `model` field, and `response_format=json`, each with correct CRLF
framing. Through a custom `URLProtocol`, assert:

```swift
func testTranscribeBuildsAuthorizedOpenAIRequest() async throws {
    let text = try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)
    XCTAssertEqual(text, "Распознанный текст")
    XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    XCTAssertEqual(capturedRequest?.url?.path, "/v1/audio/transcriptions")
}

func testEmptyTextThrowsNoSpeech() async {
    stub(status: 200, json: #"{"text":"   "}"#)
    await XCTAssertThrowsAsyncError(try await client.transcribe(fileURL: fixtureWAV, configuration: configuration)) {
        XCTAssertEqual($0 as? TranscriptionError, .noSpeech)
    }
}
```

Add cases for 401, 500, timeout, malformed JSON, and a local file read failure.
Provide an async XCTest helper in the test target rather than weakening error
assertions.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter 'MultipartFormDataTests|TranscriptionClientTests'`

Expected: compilation fails because the multipart encoder and client are absent.

- [ ] **Step 3: Implement deterministic encoding and typed errors**

Define:

```swift
protocol Transcribing {
    func transcribe(fileURL: URL, configuration: TranscriptionConfiguration) async throws -> String
}

enum TranscriptionError: Error, Equatable {
    case invalidConfiguration(String)
    case fileUnavailable
    case unauthorized
    case server(status: Int)
    case transport(URLError.Code)
    case malformedResponse
    case noSpeech
}
```

Use `URLSession.upload(for:from:)`, a 60-second request timeout, and a local
`Decodable` response containing `text`. Map errors without including response
bodies because servers may echo sensitive content.

For `testConnection`, request `{baseURL}/models`. Return `.reachable` for 2xx,
`.unauthorized` for 401/403, `.modelsEndpointUnsupported` for 404/405, and a
typed transport/server result otherwise. Do not claim transcription readiness
when the models endpoint is unsupported.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
swift test --filter 'MultipartFormDataTests|TranscriptionClientTests'
swift test
```

Expected: all tests pass and captured requests contain no token in their URL.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleFlow/Networking Tests/SimpleFlowTests/MultipartFormDataTests.swift Tests/SimpleFlowTests/TranscriptionClientTests.swift
git commit -m "feat: add OpenAI-compatible transcription client"
```

---

### Task 5: Persist successful transcript history and build its native UI

**Files:**
- Create: `Sources/SimpleFlow/History/TranscriptRecord.swift`
- Create: `Sources/SimpleFlow/History/HistoryRepository.swift`
- Create: `Sources/SimpleFlow/UI/HistoryView.swift`
- Modify: `Sources/SimpleFlow/App/SimpleFlowApp.swift`
- Create: `Tests/SimpleFlowTests/HistoryRepositoryTests.swift`

**Interfaces:**
- Produces: `InsertionStatus`, `TranscriptRecord`, and `HistoryRepository`.
- Produces: `HistoryStoring.save(text:sourceApplicationName:insertionStatus:) throws -> TranscriptRecord` and `updateInsertionStatus(_:to:) throws`.
- Produces: `HistoryView`, receiving a SwiftData model context through the environment.

- [ ] **Step 1: Write failing in-memory SwiftData tests**

Create a `ModelContainer` with `isStoredInMemoryOnly: true`. Verify save order,
status persistence, individual deletion, and clearing:

```swift
func testSuccessfulTranscriptsSortNewestFirst() throws {
    try repository.save(text: "older", createdAt: Date(timeIntervalSince1970: 1), sourceApplicationName: "TextEdit", insertionStatus: .inserted)
    try repository.save(text: "newer", createdAt: Date(timeIntervalSince1970: 2), sourceApplicationName: "Safari", insertionStatus: .focusChanged)
    XCTAssertEqual(try repository.fetchAll().map(\.text), ["newer", "older"])
}
```

- [ ] **Step 2: Run the history tests and confirm RED**

Run: `swift test --filter HistoryRepositoryTests`

Expected: compilation fails because history types do not exist.

- [ ] **Step 3: Implement the model and repository**

Use a raw string for stable persistence of the enum:

```swift
enum InsertionStatus: String, Codable, CaseIterable {
    case inserted, focusChanged, pasteFailed
}

@Model
final class TranscriptRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var sourceApplicationName: String?
    var insertionStatusRawValue: String

    var insertionStatus: InsertionStatus {
        get { InsertionStatus(rawValue: insertionStatusRawValue) ?? .pasteFailed }
        set { insertionStatusRawValue = newValue.rawValue }
    }
}
```

Reject empty or whitespace-only text at the repository boundary.

Implement the repository behind the coordinator-facing contract:

```swift
protocol HistoryStoring {
    @discardableResult
    func save(
        text: String,
        createdAt: Date,
        sourceApplicationName: String?,
        insertionStatus: InsertionStatus
    ) throws -> TranscriptRecord
    func updateInsertionStatus(_ record: TranscriptRecord, to status: InsertionStatus) throws
    func fetchAll() throws -> [TranscriptRecord]
    func delete(_ record: TranscriptRecord) throws
    func clear() throws
}

final class HistoryRepository: HistoryStoring {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }
}
```

Every mutating method calls `context.save()`. `fetchAll()` uses a fetch
descriptor sorted by `createdAt` descending.

- [ ] **Step 4: Build `HistoryView` with native controls**

Use `@Query(sort: \TranscriptRecord.createdAt, order: .reverse)`. Each row must
show a multiline preview, formatted time, source application, status label, and
a Copy button. Selection reveals full text. Add swipe/context deletion and a
`Clear History` toolbar action guarded by `confirmationDialog`. Copy only the
selected transcript string and do not perform synthetic Command-V.

Wire one shared `ModelContainer(for: TranscriptRecord.self)` into the app scene.

- [ ] **Step 5: Run tests and build**

Run:

```bash
swift test --filter HistoryRepositoryTests
swift test
swift build
```

Expected: tests and build pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SimpleFlow/History Sources/SimpleFlow/UI/HistoryView.swift Sources/SimpleFlow/App/SimpleFlowApp.swift Tests/SimpleFlowTests/HistoryRepositoryTests.swift
git commit -m "feat: add persistent transcript history"
```

---

### Task 6: Record compact GigaAM-ready WAV audio with a hard limit

**Files:**
- Create: `Sources/SimpleFlow/Audio/AudioRecording.swift`
- Create: `Sources/SimpleFlow/Audio/AudioRecorder.swift`
- Create: `Tests/SimpleFlowTests/AudioRecorderTests.swift`

**Interfaces:**
- Produces: `RecordedAudio`, `AudioRecording`, and concrete `AudioRecorder`.
- Produces: callbacks `onLimitWarning` at 290 seconds and `onLimitReached` at 300 seconds.
- Consumes later: microphone device UID from `SettingsStore`.

- [ ] **Step 1: Write failing WAV and lifecycle tests**

Separate conversion/writing from the live `AVAudioEngine` source so tests can
feed deterministic PCM buffers. Assert:

```swift
func testWriterProducesMono16kHzPCM16WAV() throws {
    let url = temporaryURL("test.wav")
    let writer = try PCM16WAVWriter(url: url)
    try writer.append(makeStereoFloatBuffer(sampleRate: 48_000, duration: 1))
    try writer.close()
    let file = try AVAudioFile(forReading: url)
    XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
    XCTAssertEqual(file.fileFormat.channelCount, 1)
    XCTAssertEqual(file.length, 16_000, accuracy: 2)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let byteCount = try XCTUnwrap(attributes[.size] as? NSNumber).int64Value
    XCTAssertLessThan(byteCount, 33_000)
}

func testCancelRemovesTemporaryFile() async throws {
    let recorder = makeRecorderWithDeterministicSource()
    try await recorder.start(deviceUID: nil)
    let url = try XCTUnwrap(recorder.currentTemporaryURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    await recorder.cancel()
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
}

func testStopReturnsExistingFileMetadata() async throws {
    let recorder = makeRecorderWithDeterministicSource(duration: 1)
    try await recorder.start(deviceUID: nil)
    let result = try await recorder.stop()
    XCTAssertEqual(result.duration, 1, accuracy: 0.01)
    XCTAssertGreaterThan(result.byteCount, 32_000)
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
    await recorder.remove(result)
    XCTAssertFalse(FileManager.default.fileExists(atPath: result.fileURL.path))
}
```

Test the 290/300-second timer logic with an injected clock or scheduler; never
make the test sleep for real time.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter AudioRecorderTests`

Expected: compilation fails because audio types do not exist.

- [ ] **Step 3: Implement public recording contracts**

```swift
struct RecordedAudio: Equatable {
    let fileURL: URL
    let duration: TimeInterval
    let byteCount: Int64
}

protocol AudioRecording: AnyObject {
    var onLimitWarning: (@Sendable () -> Void)? { get set }
    var onLimitReached: (@Sendable () -> Void)? { get set }
    func start(deviceUID: String?) async throws
    func stop() async throws -> RecordedAudio
    func cancel() async
    func remove(_ recording: RecordedAudio) async
}
```

Define typed errors for permission denied, no device, engine start failure,
conversion failure, and write failure.

- [ ] **Step 4: Implement live AVFoundation capture**

Use `AVAudioEngine.inputNode.installTap`, a serial audio queue, one
`AVAudioConverter`, and this target format:

```swift
AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16_000,
    channels: 1,
    interleaved: true
)!
```

Write converted blocks immediately with `AVAudioFile`. `stop()` must remove the
tap, stop the engine, drain the serial writer queue, close the file, cancel
timers, and return metadata. `cancel()` must perform the same shutdown and then
delete the file. Every thrown start/stop path must clean up its temporary URL.

Select a configured device by UID when present; if it disappeared, use the
current system default and report the fallback to Settings without failing the
dictation.

Resolve the stored CoreAudio UID to `AudioDeviceID`, then set
`kAudioOutputUnitProperty_CurrentDevice` on the input node's `AudioUnit` before
starting the engine. Keep that CoreAudio call in a small injected device adapter
so deterministic recorder tests do not depend on installed hardware.

- [ ] **Step 5: Run focused tests, full tests, and inspect a generated fixture**

Run:

```bash
swift test --filter AudioRecorderTests
swift test
swift build
```

Expected: all tests pass; the one-second fixture is mono, 16 kHz, 16-bit PCM and
approximately 32 KB plus its WAV header.

- [ ] **Step 6: Commit**

```bash
git add Sources/SimpleFlow/Audio Tests/SimpleFlowTests/AudioRecorderTests.swift
git commit -m "feat: record GigaAM-ready WAV audio"
```

---

### Task 7: Capture global Fn/hotkey and Escape events

**Files:**
- Create: `Sources/SimpleFlow/Hotkey/HotkeyMonitor.swift`
- Extend: `Tests/SimpleFlowTests/HotkeyTests.swift`

**Interfaces:**
- Consumes: `Hotkey` from Task 3.
- Produces: `HotkeyMonitoring.start(hotkey:onPress:onRelease:onCancel:) throws` and `stop()`.
- Produces callbacks delivered on `MainActor` exactly once per physical transition.
- Produces: `HotkeyMonitorDiagnostic.secureInputEnabled` by querying
  `IsSecureEventInputEnabled()` without recording unrelated keystrokes.

- [ ] **Step 1: Write failing event-decoder tests**

Keep CoreGraphics tap installation outside the pure decoder. Test sequences of
synthetic event descriptions:

```swift
func testFunctionFlagTransitionsEmitOnePressAndRelease() {
    var decoder = HotkeyEventDecoder(hotkey: .functionKey)
    XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskSecondaryFn]), cancelEnabled: false), .emit(.pressed))
    XCTAssertEqual(decoder.consume(.flagsChanged(flags: [.maskSecondaryFn]), cancelEnabled: false), .consume)
    XCTAssertEqual(decoder.consume(.flagsChanged(flags: []), cancelEnabled: false), .emit(.released))
}

func testEscapeDuringRecordingEmitsCancelAndSuppressesRepeat() {
    var decoder = HotkeyEventDecoder(hotkey: .functionKey)
    XCTAssertEqual(decoder.consume(.keyDown(keyCode: 53, flags: [], isRepeat: false), cancelEnabled: true), .emit(.cancel))
    XCTAssertEqual(decoder.consume(.keyDown(keyCode: 53, flags: [], isRepeat: true), cancelEnabled: true), .consume)
    XCTAssertEqual(decoder.consume(.keyUp(keyCode: 53, flags: []), cancelEnabled: true), .consume)
}

func testConfiguredKeyRequiresExactModifiers() {
    let hotkey = Hotkey(keyCode: 49, modifiersRawValue: CGEventFlags.maskAlternate.rawValue, isFunctionKeyOnly: false)
    var decoder = HotkeyEventDecoder(hotkey: hotkey)
    XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [], isRepeat: false), cancelEnabled: false), .passThrough)
    XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [.maskAlternate], isRepeat: false), cancelEnabled: false), .emit(.pressed))
}

func testKeyRepeatDoesNotEmitSecondPress() {
    let hotkey = Hotkey(keyCode: 49, modifiersRawValue: 0, isFunctionKeyOnly: false)
    var decoder = HotkeyEventDecoder(hotkey: hotkey)
    XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [], isRepeat: false), cancelEnabled: false), .emit(.pressed))
    XCTAssertEqual(decoder.consume(.keyDown(keyCode: 49, flags: [], isRepeat: true), cancelEnabled: false), .consume)
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter HotkeyTests`

Expected: missing decoder and monitor types fail compilation.

- [ ] **Step 3: Implement decoder and CGEventTap adapter**

Define:

```swift
enum HotkeyAction: Equatable { case pressed, released, cancel }
enum HotkeyDecision: Equatable { case passThrough, consume, emit(HotkeyAction) }
enum HotkeyInputEvent: Equatable {
    case flagsChanged(flags: CGEventFlags)
    case keyDown(keyCode: CGKeyCode, flags: CGEventFlags, isRepeat: Bool)
    case keyUp(keyCode: CGKeyCode, flags: CGEventFlags)
}

protocol HotkeyMonitoring: AnyObject {
    func start(
        hotkey: Hotkey,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) throws
    func stop()
}
```

Create a `CGEventTap` for `flagsChanged`, `keyDown`, and `keyUp`, attach its
run-loop source to `.commonModes`, and re-enable it after timeout/user-input
disable notifications. Consume only the configured trigger and Escape while
recording; pass unrelated events through unchanged. Fn state is the transition
of `CGEventFlags.maskSecondaryFn`.

If tap creation fails, throw `.accessibilityPermissionRequired`. Stop and
recreate the tap when settings change.

- [ ] **Step 4: Run tests and manual event smoke check**

Run:

```bash
swift test --filter HotkeyTests
swift test
scripts/build-app.sh debug
```

Launch the app after granting Accessibility. Confirm one press callback on Fn
down, one release callback on Fn up, no repeats while held, Escape cancellation,
and normal typing for unrelated keys.

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleFlow/Hotkey Tests/SimpleFlowTests/HotkeyTests.swift
git commit -m "feat: monitor global push-to-talk hotkey"
```

---

### Task 8: Guard insertion by focus identity and preserve the clipboard

**Files:**
- Create: `Sources/SimpleFlow/Focus/FocusSnapshot.swift`
- Create: `Sources/SimpleFlow/Focus/SystemFocusTracker.swift`
- Create: `Sources/SimpleFlow/Insertion/PasteboardClient.swift`
- Create: `Sources/SimpleFlow/Insertion/TextInserter.swift`
- Create: `Tests/SimpleFlowTests/FocusSnapshotTests.swift`
- Create: `Tests/SimpleFlowTests/PasteboardClientTests.swift`
- Create: `Tests/SimpleFlowTests/TextInserterTests.swift`

**Interfaces:**
- Produces: `FocusTracking.capture() -> FocusSnapshot?` and `stillMatches(_:) -> Bool`.
- Produces: `TextInserting.insert(_:) async -> InsertionResult`.
- Produces: `InsertionResult.inserted` or `.pasteFailed`; focus mismatch is decided by the coordinator before calling insertion.

- [ ] **Step 1: Write failing focus identity tests**

Use `AXUIElementCreateApplication` values to exercise `CFEqual` without reading
another application's UI:

```swift
func testSnapshotsMatchOnlySamePIDAndElement() {
    let element = AXUIElementCreateApplication(101)
    let original = FocusSnapshot(applicationPID: 101, applicationName: "A", element: element)
    XCTAssertTrue(original.matches(FocusSnapshot(applicationPID: 101, applicationName: "A", element: element)))
    XCTAssertFalse(original.matches(FocusSnapshot(applicationPID: 102, applicationName: "B", element: element)))
}
```

- [ ] **Step 2: Write failing pasteboard and inserter tests**

Use fake pasteboard, event poster, and scheduler adapters. Assert:

- every pasteboard item/type is snapshotted;
- Command-V is posted after the transcript is installed;
- restoration occurs when `changeCount == insertedChangeCount`;
- restoration is skipped after a simulated user clipboard change;
- an event-post failure returns `.pasteFailed` and leaves the transcript
  recoverable through history.

- [ ] **Step 3: Run focused tests and confirm RED**

Run: `swift test --filter 'FocusSnapshotTests|PasteboardClientTests|TextInserterTests'`

Expected: compilation fails for missing focus and insertion types.

- [ ] **Step 4: Implement Accessibility focus capture**

```swift
struct FocusSnapshot {
    let applicationPID: pid_t
    let applicationName: String?
    let element: AXUIElement

    func matches(_ other: FocusSnapshot) -> Bool {
        applicationPID == other.applicationPID && CFEqual(element, other.element)
    }
}

protocol FocusTracking {
    func capture() -> FocusSnapshot?
    func stillMatches(_ snapshot: FocusSnapshot) -> Bool
}
```

Use `NSWorkspace.shared.frontmostApplication` for PID/name and
`AXUIElementCreateSystemWide` plus `kAXFocusedUIElementAttribute` for the element.
Accept roles `kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole`, and focused
web/editable elements that expose a settable value or selected-text attribute.
Do not read or retain the input's value or selected text. Treat all AX failures
and clearly non-editable roles as no snapshot/match.

- [ ] **Step 5: Implement safe paste insertion**

Snapshot `[NSPasteboardItem]` as copied `[UTType/String: Data]` values, replace
with the transcript, post Command down/V down/V up/Command up with `CGEvent`, and
schedule restoration after 250 ms. Restore only when the pasteboard change count
equals the count returned immediately after installing the transcript.

Expose the system work through protocols so tests never touch the real global
clipboard or post real events.

- [ ] **Step 6: Run focused and full tests**

Run:

```bash
swift test --filter 'FocusSnapshotTests|PasteboardClientTests|TextInserterTests'
swift test
swift build
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SimpleFlow/Focus Sources/SimpleFlow/Insertion Tests/SimpleFlowTests/FocusSnapshotTests.swift Tests/SimpleFlowTests/PasteboardClientTests.swift Tests/SimpleFlowTests/TextInserterTests.swift
git commit -m "feat: paste only into unchanged focused input"
```

---

### Task 9: Wire the coordinator and non-activating floating HUD

**Files:**
- Create: `Sources/SimpleFlow/App/AppCoordinator.swift`
- Create: `Sources/SimpleFlow/UI/FloatingHUDController.swift`
- Create: `Sources/SimpleFlow/UI/FloatingHUDView.swift`
- Modify: `Sources/SimpleFlow/App/AppDelegate.swift`
- Create: `Tests/SimpleFlowTests/AppCoordinatorTests.swift`

**Interfaces:**
- Consumes: all protocols produced in Tasks 2–8.
- Produces: `@MainActor final class AppCoordinator: ObservableObject` with published phase/status and `start()`/`stop()` lifecycle.
- Produces: `HUDPresenting.show(_:)` and `hide()`.

- [ ] **Step 1: Write failing coordinator tests with fakes**

Cover the complete decisions, not Apple framework behavior:

```swift
func testSuccessfulTranscriptIsSavedBeforeInsertion() async throws {
    let harness = CoordinatorHarness(transcript: "hello", focusStillMatches: true)
    await harness.pressReleaseAndComplete()
    XCTAssertEqual(harness.calls, [
        .captureFocus, .startAudio, .stopAudio, .transcribe,
        .saveHistory(status: .pasteFailed), .insert,
        .updateHistory(status: .inserted), .removeAudio
    ])
}

func testChangedFocusSavesWithoutInsertion() async throws {
    let harness = CoordinatorHarness(transcript: "hello", focusStillMatches: false)
    await harness.pressReleaseAndComplete()
    XCTAssertFalse(harness.inserterWasCalled)
    XCTAssertEqual(harness.savedStatus, .focusChanged)
}

func testAPIFailureDeletesAudioAndCreatesNoHistory() async {
    let harness = CoordinatorHarness(transcriptionResult: .failure(.transport(.notConnectedToInternet)))
    await harness.pressReleaseAndComplete()
    XCTAssertEqual(harness.removeAudioCallCount, 1)
    XCTAssertTrue(harness.savedRecords.isEmpty)
    XCTAssertEqual(harness.presentedFeedback, .error("No internet connection"))
}

func testEscapeCancelsWithoutAPIOrHistory() async {
    let harness = CoordinatorHarness(transcript: "unused")
    await harness.pressThenEscape()
    XCTAssertEqual(harness.cancelAudioCallCount, 1)
    XCTAssertEqual(harness.transcribeCallCount, 0)
    XCTAssertTrue(harness.savedRecords.isEmpty)
}

func testSecondPressWhileTranscribingIsIgnored() async {
    let harness = CoordinatorHarness.withSuspendedTranscription()
    await harness.pressAndRelease()
    await harness.press()
    XCTAssertEqual(harness.startAudioCallCount, 1)
}

func testPasteFailureKeepsProvisionalPasteFailedStatus() async {
    let harness = CoordinatorHarness(transcript: "hello", focusStillMatches: true, insertionResult: .pasteFailed)
    await harness.pressReleaseAndComplete()
    XCTAssertEqual(harness.savedRecords.single?.insertionStatus, .pasteFailed)
    XCTAssertEqual(harness.presentedFeedback, .savedToHistory)
}
```

The test file must define `CoordinatorHarness`, `HarnessCall`, fake recorder,
transcriber, focus tracker, history repository, inserter, HUD, and an explicitly
resumable continuation for suspended transcription. The harness exposes the
counters and captured records asserted above; it must not call AVFoundation,
Accessibility, URLSession, SwiftData, or the real pasteboard.

To guarantee save-before-paste while retaining a truthful crash-safe status,
initially save the record with `.pasteFailed`, attempt insertion, and update
that same record to `.inserted` only after Command-V is posted successfully. On
focus mismatch, save directly as `.focusChanged`.

- [ ] **Step 2: Run coordinator tests and confirm RED**

Run: `swift test --filter AppCoordinatorTests`

Expected: compilation fails because `AppCoordinator` does not exist.

- [ ] **Step 3: Implement coordinator orchestration**

Make `AppCoordinator` `@MainActor`. Retain the original `FocusSnapshot` only for
the current dictation. Use `defer` in the transcription task to delete the WAV;
audio cleanup must also be inside the recorder so duplicate deletion is safe.

On success:

```swift
let matches = focusTracker.stillMatches(originalFocus)
let record = try history.save(
    text: text,
    sourceApplicationName: originalFocus.applicationName,
    insertionStatus: matches ? .pasteFailed : .focusChanged
)
guard matches else { showSavedFeedback(); return }
if await textInserter.insert(text) == .inserted {
    try history.updateInsertionStatus(record, to: .inserted)
    showInsertedFeedback()
} else {
    showSavedFeedback()
}
```

If no focus snapshot was captured, use `.focusChanged`. Map typed errors to short
user-facing copy without transcript/audio/token content.

- [ ] **Step 4: Implement a native non-activating HUD**

Use an `NSPanel` configured with `.nonactivatingPanel`, floating level,
`hidesOnDeactivate=false`, `isMovable=false`, `collectionBehavior` containing
`.canJoinAllSpaces` and `.fullScreenAuxiliary`, and `canBecomeKey=false`. Host
`FloatingHUDView` in `NSHostingView`.

Render native states for Recording with timer and Escape copy, 10-second limit
warning, Transcribing spinner, Inserted, Saved to history, and Error. Position
near the bottom center of the screen containing the original target application.
Terminal feedback auto-hides after 1.5 seconds; errors after 4 seconds.

- [ ] **Step 5: Wire startup and run tests**

Construct production adapters once in `AppDelegate`, start the coordinator after
launch, and stop event taps/audio during termination.

Run:

```bash
swift test --filter AppCoordinatorTests
swift test
scripts/build-app.sh debug
```

Expected: all tests/build pass. Manual launch confirms the HUD never steals
focus from TextEdit.

- [ ] **Step 6: Commit**

```bash
git add Sources/SimpleFlow/App Sources/SimpleFlow/UI/FloatingHUDController.swift Sources/SimpleFlow/UI/FloatingHUDView.swift Tests/SimpleFlowTests/AppCoordinatorTests.swift
git commit -m "feat: orchestrate push-to-talk dictation"
```

---

### Task 10: Complete permissions, microphone, settings, onboarding, and menu UI

**Files:**
- Create: `Sources/SimpleFlow/System/PermissionManager.swift`
- Create: `Sources/SimpleFlow/System/MicrophoneCatalog.swift`
- Create: `Sources/SimpleFlow/System/LaunchAtLoginController.swift`
- Create: `Sources/SimpleFlow/UI/SettingsViewModel.swift`
- Create: `Sources/SimpleFlow/UI/OnboardingViewModel.swift`
- Create: `Sources/SimpleFlow/UI/SettingsView.swift`
- Create: `Sources/SimpleFlow/UI/OnboardingView.swift`
- Modify: `Sources/SimpleFlow/UI/MenuBarContent.swift`
- Modify: `Sources/SimpleFlow/App/SimpleFlowApp.swift`
- Modify: `Sources/SimpleFlow/App/AppDelegate.swift`
- Create: `Tests/SimpleFlowTests/SetupViewModelTests.swift`

**Interfaces:**
- Consumes: stores, coordinator, hotkey, and network interfaces from earlier tasks.
- Produces: complete first-run flow and configuration UI.
- Produces: `PermissionManaging`, `MicrophoneCataloging`, and `LaunchAtLoginControlling` adapters injected into views.

- [ ] **Step 1: Write failing settings and onboarding view-model tests**

Use fake token, permission, connection-test, hotkey, and launch-at-login
adapters. Define `SetupHarness` in the test file and cover exact behavior:

```swift
func testApplyRejectsInvalidURLWithoutOverwritingStoredSettings() async {
    let harness = SetupHarness(existingBaseURL: "https://working.example/v1")
    harness.settingsViewModel.baseURL = "not a URL"
    await harness.settingsViewModel.apply()
    XCTAssertEqual(harness.persistedBaseURL, "https://working.example/v1")
    XCTAssertEqual(harness.settingsViewModel.errorMessage, "Enter a valid HTTPS URL")
}

func testChangingHotkeyRestartsMonitorAfterPersistence() async {
    let harness = SetupHarness()
    harness.settingsViewModel.hotkey = Hotkey(keyCode: 49, modifiersRawValue: 0, isFunctionKeyOnly: false)
    await harness.settingsViewModel.apply()
    XCTAssertEqual(Array(harness.calls.suffix(2)), [.saveHotkey, .restartHotkeyMonitor])
}

func testOnboardingRequiresBothPermissions() {
    let microphoneOnly = OnboardingViewModel(microphone: .granted, accessibility: .denied)
    XCTAssertFalse(microphoneOnly.canFinish)
    let complete = OnboardingViewModel(microphone: .granted, accessibility: .granted)
    XCTAssertTrue(complete.canFinish)
}

func testLaunchAtLoginFailureReturnsToggleToOff() async {
    let harness = SetupHarness(launchAtLoginResult: .failure(TestError.registrationDenied))
    await harness.settingsViewModel.setLaunchAtLogin(true)
    XCTAssertFalse(harness.settingsViewModel.launchAtLogin)
    XCTAssertEqual(harness.settingsViewModel.errorMessage, "Could not enable Launch at Login")
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter SetupViewModelTests`

Expected: compilation fails because the view models and system protocols do not exist.

- [ ] **Step 3: Add permission and device adapters**

Define permission status as `.notDetermined`, `.denied`, or `.granted`.
Microphone uses `AVCaptureDevice.authorizationStatus(for: .audio)` and
`requestAccess(for: .audio)`. Accessibility uses
`AXIsProcessTrustedWithOptions`; the request action may show the macOS prompt.
Buttons for denied status must open the exact Privacy & Security pane using the
documented `x-apple.systempreferences` URL.

Enumerate audio input devices with AVFoundation/CoreAudio and expose stable UID
plus display name. Include “System Default” as `nil`.

- [ ] **Step 4: Implement Settings with validation at the boundary**

Put validation and side effects in `@MainActor SettingsViewModel`; the SwiftUI
view only binds fields and sends actions. Build a standard SwiftUI `Form` with sections:

- API: Base URL, masked token with reveal toggle, Model, Test Connection result;
- Audio: microphone picker;
- Shortcut: current display string and a recorder sheet that captures Fn or one
  physical key with modifiers;
- Permissions: live Microphone and Accessibility status plus action buttons;
- General: Launch at Login.

Save text fields on explicit Apply, validate before writing, and keep the last
valid settings when validation fails. After changing hotkey, call the
coordinator to restart `HotkeyMonitor` with the new value.

Use `SMAppService.mainApp.register()`/`unregister()` in
`LaunchAtLoginController`. If registration is unavailable because the ad-hoc
personal app is not installed in a stable location, show the system error and
leave the toggle off.

- [ ] **Step 5: Implement first-run onboarding**

Show one compact native window on first launch with two permission rows:
Microphone and Accessibility. Explain each in one sentence. Request only when
the user clicks the row's button. Enable Finish only after Microphone and
Accessibility are granted because the global Fn event tap and synthetic
Command-V both depend on Accessibility. If Accessibility is revoked during an
active recording, allow that recording to finish transcription and save it to
history without attempting insertion.

Put `canFinish` and permission refresh/request actions in
`OnboardingViewModel`. Persist onboarding completion in `SettingsStore`.

- [ ] **Step 6: Finish menu bar behavior**

`MenuBarContent` must display phase-specific SF Symbols and provide:

- a non-interactive status/error row;
- History… using `openWindow(id: "history")`;
- Copy Last Transcript, disabled when history is empty;
- Settings… using `openWindow(id: "settings")`;
- Quit calling `NSApplication.shared.terminate(nil)`.

When `IsSecureEventInputEnabled()` is true, show a diagnostic row explaining
that Secure Keyboard Entry is blocking the push-to-talk shortcut.

Copy Last Transcript writes only the latest transcript to the pasteboard and
does not synthesize Command-V.

- [ ] **Step 7: Run tests, build, and manually verify settings/onboarding**

Run:

```bash
swift test
scripts/build-app.sh debug
codesign --verify --deep --strict .build/SimpleFlow.app
```

Launch with a fresh preferences domain and Keychain test token removed. Verify
onboarding, both permission states, token masking, API validation, microphone
selection, Fn and alternate hotkey capture, connection test outcomes, menu
actions, and a failed Launch at Login registration message when applicable.

- [ ] **Step 8: Commit**

```bash
git add Sources/SimpleFlow/System Sources/SimpleFlow/UI Sources/SimpleFlow/App Tests/SimpleFlowTests/SetupViewModelTests.swift
git commit -m "feat: add native setup and settings experience"
```

---

### Task 11: Harden privacy, cleanup, packaging, and end-to-end acceptance

**Files:**
- Modify: `Sources/SimpleFlow/App/AppCoordinator.swift`
- Modify: `Sources/SimpleFlow/Audio/AudioRecorder.swift`
- Modify: `Sources/SimpleFlow/Networking/TranscriptionClient.swift`
- Modify: `Sources/SimpleFlow/Insertion/PasteboardClient.swift`
- Modify: `Sources/SimpleFlow/UI/MenuBarContent.swift`
- Modify: `scripts/build-app.sh`
- Modify: `Tests/SimpleFlowTests/AudioRecorderTests.swift`
- Create: `docs/manual-test-checklist.md`

**Interfaces:**
- Consumes: the complete application.
- Produces: a release app bundle and recorded evidence that every acceptance criterion was exercised.

- [ ] **Step 1: Add privacy-safe structured logging**

Use `Logger` categories `lifecycle`, `audio`, `network`, `focus`, and `insertion`.
Log state, duration, file size, application name, HTTP status, and typed error
case only. Search all logger and print calls and remove any interpolation of
token, transcript, pasteboard values, multipart body, or audio bytes.

- [ ] **Step 2: Add process-restart cleanup for abandoned temporary WAVs**

Store recordings only under a dedicated directory such as
`FileManager.default.temporaryDirectory/SimpleFlowRecordings`. On startup,
delete `.wav` files in exactly that directory that are older than one hour.
Never recursively delete a broader temp directory. Add a unit test that creates
old/new/non-WAV files and confirms only old WAV files in the dedicated directory
are removed.

- [ ] **Step 3: Write the exact manual acceptance checklist**

`docs/manual-test-checklist.md` must include checkboxes for:

1. Ten consecutive short dictations into TextEdit.
2. Replacement of selected text in TextEdit.
3. Safari input, Telegram or Slack, VS Code editor, and Terminal insertion.
4. Switching to a different input during transcription: history saved, no paste.
5. Closing the original window during transcription: history saved, no focus jump.
6. Escape cancellation: no request, history row, or remaining WAV.
7. Warning at 4:50 and automatic submission at 5:00 using an injected/debug clock.
8. Missing Microphone permission.
9. Missing Accessibility permission: push-to-talk is blocked with a permission
   action; revocation during an active recording saves without insertion.
10. Offline, 401, 500, malformed JSON, and empty text responses.
11. Clipboard restoration with text, image, and multi-item clipboard content.
12. User changes clipboard during the restoration delay: newer value survives.
13. Copy current and older history entries.
14. Relaunch persistence for history and settings; token present in Keychain and absent from defaults.
15. No remaining audio after every terminal outcome.
16. HUD does not activate Simple Flow or move the caret.

- [ ] **Step 4: Run the complete automated verification suite**

Run:

```bash
swift test
swift build -c release
scripts/build-app.sh release
codesign --verify --deep --strict .build/SimpleFlow.app
plutil -lint .build/SimpleFlow.app/Contents/Info.plist
git diff --check
```

Expected: every command exits 0 and all XCTest cases pass with zero failures.

- [ ] **Step 5: Run the manual checklist with a real endpoint**

Install or move the app to a stable local path before granting final macOS
permissions so TCC associates them with the stable bundle. Configure the real
Base URL, token, and model. Complete every checklist row and record macOS
version, target applications, endpoint model, and result beside each checkbox.

If a row fails, add a focused failing automated test when the behavior is
deterministic, fix it, rerun the focused test, then rerun Steps 4 and 5.

- [ ] **Step 6: Audit spec coverage and repository state**

Run:

```bash
rg -n 'token|transcript|pasteboard|audio' Sources/SimpleFlow
find "${TMPDIR%/}/SimpleFlowRecordings" -maxdepth 1 -type f -name '*.wav' -print 2>/dev/null
git status --short
```

Manually inspect every logging match. Expected: no sensitive values are logged,
no abandoned WAV is listed after completed test scenarios, and the working tree
contains only the intended checklist updates.

- [ ] **Step 7: Commit the release-ready result**

```bash
git add Sources/SimpleFlow scripts/build-app.sh docs/manual-test-checklist.md Tests/SimpleFlowTests
git commit -m "chore: harden Simple Flow for personal release"
```

- [ ] **Step 8: Capture final evidence**

Run once more after the final commit:

```bash
swift test
scripts/build-app.sh release
codesign --verify --deep --strict .build/SimpleFlow.app
git status --short
git log --oneline --decorate -12
```

Expected: tests pass, the app bundle verifies, the working tree is clean, and
the task commits appear in order.

## Executor handoff notes

- Read the design spec before Task 1 and keep it open during reviews.
- Execute tasks in order; later task interfaces intentionally depend on earlier ones.
- Use a fresh implementation subagent per task with specification review followed by code-quality review.
- Do not grant system permissions to a changing temporary bundle path repeatedly; use the stable built app location for final manual testing.
- If Fn delivery differs on the executor's macOS/hardware, capture raw `flagsChanged` diagnostics without logging other keystrokes, add a decoder fixture, and keep standalone Fn as the default.
- Do not broaden the MVP with streaming, retained audio, context-aware rewriting, sync, search, or updater work.
