import Cocoa

enum ScreenLocator {
    /// AppKit uses a bottom-left origin; AX uses the primary display's top-left.
    /// NSScreen.main is the active window's screen, which may be a secondary display.
    static func accessibilityPoint(for point: NSPoint) -> CGPoint {
        accessibilityPoint(for: point, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    static func accessibilityPoint(for point: NSPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func screen(for point: NSPoint) -> NSScreen? {
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return containingScreen
        }

        return NSScreen.screens.min { lhs, rhs in
            distance(from: point, to: lhs.frame) < distance(from: point, to: rhs.frame)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func visibleFrame(for point: NSPoint) -> NSRect {
        screen(for: point)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    static func frame(for size: NSSize, anchoredAt anchorPoint: NSPoint, gap: CGFloat = 10, inset: CGFloat = 8) -> NSRect {
        let visibleFrame = visibleFrame(for: anchorPoint)
        var origin = NSPoint(x: anchorPoint.x - size.width / 2, y: anchorPoint.y - size.height - gap)

        if origin.x + size.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - size.width - inset
        }
        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX + inset
        }
        if origin.y < visibleFrame.minY {
            origin.y = anchorPoint.y + gap
        }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = visibleFrame.maxY - size.height - inset
        }
        if origin.y < visibleFrame.minY {
            origin.y = visibleFrame.minY + inset
        }

        return NSRect(origin: origin, size: size)
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}
