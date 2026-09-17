import Cocoa
import Carbon
import SwiftUI

// MARK: - Panel Controller
private final class KeyableResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Copy the whole result explicitly with Shift+Cmd+C.
    var onCopyAllRequested: (() -> Void)?
    var onFocusFollowUpRequested: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            if !isEditingTextField {
                onFocusFollowUpRequested?()
                return
            }
        }

        super.keyDown(with: event)
    }

    private var isEditingTextField: Bool {
        guard let textView = firstResponder as? NSTextView else {
            return false
        }
        return textView.isFieldEditor
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Cmd+C belongs to the native responder chain, including SwiftUI text selections.
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c",
           let onCopyAllRequested {
            onCopyAllRequested()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

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
        sourceAppPID: pid_t = 0,
        at origin: NSPoint
    ) {
        // Cancel any existing stream but don't animate out
        viewModel.cancelPendingWork()

        panelOrigin = origin

        // Reset the view model for new execution
        viewModel = ResultViewModel()
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }

        let resultView = ResultContentView(
            viewModel: viewModel,
            onFocusFollowUpRequested: { [weak self] in
                self?.scheduleFollowUpFocus()
            }
        )

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
            p.onCopyAllRequested = { [weak self] in
                self?.viewModel.copyResult()
            }
            p.onFocusFollowUpRequested = { [weak self] in
                self?.focusFollowUpInput()
            }

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

        viewModel.execute(
            text: text,
            plugin: plugin,
            userInput: userInput,
            thinkModeOverride: thinkModeOverride,
            sourceAppPID: sourceAppPID
        )
    }

    func applyCurrentTheme() {
        panel?.appearance = AppSettings.shared.appTheme.nsAppearance
    }

    func dismiss() {
        viewModel.cancelPendingWork()
        guard let panel else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
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
        let visibleFrame = ScreenLocator.visibleFrame(for: anchorPoint)
        panel.minSize = NSSize(width: Self.minPanelWidth, height: Self.minPanelHeight)
        panel.maxSize = NSSize(
            width: min(visibleFrame.width * 0.85, Self.maxPanelWidthCap),
            height: visibleFrame.height * 0.85
        )
    }

    private func screen(for point: NSPoint) -> NSScreen? {
        ScreenLocator.screen(for: point)
    }

    private func calculatePanelFrame(anchorPoint: NSPoint, panelSize: NSSize) -> NSRect {
        ScreenLocator.frame(for: panelSize, anchoredAt: anchorPoint)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else { return }
        panelOrigin = NSPoint(x: panel.frame.midX, y: panel.frame.maxY + 10)
    }

    private func scheduleFollowUpFocus() {
        DispatchQueue.main.async { [weak self] in self?.focusFollowUpInput() }
    }

    private func focusFollowUpInput() {
        guard let panel, panel.isVisible, panel.isKeyWindow,
              let textField = panel.contentView?.firstTextField(
                withPlaceholder: UIString("Type your follow-up...")
              ) else {
            return
        }
        panel.makeKey()
        panel.makeFirstResponder(textField)
        textField.currentEditor()?.moveToEndOfDocument(nil)
    }
}

