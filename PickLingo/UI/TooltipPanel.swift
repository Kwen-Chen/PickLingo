import Cocoa
import SwiftUI
import Combine
import OSLog

final class TooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var onPluginSelected: ((Plugin) -> Void)?

    private var autoHideWorkItem: DispatchWorkItem?
    private var mouseExitDismissWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var trackingArea: NSTrackingArea?
    private var globalClickMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var selectionAnchor: NSPoint?
    private var selectionBounds: NSRect?
    private var settingsObserver: AnyCancellable?
    private let shadowInset: CGFloat = 12
    private let logger = Logger(subsystem: "com.picklingo.app", category: "SelectionMonitoring")

    private var dismissDistance: CGFloat {
        CGFloat(AppSettings.shared.tooltipDismissDistance)
    }

    private var hostingView: NSHostingView<TooltipBarView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .utilityWindow
        settingsObserver = AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.isVisible else { return }
                self.updateLayout()
            }
    }

    deinit {
        removeAllMonitors()
    }

    private func setupContent(at point: NSPoint) {
        let settings = AppSettings.shared
        let root = TooltipBarView(
            plugins: PluginManager.shared.enabledPlugins(),
            style: settings.tooltipStyle,
            spacing: settings.tooltipPluginSpacing,
            maximumWidth: max(80, ScreenLocator.visibleFrame(for: point).width - shadowInset * 2),
            onSelect: { [weak self] plugin in self?.onPluginSelected?(plugin) }
        )
        let view: NSHostingView<TooltipBarView>
        if let existing = hostingView {
            existing.rootView = root
            view = existing
        } else {
            view = NSHostingView(rootView: root)
            contentView?.addSubview(view)
            hostingView = view
        }
        // Style and spacing affect intrinsic size even when plugin IDs are unchanged.
        view.invalidateIntrinsicContentSize()
        let size = view.fittingSize
        view.frame = NSRect(origin: NSPoint(x: shadowInset, y: shadowInset), size: size)
        setContentSize(NSSize(width: size.width + shadowInset * 2, height: size.height + shadowInset * 2))
    }

    func show(at point: NSPoint, selectionBounds: NSRect? = nil) {
        dismiss()
        guard !PluginManager.shared.enabledPlugins().isEmpty else { return }
        selectionAnchor = point
        self.selectionBounds = selectionBounds
        updateLayout()
        self.alphaValue = 1.0
        self.orderFrontRegardless()
        logger.debug("Selection toolbar shown; visible: \(self.isVisible)")

        isMouseInside = false

        setupMouseTracking()
        setupGlobalClickMonitor()
        setupMouseMoveMonitor()
        startAutoHideTimer(interval: 6.0)
    }

    private func updateLayout() {
        guard let anchor = selectionAnchor else { return }
        applyCurrentTheme()
        setupContent(at: anchor)
        guard let hostingView else { return }
        let settings = AppSettings.shared
        let surface = ScreenLocator.toolbarFrame(
            for: hostingView.frame.size, selectionBounds: selectionBounds, anchor: anchor,
            horizontalOffset: settings.tooltipHorizontalOffset, verticalGap: settings.tooltipVerticalGap,
            position: settings.tooltipPosition, in: ScreenLocator.visibleFrame(for: anchor), inset: shadowInset
        )
        setFrame(surface.insetBy(dx: -shadowInset, dy: -shadowInset), display: true)
        setupMouseTracking()
    }

    func applyCurrentTheme() {
        self.appearance = AppSettings.shared.appTheme.nsAppearance
    }

    // MARK: - Mouse Tracking (enter/exit tooltip area)

    private func setupMouseTracking() {
        guard let contentView = self.contentView else { return }

        if let existing = trackingArea {
            contentView.removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        mouseExitDismissWorkItem?.cancel()
        autoHideWorkItem?.cancel()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        mouseExitDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isMouseInside else { return }
            self.fadeOut()
        }
        mouseExitDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)

        startAutoHideTimer(interval: 3.0)
    }

    // MARK: - Global Click Monitor

    private func setupGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                self.fadeOut()
            }
        }
    }

    // MARK: - Mouse Move Monitor (distance-based dismiss)

    private func setupMouseMoveMonitor() {
        removeMouseMoveMonitor()
        guard AppSettings.shared.tooltipAutoDismissByDistanceEnabled else { return }

        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self, !self.isMouseInside else { return }
            let mouseLocation = NSEvent.mouseLocation
            let source = self.selectionBounds ?? NSRect(origin: self.selectionAnchor ?? mouseLocation, size: .zero)
            // Keep a path from the selection to the toolbar when its gap is large.
            let travelArea = self.frame.union(source).insetBy(dx: -self.dismissDistance, dy: -self.dismissDistance)
            if !travelArea.contains(mouseLocation) {
                self.fadeOut()
            }
        }
    }

    // MARK: - Auto-hide Timer

    private func startAutoHideTimer(interval: TimeInterval) {
        autoHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    // MARK: - Dismiss

    func fadeOut() { dismiss() }

    func dismiss() {
        autoHideWorkItem?.cancel()
        mouseExitDismissWorkItem?.cancel()
        autoHideWorkItem = nil
        mouseExitDismissWorkItem = nil
        removeAllMonitors()
        // Synchronous dismissal cannot hide a newly shown tooltip via an old animation.
        orderOut(nil)
        selectionAnchor = nil
        selectionBounds = nil
        alphaValue = 1
    }

    func cancelAutoHide() {
        autoHideWorkItem?.cancel()
    }

    // MARK: - Monitor Cleanup

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    private func removeMouseMoveMonitor() {
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
    }

    private func removeAllMonitors() {
        removeGlobalClickMonitor()
        removeMouseMoveMonitor()
    }
}

