import Cocoa
import SwiftUI

final class TooltipPanel: NSPanel {
    var onPluginSelected: ((Plugin) -> Void)?

    private var autoHideWorkItem: DispatchWorkItem?
    private var mouseExitDismissWorkItem: DispatchWorkItem?
    private var isMouseInside = false
    private var trackingArea: NSTrackingArea?
    private var globalClickMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var tooltipCenter: NSPoint = .zero

    private var dismissDistance: CGFloat {
        CGFloat(AppSettings.shared.tooltipDismissDistance)
    }

    // Cache: only rebuild content when plugin list changes
    private var cachedPluginIDs: [UUID] = []
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
    }

    deinit {
        removeAllMonitors()
    }

    private func setupContent() {
        let plugins = PluginManager.shared.enabledPlugins()
        let currentIDs = plugins.map(\.id)

        // Only rebuild if plugin list changed
        if currentIDs == cachedPluginIDs, let existing = hostingView {
            // Just update the callback (may have changed)
            existing.rootView = TooltipBarView(plugins: plugins, onSelect: { [weak self] plugin in
                self?.onPluginSelected?(plugin)
            })
            let fittingSize = existing.fittingSize
            let padded = NSSize(width: fittingSize.width + 16, height: fittingSize.height + 12)
            existing.frame = NSRect(origin: NSPoint(x: 8, y: 6), size: fittingSize)
            self.setContentSize(padded)
            return
        }

        cachedPluginIDs = currentIDs

        let newHostingView = NSHostingView(rootView: TooltipBarView(plugins: plugins, onSelect: { [weak self] plugin in
            self?.onPluginSelected?(plugin)
        }))
        let fittingSize = newHostingView.fittingSize
        let padded = NSSize(width: fittingSize.width + 16, height: fittingSize.height + 12)
        newHostingView.frame = NSRect(origin: NSPoint(x: 8, y: 6), size: fittingSize)
        self.setContentSize(padded)
        self.contentView?.subviews.forEach { $0.removeFromSuperview() }
        self.contentView?.addSubview(newHostingView)
        hostingView = newHostingView
    }

    func show(at point: NSPoint) {
        setupContent()

        let size = self.frame.size
        let origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 4)
        self.setFrameOrigin(origin)
        self.alphaValue = 1.0
        self.orderFrontRegardless()

        tooltipCenter = NSPoint(x: self.frame.midX, y: self.frame.midY)
        isMouseInside = false

        setupMouseTracking()
        setupGlobalClickMonitor()
        setupMouseMoveMonitor()
        startAutoHideTimer(interval: 6.0)
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
            let dx = mouseLocation.x - self.tooltipCenter.x
            let dy = mouseLocation.y - self.tooltipCenter.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance > self.dismissDistance {
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

    func fadeOut() {
        autoHideWorkItem?.cancel()
        mouseExitDismissWorkItem?.cancel()
        removeAllMonitors()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1.0
        })
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

// MARK: - Tooltip Bar View (horizontal row of plugin icons)

struct TooltipBarView: View {
    let plugins: [Plugin]
    let onSelect: (Plugin) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(plugins) { plugin in
                TooltipPluginButton(plugin: plugin) {
                    onSelect(plugin)
                }
            }
        }
    }
}

struct TooltipPluginButton: View {
    let plugin: Plugin
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: plugin.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHovered ? .white : .primary)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(isHovered ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(plugin.name)
        .accessibilityLabel(Text(plugin.name))
    }
}
