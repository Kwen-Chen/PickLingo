import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var isGranted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.point.up.left.and.text")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("PickLingo")
                .font(.title)
                .fontWeight(.semibold)

            Text(String(localized: "PickLingo needs Accessibility permission to detect text selection across apps."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if isGranted {
                Label(String(localized: "Permission Granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button(String(localized: "Open Accessibility Settings")) {
                    AccessibilityMonitor.shared.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(String(localized: "After granting permission, this screen will update automatically."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isGranted {
                Button(String(localized: "Get Started")) {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 440, height: 320)
        .onAppear {
            if isGranted { onComplete() }
        }
        .onReceive(timer) { _ in
            let granted = AXIsProcessTrusted()
            guard granted != isGranted else { return }
            isGranted = granted
            if granted { onComplete() }
        }
    }
}
