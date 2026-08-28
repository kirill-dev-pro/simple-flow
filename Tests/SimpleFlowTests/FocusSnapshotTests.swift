import ApplicationServices
import XCTest
@testable import SimpleFlow

final class FocusSnapshotTests: XCTestCase {
    func testSnapshotsMatchOnlySamePIDAndElement() {
        let elementA = AXUIElementCreateApplication(101)
        let elementB = AXUIElementCreateApplication(102)

        let original = FocusSnapshot(applicationPID: 101, applicationName: "AppA", element: elementA)
        let sameIdentity = FocusSnapshot(applicationPID: 101, applicationName: "AppA", element: elementA)
        let differentPID = FocusSnapshot(applicationPID: 102, applicationName: "AppB", element: elementA)
        let differentElement = FocusSnapshot(applicationPID: 101, applicationName: "AppA", element: elementB)

        XCTAssertTrue(original.matches(sameIdentity))
        XCTAssertEqual(original, sameIdentity)

        XCTAssertFalse(original.matches(differentPID))
        XCTAssertNotEqual(original, differentPID)

        XCTAssertFalse(original.matches(differentElement))
        XCTAssertNotEqual(original, differentElement)
    }

    func testSystemFocusTrackerCaptureReturnsNilWhenNoApp() {
        let tracker = SystemFocusTracker(
            frontmostAppProvider: { nil },
            systemWideElementProvider: { AXUIElementCreateApplication(101) },
            editableValidator: { _ in true }
        )

        XCTAssertNil(tracker.capture())
        let snapshot = FocusSnapshot(applicationPID: 101, applicationName: "AppA", element: AXUIElementCreateApplication(101))
        XCTAssertFalse(tracker.stillMatches(snapshot))
    }

    func testSystemFocusTrackerCaptureReturnsNilWhenNoFocusedElement() {
        let tracker = SystemFocusTracker(
            frontmostAppProvider: { (pid: 101, name: "AppA") },
            systemWideElementProvider: { nil },
            editableValidator: { _ in true }
        )

        XCTAssertNil(tracker.capture())
        let snapshot = FocusSnapshot(applicationPID: 101, applicationName: "AppA", element: AXUIElementCreateApplication(101))
        XCTAssertFalse(tracker.stillMatches(snapshot))
    }

    func testSystemFocusTrackerCaptureReturnsNilWhenElementNotEditable() {
        let tracker = SystemFocusTracker(
            frontmostAppProvider: { (pid: 101, name: "AppA") },
            systemWideElementProvider: { AXUIElementCreateApplication(101) },
            editableValidator: { _ in false }
        )

        XCTAssertNil(tracker.capture())
        let snapshot = FocusSnapshot(applicationPID: 101, applicationName: "AppA", element: AXUIElementCreateApplication(101))
        XCTAssertFalse(tracker.stillMatches(snapshot))
    }

    final class FocusTestState: @unchecked Sendable {
        var currentElement: AXUIElement?
        var currentPID: pid_t

        init(currentElement: AXUIElement?, currentPID: pid_t) {
            self.currentElement = currentElement
            self.currentPID = currentPID
        }
    }

    func testSystemFocusTrackerCaptureSuccessAndStillMatches() {
        let element = AXUIElementCreateApplication(101)
        let state = FocusTestState(currentElement: element, currentPID: 101)

        let tracker = SystemFocusTracker(
            frontmostAppProvider: { [state] in (pid: state.currentPID, name: "AppA") },
            systemWideElementProvider: { [state] in state.currentElement },
            editableValidator: { _ in true }
        )

        guard let snapshot = tracker.capture() else {
            XCTFail("Expected capture to succeed")
            return
        }

        XCTAssertEqual(snapshot.applicationPID, 101)
        XCTAssertEqual(snapshot.applicationName, "AppA")
        XCTAssertTrue(tracker.stillMatches(snapshot))

        // Focus changed to another element
        state.currentElement = AXUIElementCreateApplication(202)
        XCTAssertFalse(tracker.stillMatches(snapshot))

        // App changed
        state.currentElement = element
        state.currentPID = 202
        XCTAssertFalse(tracker.stillMatches(snapshot))
    }

    func testNonEditableApplicationElementFailsDefaultValidator() {
        let appElement = AXUIElementCreateApplication(101)
        XCTAssertFalse(SystemFocusTracker.isElementEditable(appElement))
    }
}
