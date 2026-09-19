import AppKit

@main
enum PickLingoApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // AppDelegate owns all windows. A separate SwiftUI Settings scene would
        // create a second settings window with an independent Dock lifecycle.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
