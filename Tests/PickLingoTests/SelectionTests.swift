import XCTest
import ApplicationServices
import AppKit
@testable import PickLingoCore

final class SelectionTests: XCTestCase {
    func testToolbarGapsUseSelectionEdgesAndHorizontalOffsets() {
        let selection = CGRect(x: 400, y: 300, width: 200, height: 40)
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: 220, height: 42)
        let below = ScreenLocator.toolbarFrame(for: size, selectionBounds: selection, anchor: .zero,
                                               horizontalOffset: 60, verticalGap: 24, position: .below, in: screen)
        XCTAssertEqual(below.midX, selection.midX + 60)
        XCTAssertEqual(selection.minY - below.maxY, 24)
        let above = ScreenLocator.toolbarFrame(for: size, selectionBounds: selection, anchor: .zero,
                                               horizontalOffset: -60, verticalGap: 0, position: .above, in: screen)
        XCTAssertEqual(above.midX, selection.midX - 60)
        XCTAssertEqual(above.minY, selection.maxY)
    }

    func testToolbarFlipsAndClampsWithinItsOriginalDisplay() {
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let selection = CGRect(x: -50, y: -875, width: 40, height: 20)
        let frame = ScreenLocator.toolbarFrame(for: CGSize(width: 320, height: 42), selectionBounds: selection,
                                               anchor: CGPoint(x: -20, y: -860), horizontalOffset: 120,
                                               verticalGap: 40, position: .below, in: screen)
        XCTAssertEqual(frame.minY, selection.maxY + 40, "Not enough room below: preserve the gap above")
        XCTAssertEqual(frame.maxX, screen.maxX - 12)
        XCTAssertTrue(screen.contains(frame))
    }

    func testMissingSelectionBoundsStillPositionsToolbarAtGesture() {
        let anchor = CGPoint(x: 500, y: 400)
        let frame = ScreenLocator.toolbarFrame(for: CGSize(width: 200, height: 42), selectionBounds: nil,
                                               anchor: anchor, horizontalOffset: -30, verticalGap: 12,
                                               position: .below, in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        XCTAssertEqual(frame.midX, 470)
        XCTAssertEqual(frame.maxY, 388)
        XCTAssertEqual(ScreenLocator.appKitRect(for: CGRect(x: -600, y: -100, width: 120, height: 40),
                                                primaryScreenHeight: 900),
                       CGRect(x: -600, y: 960, width: 120, height: 40))
    }

    func testSettingsControlsAndTheirTextLabelsCannotTriggerSelection() {
        for role in [kAXRadioButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole, kAXSliderRole, kAXButtonRole] {
            XCTAssertFalse(SelectionTargetPolicy.allowsSettingsSelection(rolePath: [role, kAXGroupRole]))
            XCTAssertFalse(SelectionTargetPolicy.allowsSettingsSelection(rolePath: [kAXStaticTextRole, role, kAXGroupRole]),
                           "Text inside a control must not reuse an earlier selection")
        }
        XCTAssertFalse(SelectionTargetPolicy.allowsSettingsSelection(rolePath: [kAXGroupRole]),
                       "Blank settings areas must not fall back to a focused field's selection")
        XCTAssertTrue(SelectionTargetPolicy.allowsSettingsSelection(rolePath: [kAXStaticTextRole, kAXGroupRole]))
        XCTAssertTrue(SelectionTargetPolicy.allowsSettingsSelection(rolePath: [kAXTextAreaRole, kAXScrollAreaRole, kAXGroupRole]))
        XCTAssertTrue(SelectionTargetPolicy.allowsSettingsSelection(rolePath: [kAXTextFieldRole, kAXGroupRole]))
    }

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
    private var continuation: CheckedContinuation<SelectionSnapshot?, Never>?
    private(set) var started = false

    func read() async -> SelectionSnapshot? {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ text: String) {
        continuation?.resume(returning: SelectionSnapshot(text: text))
        continuation = nil
    }
}

private actor InitializingSelectionReader {
    private(set) var calls = 0

    func read() -> SelectionSnapshot? {
        calls += 1
        return calls == 1 ? nil : SelectionSnapshot(text: "selected after initialization")
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
            XCTAssertEqual(text.text, "selected after initialization")
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
                          read: { _, _ in await reader.read() }) { detected.append($0.text) }
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
                              read: { _, _ in SelectionSnapshot(text: "  selected code\n") }) { detected.append($0.text) }
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
                          read: { _, _ in await reader.read() }) { detected.append($0.text) }
        while !(await reader.started) { await Task.yield() }
        pid = 99
        await reader.finish("old app text")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(detected.isEmpty)
    }
}