// MARK: - Shared toolbar rendering (popover and settings preview)

struct TooltipBarView: View {
    let plugins: [Plugin]
    var style: TooltipStyle = .floating
    var spacing: Double = 2
    var maximumWidth: CGFloat = 600
    let onSelect: (Plugin) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var padding: CGFloat { style == .floating ? 1 : 5 }
    private var radius: CGFloat { style == .capsule ? 22 : 13 }
    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        TooltipFlowLayout(spacing: CGFloat(spacing), maximumWidth: maximumWidth - padding * 2) {
            ForEach(plugins) { plugin in
                TooltipPluginButton(plugin: plugin, style: style) { onSelect(plugin) }
            }
        }
        .fixedSize()
        .padding(padding)
        .background {
            if style != .floating {
                surface
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(dark ? 0.18 : 0.8), .white.opacity(0.02)],
                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.5
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.black.opacity(dark ? 0.2 : 0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(dark ? 0.22 : 0.1), radius: 7, y: 3)
                    .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            }
        }
        .textSelection(.disabled)
    }

    @ViewBuilder
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if style == .capsule {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(.white.opacity(dark ? 0.025 : 0.22)) }
        } else if style == .minimal {
            shape.fill(LinearGradient(colors: [Color(red: 0.19, green: 0.21, blue: 0.25),
                                                Color(red: 0.12, green: 0.14, blue: 0.18)],
                                      startPoint: .top, endPoint: .bottom))
        } else {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}

/// Wrap long toolbars rather than pushing plugins off the active display.
struct TooltipFlowLayout: Layout {
    let spacing: CGFloat
    let maximumWidth: CGFloat

    private func arrange(_ subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maximumWidth {
                x = 0
                y += rowHeight + max(4, spacing)
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            width = max(width, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (positions, CGSize(width: width, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(subviews).positions
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y),
                          anchor: .topLeading, proposal: .unspecified)
        }
    }
}

struct TooltipPluginButton: View {
    let plugin: Plugin
    var style: TooltipStyle = .floating
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Bool { style == .minimal }
    private var foreground: Color {
        ink ? .white.opacity(isHovered ? 1 : 0.9) : (isHovered ? .accentColor : .primary.opacity(0.85))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: plugin.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                if style == .labeled {
                    Text(plugin.uiDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 140)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, style == .labeled ? 9 : 6)
            .frame(height: 32)
            .background {
                if style == .floating {
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay { Circle().fill(Color.accentColor.opacity(isHovered ? 0.12 : 0)) }
                        .overlay { Circle().strokeBorder(Color.primary.opacity(isHovered ? 0.1 : 0.06), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.09), radius: 3, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: style == .capsule ? 17 : 8, style: .continuous)
                        .fill(ink ? Color.white.opacity(isHovered ? 0.16 : 0) : Color.accentColor.opacity(isHovered ? 0.1 : 0))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(plugin.uiDisplayName)
        .accessibilityLabel(Text(plugin.uiDisplayName))
    }
}
