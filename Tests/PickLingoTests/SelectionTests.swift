import XCTest
import AppKit
@testable import PickLingoCore

final class SelectionTests: XCTestCase {
    func testReturningToAppDoesNotReviveAnOldSelection() {
        var session = SelectionSession()
        let old = session.begin(pid: 42)
        XCTAssertFalse(session.isCurrent(old, frontmostPID: 43))
        session.invalidate()
        XCTAssertFalse(session.isCurrent(old, frontmostPID: 42))
    }

    func testNewGestureSupersedesSlowAXReply() {
        var session = SelectionSession()
        let first = session.begin(pid: 42)
        let second = session.begin(pid: 42)
        XCTAssertFalse(session.isCurrent(first, frontmostPID: 42))
        XCTAssertTrue(session.isCurrent(second, frontmostPID: 42))
        XCTAssertFalse(session.isCurrent(second, frontmostPID: nil))
    }

    func testSelectionGesturesIncludeShiftClickButNotCaretPlacement() {
        XCTAssertFalse(SelectionSession.isSelectionGesture(from: .zero, to: NSPoint(x: 2, y: 0), clickCount: 1, shiftPressed: false))
        XCTAssertTrue(SelectionSession.isSelectionGesture(from: .zero, to: NSPoint(x: 8, y: 0), clickCount: 1, shiftPressed: false))
        XCTAssertTrue(SelectionSession.isSelectionGesture(from: .zero, to: .zero, clickCount: 2, shiftPressed: false))
        XCTAssertTrue(SelectionSession.isSelectionGesture(from: .zero, to: .zero, clickCount: 1, shiftPressed: true))
    }

    func testAXCoordinatesAcrossVerticallyAndHorizontallyArrangedDisplays() {
        XCTAssertEqual(ScreenLocator.accessibilityPoint(for: CGPoint(x: 100, y: 800), primaryScreenHeight: 900), CGPoint(x: 100, y: 100))
        XCTAssertEqual(ScreenLocator.accessibilityPoint(for: CGPoint(x: -1200, y: 1100), primaryScreenHeight: 900), CGPoint(x: -1200, y: -200))
        XCTAssertEqual(ScreenLocator.accessibilityPoint(for: CGPoint(x: 1500, y: -300), primaryScreenHeight: 900), CGPoint(x: 1500, y: 1200))
    }

    func testEditingShortcutsCannotOpenQuickAsk() {
        for key in ["c", "v", "x", "a", "z"] {
            XCTAssertNil(QuickAskShortcutParser.parse("cmd+\(key)"))
            XCTAssertNil(QuickAskShortcutParser.parse("command+\(key)"))
        }
        XCTAssertEqual(QuickAskShortcutParser.parse("cmd+cmd"), .doubleCommandTap)
        XCTAssertEqual(QuickAskShortcutParser.parse("⌘+shift+k"), .keyCombo(key: "k", modifiers: [.command, .shift]))
    }

    func testInvalidShortcutDoesNotSilentlyBecomeDoubleCommand() {
        for value in ["garbage", "cmd++k", "cmd+", "+cmd+k", "cmd+shift", "k"] {
            XCTAssertNil(QuickAskShortcutParser.parse(value))
            XCTAssertNotEqual(QuickAskShortcutParser.normalize(value), "cmd+cmd")
        }
    }
}

private actor DelayedSelectionReader {
    private var continuation: CheckedContinuation<String?, Never>?
    private(set) var started = false

    func read() async -> String? {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ text: String) {
        continuation?.resume(returning: text)
        continuation = nil
    }
}

private actor InitializingSelectionReader {
    private(set) var calls = 0

    func read() -> String? {
        calls += 1
        return calls == 1 ? nil : "selected after initialization"
    }
}

extension SelectionTests {
    @MainActor
    func testFirstGestureCanWaitForAccessibilityTreeInitialization() async throws {
        let delivery = SelectionDelivery()
        let reader = InitializingSelectionReader()
        let delivered = expectation(description: "first gesture delivered")
        delivery.schedule(pid: 42, at: .zero, delay: 0, frontmostPID: { 42 },
                          read: { _, _ in await reader.read() }) { text in
            XCTAssertEqual(text, "selected after initialization")
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 1)
        let calls = await reader.calls
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testCopyCancelsPendingAccessibilityInitializationRetry() async throws {
        let delivery = SelectionDelivery()
        let reader = InitializingSelectionReader()
        delivery.schedule(pid: 42, at: .zero, delay: 0, frontmostPID: { 42 },
                          read: { _, _ in await reader.read() }) { _ in
            XCTFail("Canceled selection must not appear")
        }
        while await reader.calls == 0 { await Task.yield() }
        delivery.cancel()
        try await Task.sleep(for: .milliseconds(200))
        let calls = await reader.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testCopyDuringSlowSelectionReadCannotDeliverStaleTooltip() async throws {
        let delivery = SelectionDelivery()
        let reader = DelayedSelectionReader()
        var detected: [String] = []
        delivery.schedule(pid: 42, at: .zero, delay: 0, frontmostPID: { 42 },
                          read: { _, _ in await reader.read() }) { detected.append($0) }
        while !(await reader.started) { await Task.yield() }
        delivery.cancel() // The key-down path for Cmd+C / Cmd+V and selection clearing.
        await reader.finish("late selection")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(detected.isEmpty)
    }

    @MainActor
    func testSelectionPreservesWhitespaceAndAllowsReselectingSameText() async throws {
        let delivery = SelectionDelivery()
        var detected: [String] = []
        for _ in 0..<2 {
            delivery.schedule(pid: 42, at: .zero, delay: 0, frontmostPID: { 42 },
                              read: { _, _ in "  selected code\n" }) { detected.append($0) }
            try await Task.sleep(for: .milliseconds(20))
            delivery.cancel()
        }
        XCTAssertEqual(detected, ["  selected code\n", "  selected code\n"])
    }

    @MainActor
    func testSwitchingAppsWhileAXIsReadingDiscardsItsReply() async throws {
        let delivery = SelectionDelivery()
        let reader = DelayedSelectionReader()
        var pid: pid_t? = 42
        var detected: [String] = []
        delivery.schedule(pid: 42, at: .zero, delay: 0, frontmostPID: { pid },
                          read: { _, _ in await reader.read() }) { detected.append($0) }
        while !(await reader.started) { await Task.yield() }
        pid = 99
        await reader.finish("old app text")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(detected.isEmpty)
    }
}
