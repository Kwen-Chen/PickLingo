import AppKit
import XCTest
@testable import PickLingoCore

final class EventRoutingTests: XCTestCase {
    func testNonactivatingToolbarClickCannotClearTheSelectionBeforeButtonExecution() {
        var routing = SelectionEventRouting()
        // Quartz can still name the source editor as the target and front app.
        XCTAssertFalse(routing.shouldForward(.leftMouseDown, targetIsOwnApp: false,
                                             frontmostIsOwnApp: false, hitsOwnWindow: true))
        XCTAssertFalse(routing.shouldForward(.leftMouseUp, targetIsOwnApp: false,
                                             frontmostIsOwnApp: false, hitsOwnWindow: true))
    }

    func testLocalMouseUpStaysLocalIfThePanelClosesOrPointerLeavesDuringTheClick() {
        var routing = SelectionEventRouting()
        XCTAssertFalse(routing.shouldForward(.leftMouseDown, targetIsOwnApp: false,
                                             frontmostIsOwnApp: false, hitsOwnWindow: true))
        XCTAssertFalse(routing.shouldForward(.leftMouseUp, targetIsOwnApp: false,
                                             frontmostIsOwnApp: false, hitsOwnWindow: false))
        XCTAssertTrue(routing.shouldForward(.leftMouseDown, targetIsOwnApp: false,
                                            frontmostIsOwnApp: false, hitsOwnWindow: false))
        XCTAssertTrue(routing.shouldForward(.leftMouseUp, targetIsOwnApp: false,
                                            frontmostIsOwnApp: false, hitsOwnWindow: false))
    }

    func testHoveringToolbarDoesNotHideCopyPasteKeysFromSelectionCancellation() {
        var routing = SelectionEventRouting()
        for type in [NSEvent.EventType.keyDown, .flagsChanged] {
            XCTAssertTrue(routing.shouldForward(type, targetIsOwnApp: false,
                                                frontmostIsOwnApp: false, hitsOwnWindow: true))
            XCTAssertFalse(routing.shouldForward(type, targetIsOwnApp: true,
                                                 frontmostIsOwnApp: false, hitsOwnWindow: false))
        }
    }

    func testResultPanelScrollingAndSecondaryClicksStayLocal() {
        var routing = SelectionEventRouting()
        for type in [NSEvent.EventType.scrollWheel, .rightMouseDown, .otherMouseDown] {
            XCTAssertFalse(routing.shouldForward(type, targetIsOwnApp: false,
                                                 frontmostIsOwnApp: false, hitsOwnWindow: true))
            XCTAssertTrue(routing.shouldForward(type, targetIsOwnApp: false,
                                                frontmostIsOwnApp: false, hitsOwnWindow: false))
        }
    }

    func testWindowHitTestingCoordinatesRoundTripAcrossDisplays() {
        for point in [CGPoint(x: 40, y: 600), CGPoint(x: -800, y: 1200), CGPoint(x: 1800, y: -200)] {
            let quartz = ScreenLocator.accessibilityPoint(for: point, primaryScreenHeight: 900)
            XCTAssertEqual(ScreenLocator.appKitPoint(for: quartz, primaryScreenHeight: 900), point)
        }
    }
}