private extension NSView {
    func firstTextField(withPlaceholder placeholder: String) -> NSTextField? {
        if let textField = self as? NSTextField,
           textField.placeholderString == placeholder {
            return textField
        }

        for subview in subviews {
            if let match = subview.firstTextField(withPlaceholder: placeholder) {
                return match
            }
        }

        return nil
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
    private let executor: any PluginExecuting
    private let settings: AppSettings

    init(executor: (any PluginExecuting)? = nil, settings: AppSettings? = nil) {
        self.executor = executor ?? PluginExecutor.shared
        self.settings = settings ?? AppSettings.shared
    }

    @Published var sourceText: String = ""
    @Published var resultText: String = ""
    @Published var thinkingText: String = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var isPasting = false
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
    private var pasteTask: Task<Void, Never>?
    private var executionID = UUID()
    private var originalSelectedText = ""
    private var latestAnswerText: String = ""
    private var pendingFollowUpDisplayPrefix: String?
    private var sourceAppPID: pid_t = 0

    func execute(
        text: String,
        plugin: Plugin,
        userInput: String? = nil,
        thinkModeOverride: Bool? = nil,
        sourceAppPID: pid_t = 0
    ) {
        pasteTask?.cancel()
        isPasting = false
        sourceText = text
        originalSelectedText = text
        currentPlugin = plugin
        userInputText = userInput ?? ""
        self.thinkModeOverride = thinkModeOverride
        self.sourceAppPID = sourceAppPID
        latestAnswerText = ""
        pendingFollowUpDisplayPrefix = nil

        if plugin.showLanguageControls {
            let settings = self.settings
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
        cancelStream()
        guard let plugin = currentPlugin else { return }
        let requestID = executionID
        isGenerating = true
        isLoading = true
        errorMessage = nil
        let displayPrefix = pendingFollowUpDisplayPrefix ?? ""
        pendingFollowUpDisplayPrefix = nil
        resultText = displayPrefix
        thinkingText = ""
        isThinking = false

        let text = sourceText
        let userInput = userInputText.isEmpty ? nil : userInputText
        let source: Language? = plugin.showLanguageControls ? detectedSourceLanguage : nil
        let target: Language? = plugin.showLanguageControls ? currentTargetLanguage : nil
        let thinkMode = thinkModeOverride
        let streaming = settings.streamingEnabled

        currentStreamTask = Task {
            do {
                var answer = ""
                if streaming {
                    var reasoning = ""
                    var lastPublish: TimeInterval = 0
                    let stream = executor.executeStream(
                        text: text, plugin: plugin, userInput: userInput,
                        source: source, target: target, thinkModeOverride: thinkMode
                    )
                    for try await chunk in stream {
                        try Task.checkCancellation()
                        guard executionID == requestID else { return }
                        switch chunk {
                        case .thinking(let delta): reasoning += delta
                        case .text(let delta): answer += delta
                        case .done: break
                        }
                        // Markdown layout is expensive. Publish at most 30 times/second.
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastPublish >= 1.0 / 30 {
                            resultText = displayPrefix + answer
                            thinkingText = reasoning
                            isThinking = answer.isEmpty && !reasoning.isEmpty
                            isLoading = answer.isEmpty
                            lastPublish = now
                        }
                    }
                    try Task.checkCancellation()
                    guard executionID == requestID else { return }
                    thinkingText = reasoning
                } else {
                    answer = try await executor.execute(
                        text: text, plugin: plugin, userInput: userInput,
                        source: source, target: target, thinkModeOverride: thinkMode
                    )
                }
                try Task.checkCancellation()
                guard executionID == requestID else { return }
                resultText = displayPrefix + answer
                latestAnswerText = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                isLoading = false
                isThinking = false
                isGenerating = false
                currentStreamTask = nil
                // Keep the user's current selection/focus while they read or copy.
            } catch {
                guard !Task.isCancelled, executionID == requestID else { return }
                errorMessage = error.localizedDescription
                isLoading = false
                isThinking = false
                isGenerating = false
                currentStreamTask = nil
            }
        }
    }

    func copyResult() {
        guard !resultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        if !isPinned {
            dismiss()
        }
    }

    func insertResult() {
        pasteTextToSourceApp(originalSelectedText + "\n" + resultText)
    }

    func replaceResult() {
        pasteTextToSourceApp(resultText)
    }

    private func pasteTextToSourceApp(_ text: String) {
        guard !isGenerating, !isPasting, !text.isEmpty else { return }
        guard sourceAppPID != 0, sourceAppPID != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: sourceAppPID), !app.isTerminated else {
            errorMessage = UIString("Source app unavailable. Copy the result and paste it manually.")
            return
        }
        let initialChangeCount = NSPasteboard.general.changeCount
        let pid = sourceAppPID
        isPasting = true
        pasteTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isPasting = false }
            guard app.activate(options: []) else {
                self.errorMessage = UIString("Source app unavailable. Copy the result and paste it manually.")
                return
            }
            do {
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(25))
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
                }
                try Task.checkCancellation()
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                      NSPasteboard.general.changeCount == initialChangeCount else {
                    self.errorMessage = UIString("Paste canceled because the app or clipboard changed. Copy the result and paste it manually.")
                    return
                }
                let source = CGEventSource(stateID: .privateState)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else { return }
                // Explicit insertion leaves this text on the clipboard. Delayed restoration
                // cannot reliably know when an external editor has finished reading it.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.postToPid(pid)
                up.postToPid(pid)
                self.dismiss()
            } catch { /* Canceled by closing the panel or starting another action. */ }
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
            let settings = self.settings
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

    func cancelStream() {
        executionID = UUID()
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isLoading = false
        isThinking = false
        isGenerating = false
    }

    func cancelPendingWork() {
        pasteTask?.cancel()
        pasteTask = nil
        isPasting = false
        cancelStream()
    }

    func dismiss() {
        cancelPendingWork()
        onDismiss?()
    }
}

