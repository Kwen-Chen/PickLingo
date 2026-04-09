import Cocoa
import SwiftUI

// MARK: - Panel Controller
private final class KeyableResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ResultPanelController: NSObject, NSWindowDelegate {
    private static let minPanelWidth: CGFloat = 340
    private static let minPanelHeight: CGFloat = 120
    private static let defaultPanelWidth: CGFloat = 420
    private static let defaultPanelHeight: CGFloat = 220
    private static let maxPanelWidthCap: CGFloat = 900

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ResultContentView>?
    private var viewModel = ResultViewModel()
    private var panelOrigin: NSPoint = .zero

    var isPinned: Bool {
        viewModel.isPinned
    }

    /// Whether the panel is currently on screen and visible.
    var isVisible: Bool {
        guard let panel else { return false }
        return panel.isVisible && panel.alphaValue > 0
    }

    func show(
        for text: String,
        plugin: Plugin,
        userInput: String? = nil,
        thinkModeOverride: Bool? = nil,
        at origin: NSPoint
    ) {
        // Cancel any existing stream but don't animate out
        viewModel.cancelStream()

        panelOrigin = origin

        // Reset the view model for new execution
        viewModel = ResultViewModel()
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }

        let resultView = ResultContentView(viewModel: viewModel)

        if let panel, let hostingView {
            // Reuse existing panel — just swap the root view
            hostingView.rootView = resultView
            panel.appearance = AppSettings.shared.appTheme.nsAppearance
            updatePanelResizeLimits(panel, anchorPoint: origin)
            let fittingSize = hostingView.fittingSize
            let panelSize = preferredPanelSize(currentSize: panel.frame.size, fittingSize: fittingSize)
            let panelFrame = calculatePanelFrame(anchorPoint: origin, panelSize: panelSize)
            panel.setFrame(panelFrame, display: false)
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // First time: create panel and hosting view
            let hv = NSHostingView(rootView: resultView)
            let fittingSize = hv.fittingSize

            let p = KeyableResultPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: max(fittingSize.width, Self.minPanelWidth),
                    height: max(fittingSize.height, Self.minPanelHeight)
                ),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.isMovableByWindowBackground = true
            p.hidesOnDeactivate = false
            p.animationBehavior = .utilityWindow
            p.contentView = hv
            p.appearance = AppSettings.shared.appTheme.nsAppearance
            p.delegate = self

            updatePanelResizeLimits(p, anchorPoint: origin)

