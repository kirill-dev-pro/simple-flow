import CoreGraphics
import Foundation

public enum InsertionResult: String, Codable, CaseIterable, Sendable {
    case inserted
    case pasteFailed
}

public protocol EventPosting: Sendable {
    func postPasteCommand() -> Bool
}

public final class SystemEventPoster: EventPosting, @unchecked Sendable {
    public init() {}

    public func postPasteCommand() -> Bool {
        let cmdKeyCode: CGKeyCode = 55
        let vKeyCode: CGKeyCode = 9

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            return false
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []

        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)

        return true
    }
}

public protocol PasteRestorationScheduling: Sendable {
    func schedule(after delay: TimeInterval, action: @escaping @Sendable () -> Void)
}

public final class AsyncTimerRestorationScheduler: PasteRestorationScheduling, @unchecked Sendable {
    public init() {}

    public func schedule(after delay: TimeInterval, action: @escaping @Sendable () -> Void) {
        Task {
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }
}

public protocol TextInserting: Sendable {
    func insert(_ text: String) async -> InsertionResult
}

public final class TextInserter: TextInserting, @unchecked Sendable {
    private let pasteboard: PasteboardManaging
    private let eventPoster: EventPosting
    private let scheduler: PasteRestorationScheduling
    private let restorationDelay: TimeInterval

    public static let defaultRestorationDelay: TimeInterval = 0.5

    public init(
        pasteboard: PasteboardManaging = PasteboardClient(),
        eventPoster: EventPosting = SystemEventPoster(),
        scheduler: PasteRestorationScheduling = AsyncTimerRestorationScheduler(),
        restorationDelay: TimeInterval = defaultRestorationDelay
    ) {
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.scheduler = scheduler
        self.restorationDelay = restorationDelay
    }

    public func insert(_ text: String) async -> InsertionResult {
        AppLogger.insertion.info("Attempting text insertion (length: \(text.count) characters)")
        let previousSnapshot = pasteboard.snapshot()
        let insertedChangeCount = pasteboard.writeString(text)

        let posted = eventPoster.postPasteCommand()
        guard posted else {
            AppLogger.insertion.error("Failed to post synthetic paste command, restoring pasteboard")
            pasteboard.restore(previousSnapshot, matchingChangeCount: insertedChangeCount)
            return .pasteFailed
        }

        scheduler.schedule(after: restorationDelay) { [pasteboard] in
            pasteboard.restore(previousSnapshot, matchingChangeCount: insertedChangeCount)
        }

        AppLogger.insertion.info("Text insertion completed with result: inserted")
        return .inserted
    }
}