// MARK: - Result View

struct ResultContentView: View {
    private static let maxAutoScrollableContentHeight: CGFloat = 460

    @ObservedObject var viewModel: ResultViewModel
    let onFocusFollowUpRequested: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var bodyContentHeight: CGFloat = 0
    @State private var followUpInputText: String = ""
    @FocusState private var isFollowUpFocused: Bool

    private var panelFontSize: CGFloat {
        CGFloat(settings.resultPanelFontSize)
    }

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
            if !viewModel.sourceText.isEmpty {
                // Source text
                Text(viewModel.sourceText)
                    .font(.system(size: max(10, panelFontSize - 1)))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            // User input (for Ask-type plugins)
            if !viewModel.userInputText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: max(9, panelFontSize - 3)))
                        .foregroundStyle(.secondary)
                    Text(viewModel.userInputText)
                        .font(.system(size: max(10, panelFontSize - 1), weight: .medium))
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
            if viewModel.isGenerating || viewModel.errorMessage != nil || !viewModel.resultText.isEmpty {
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
                        .font(.system(size: max(9, panelFontSize - 2)))
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
                        .font(.system(size: max(9, panelFontSize - 2), weight: .medium))
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
                    .font(.system(size: panelFontSize))
                    .foregroundStyle(.secondary)
            }
        } else if let error = viewModel.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: max(10, panelFontSize - 1)))
                    .foregroundStyle(.secondary)
            }
        } else if !viewModel.resultText.isEmpty {
            MarkdownContentView(text: viewModel.resultText, baseFontSize: panelFontSize)
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
            !viewModel.isGenerating &&
            viewModel.errorMessage == nil &&
            !viewModel.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var followUpInput: some View {
        HStack(spacing: 8) {
            TextField(UIString("Type your follow-up..."), text: $followUpInputText)
                .textFieldStyle(.plain)
                .font(.system(size: panelFontSize))
                .focused($isFollowUpFocused)
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
        isFollowUpFocused = false
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
                    ActionChip(title: UIString("Copy"), icon: "doc.on.doc") {
                        viewModel.copyResult()
                    }
                    .disabled(viewModel.resultText.isEmpty)
                    .help(UIString("Copy All (⇧⌘C)"))
                }
                if actions.contains(.insert) {
                    ActionChip(title: UIString("Insert"), icon: "text.insert", shortcut: "i") {
                        viewModel.insertResult()
                    }
                    .disabled(viewModel.isGenerating || viewModel.isPasting || viewModel.resultText.isEmpty)
                }
                if actions.contains(.replace) {
                    ActionChip(title: UIString("Replace"), icon: "arrow.2.squarepath", shortcut: "r") {
                        viewModel.replaceResult()
                    }
                    .disabled(viewModel.isGenerating || viewModel.isPasting || viewModel.resultText.isEmpty)
                }
                if viewModel.isGenerating {
                    ActionChip(title: UIString("Stop"), icon: "stop.fill") {
                        viewModel.cancelStream()
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
    let shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    init(title: String, icon: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.action = action
    }

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
        .keyboardShortcut(
            shortcut.flatMap { $0.first.map { KeyboardShortcut(KeyEquivalent($0), modifiers: .command) } }
        )
    }
}