            let panelSize = preferredPanelSize(currentSize: nil, fittingSize: fittingSize)
            let panelFrame = calculatePanelFrame(anchorPoint: origin, panelSize: panelSize)
            p.setFrameOrigin(panelFrame.origin)
            p.setContentSize(panelSize)
            p.alphaValue = 0
            p.orderFrontRegardless()
            p.makeKey()
            NSApp.activate(ignoringOtherApps: true)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                p.animator().alphaValue = 1.0
            }

            panel = p
            hostingView = hv
        }

        viewModel.execute(text: text, plugin: plugin, userInput: userInput, thinkModeOverride: thinkModeOverride)
    }

    func applyCurrentTheme() {
        panel?.appearance = AppSettings.shared.appTheme.nsAppearance
    }

    func dismiss() {
        viewModel.cancelStream()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    func dismissIfNotPinned() {
        if !viewModel.isPinned {
            dismiss()
        }
    }

    private func preferredPanelSize(currentSize: NSSize?, fittingSize: NSSize) -> NSSize {
        let width = currentSize?.width ?? max(fittingSize.width, Self.defaultPanelWidth)
        let height = currentSize?.height ?? max(fittingSize.height, Self.defaultPanelHeight)
        return NSSize(
            width: max(width, Self.minPanelWidth),
            height: max(height, Self.minPanelHeight)
        )
    }

    private func updatePanelResizeLimits(_ panel: NSPanel, anchorPoint: NSPoint) {
        let visibleFrame = screen(for: anchorPoint)?.visibleFrame
            ?? (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.minSize = NSSize(width: Self.minPanelWidth, height: Self.minPanelHeight)
        panel.maxSize = NSSize(
            width: min(visibleFrame.width * 0.85, Self.maxPanelWidthCap),
            height: visibleFrame.height * 0.85
        )
    }

    private func screen(for point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func calculatePanelFrame(anchorPoint: NSPoint, panelSize: NSSize) -> NSRect {
        var origin = NSPoint(x: anchorPoint.x - panelSize.width / 2, y: anchorPoint.y - panelSize.height - 10)

        if let screen = screen(for: anchorPoint) {
            let screenFrame = screen.visibleFrame

            if origin.x + panelSize.width > screenFrame.maxX {
                origin.x = screenFrame.maxX - panelSize.width - 8
            }
            if origin.x < screenFrame.minX {
                origin.x = screenFrame.minX + 8
            }
            if origin.y < screenFrame.minY {
                origin.y = anchorPoint.y + 10
            }
            if origin.y + panelSize.height > screenFrame.maxY {
                origin.y = screenFrame.maxY - panelSize.height - 8
            }
        }

        return NSRect(origin: origin, size: panelSize)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        panelOrigin = NSPoint(x: panel.frame.midX, y: panel.frame.maxY + 10)
    }
}

struct BodyContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - ViewModel

@MainActor
final class ResultViewModel: ObservableObject {
    let minPanelWidth: CGFloat = 340

    @Published var sourceText: String = ""
    @Published var resultText: String = ""
    @Published var thinkingText: String = ""
    @Published var isLoading: Bool = false
    @Published var isThinking: Bool = false
    @Published var errorMessage: String?
    @Published var isPinned: Bool = false

    // Plugin info
    @Published var currentPlugin: Plugin?
    @Published var userInputText: String = ""
    @Published var thinkModeOverride: Bool?

    // Translation-specific (only for Translate plugin)
    @Published var sourceLang: String = ""
    @Published var targetLang: String = ""
    @Published var detectedSourceLanguage: Language = .english
    @Published var currentTargetLanguage: Language = .chinese

    var onDismiss: (() -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    private var currentStreamTask: Task<Void, Never>?
    private var latestAnswerText: String = ""
    private var pendingFollowUpDisplayPrefix: String?

    func execute(text: String, plugin: Plugin, userInput: String? = nil, thinkModeOverride: Bool? = nil) {
        sourceText = text
        currentPlugin = plugin
        userInputText = userInput ?? ""
        self.thinkModeOverride = thinkModeOverride
        latestAnswerText = ""
        pendingFollowUpDisplayPrefix = nil

        if plugin.showLanguageControls {
            let settings = AppSettings.shared
            let detected: Language
            if settings.autoDetectLanguage {
                detected = LanguageDetector.detect(text) ?? .english
            } else {
                detected = .english
            }
            let target = LanguageDetector.targetLanguage(for: detected)
            detectedSourceLanguage = detected
            currentTargetLanguage = target
            sourceLang = detected.uiName
            targetLang = target.uiName
        }

        performExecution()
    }

    func changeTargetLanguage(_ language: Language) {
        currentTargetLanguage = language
        targetLang = language.uiName
        performExecution()
    }

    func togglePin() {
        isPinned.toggle()
        onPinChanged?(isPinned)
    }

    private func performExecution() {
        currentStreamTask?.cancel()
        currentStreamTask = nil

        isLoading = true
        errorMessage = nil
        let displayPrefix = pendingFollowUpDisplayPrefix
        pendingFollowUpDisplayPrefix = nil
        resultText = displayPrefix ?? ""
        thinkingText = ""
        isThinking = false

        guard let plugin = currentPlugin else { return }

        let settings = AppSettings.shared
        let text = sourceText
        let userInput = userInputText.isEmpty ? nil : userInputText

        if settings.streamingEnabled {
            let source: Language? = plugin.showLanguageControls ? detectedSourceLanguage : nil
            let target: Language? = plugin.showLanguageControls ? currentTargetLanguage : nil

            currentStreamTask = Task {
                do {
                    var latestChunkedAnswer = ""
                    let stream = PluginExecutor.shared.executeStream(
                        text: text,
                        plugin: plugin,
                        userInput: userInput,
                        source: source,
                        target: target,
                        thinkModeOverride: thinkModeOverride
                    )
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        switch chunk {
                        case .thinking(let delta):
                            if !isThinking { isThinking = true }
                            thinkingText += delta
                        case .text(let delta):
                            if isThinking { isThinking = false }
                            if isLoading { isLoading = false }
                            latestChunkedAnswer += delta
                            resultText += delta
                        case .done:
                            break
                        }
                    }
                    latestAnswerText = latestChunkedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                    isLoading = false
                } catch {
                    if !Task.isCancelled {
                        errorMessage = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        } else {
            currentStreamTask = Task {
                do {
                    let source: Language? = plugin.showLanguageControls ? detectedSourceLanguage : nil
                    let target: Language? = plugin.showLanguageControls ? currentTargetLanguage : nil
                    let result = try await PluginExecutor.shared.execute(
                        text: text,
                        plugin: plugin,
                        userInput: userInput,
                        source: source,
                        target: target,
                        thinkModeOverride: thinkModeOverride
                    )
                    if !Task.isCancelled {
                        latestAnswerText = result.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let prefix = displayPrefix {
                            resultText = prefix + result
                        } else {
                            resultText = result
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        errorMessage = error.localizedDescription
                    }
                }
                isLoading = false
            }
        }
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
    }

    func insertResult() {
        let prev = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceText + "\n" + resultText, forType: .string)
        simulatePaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let prev {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prev, forType: .string)
            }
        }
    }

    func replaceResult() {
        let prev = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        simulatePaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let prev {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prev, forType: .string)
            }
        }
    }

    func regenerateResult() {
        performExecution()
    }

    func submitFollowUp(_ userInput: String, thinkModeOverride: Bool? = nil) {
        guard let plugin = currentPlugin else { return }
        let context = latestAnswerText.isEmpty
            ? resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            : latestAnswerText
        let question = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty, !question.isEmpty else { return }

        let previousDisplay = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingFollowUpDisplayPrefix = previousDisplay + "\n\n---\n\n> " + question + "\n\n"

        sourceText = context
        userInputText = question
        self.thinkModeOverride = thinkModeOverride

        if plugin.showLanguageControls {
            let settings = AppSettings.shared
            let detected: Language
            if settings.autoDetectLanguage {
                detected = LanguageDetector.detect(context) ?? .english
            } else {
                detected = .english
            }
            detectedSourceLanguage = detected
            sourceLang = detected.uiName
            // Keep user's currently selected target language for continuity.
            targetLang = currentTargetLanguage.uiName
        }

        performExecution()
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func cancelStream() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
    }

    func dismiss() {
        cancelStream()
        onDismiss?()
    }
}

// MARK: - Result View

struct ResultContentView: View {
    private static let maxAutoScrollableContentHeight: CGFloat = 460

    @ObservedObject var viewModel: ResultViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var bodyContentHeight: CGFloat = 0
    @State private var followUpInputText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            if bodyContentHeight > Self.maxAutoScrollableContentHeight {
                ScrollView(.vertical) {
                    contentBody
                }
                .frame(height: Self.maxAutoScrollableContentHeight)
            } else {
                contentBody
            }
        }
        .frame(minWidth: viewModel.minPanelWidth, maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(BodyContentHeightPreferenceKey.self) { height in
            bodyContentHeight = height
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 3, x: 0, y: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Source text
            Text(viewModel.sourceText)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // User input (for Ask-type plugins)
            if !viewModel.userInputText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(viewModel.userInputText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            // Thinking section
            if !viewModel.thinkingText.isEmpty {
                thinkingSection
            }

            // Result content
            resultContent
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            if shouldShowFollowUpInput {
                followUpInput
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            // Action bar (only if the plugin has at least one action enabled)
            if !viewModel.isLoading && viewModel.errorMessage == nil && !viewModel.resultText.isEmpty,
               let actions = viewModel.currentPlugin?.enabledActions, !actions.isEmpty {
                actionBar
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: BodyContentHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        if let plugin = viewModel.currentPlugin, plugin.showLanguageControls {
            languageHeaderView(plugin: plugin)
        } else {
            genericHeaderView
        }
    }

    /// Header with language selectors (for any plugin with showLanguageControls = true)
    private func languageHeaderView(plugin: Plugin) -> some View {
        HStack(spacing: 6) {
            Image(systemName: plugin.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(viewModel.sourceLang)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.quaternary)

            Menu {
                // Show ALL languages — detection may be wrong, so don't exclude source
                ForEach(Language.allCases) { lang in
                    Button(lang.uiName) {
                        viewModel.changeTargetLanguage(lang)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(viewModel.targetLang)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            pinAndCloseButtons
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// Header for all other plugins — shows plugin icon + name
    private var genericHeaderView: some View {
        HStack(spacing: 6) {
            if let plugin = viewModel.currentPlugin {
                Image(systemName: plugin.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(plugin.uiDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            pinAndCloseButtons
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var pinAndCloseButtons: some View {
        HStack(spacing: 6) {
            Button(action: viewModel.togglePin) {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.isPinned ? .accentColor : .secondary)
                    .rotationEffect(.degrees(viewModel.isPinned ? 0 : 45))
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? UIString("Unpin panel") : UIString("Pin panel"))

            Button(action: viewModel.dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Thinking Section

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            DisclosureGroup {
                ScrollView(.vertical) {
                    Text(viewModel.thinkingText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(.top, 4)
            } label: {
                HStack(spacing: 4) {
                    if viewModel.isThinking {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(UIString("Thinking…"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Result Content

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isLoading && viewModel.resultText.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else if let error = viewModel.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else if !viewModel.resultText.isEmpty {
            MarkdownContentView(text: viewModel.resultText)
        }
    }

    private var loadingLabel: String {
        guard let plugin = viewModel.currentPlugin else { return UIString("Processing…") }
        if plugin.isTranslatePlugin {
            return UIString("Translating…")
        }
        return UIString("Processing…")
    }

    private var shouldShowFollowUpInput: Bool {
        guard let plugin = viewModel.currentPlugin else { return false }
        return plugin.enabledActions.contains(.followUp) &&
            !viewModel.isLoading &&
            viewModel.errorMessage == nil &&
            !viewModel.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var followUpInput: some View {
        HStack(spacing: 8) {
            TextField(UIString("Type your follow-up..."), text: $followUpInputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    submitFollowUpIfValid()
                }

            Button(action: submitFollowUpIfValid) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }

    private func submitFollowUpIfValid() {
        let text = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpInputText = ""
        viewModel.submitFollowUp(text)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        let actions = viewModel.currentPlugin?.enabledActions ?? .all
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 2) {
                if actions.contains(.copy) {
                    ActionChip(title: UIString("Copy"), icon: "doc.on.doc", shortcut: "c") {
                        viewModel.copyResult()
                    }
                }
                if actions.contains(.insert) {
                    ActionChip(title: UIString("Insert"), icon: "text.insert", shortcut: "i") {
                        viewModel.insertResult()
                    }
                }
                if actions.contains(.replace) {
                    ActionChip(title: UIString("Replace"), icon: "arrow.2.squarepath", shortcut: "r") {
                        viewModel.replaceResult()
                    }
                }
                if actions.contains(.regenerate) {
                    ActionChip(title: UIString("Regenerate"), icon: "arrow.clockwise", shortcut: "g") {
                        viewModel.regenerateResult()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Action Chip

struct ActionChip: View {
    let title: String
    let icon: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .keyboardShortcut(KeyEquivalent(Character(shortcut)), modifiers: .command)
    }
}
