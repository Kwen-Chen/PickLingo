import XCTest
@testable import PickLingoCore

@MainActor
final class MonitoringLifecycleTests: XCTestCase {
    func testGrantAfterStartupStartsMonitoringWithoutOnboardingCallback() {
        var installations = 0
        let lifecycle = SelectionMonitoringLifecycle(install: { installations += 1; return true }, remove: {})
        lifecycle.reconcile(enabled: true, trusted: false)
        XCTAssertEqual(lifecycle.state, .permissionRequired)
        XCTAssertEqual(installations, 0)

        // Permission changes even if the welcome/settings window has been closed.
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(lifecycle.state, .active)
        XCTAssertEqual(installations, 1)
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(installations, 1, "Permission checks must not reset a current selection")
    }

    func testRevocationStopsMonitoringAndReauthorizationRestartsIt() {
        var installations = 0
        var removals = 0
        let lifecycle = SelectionMonitoringLifecycle(install: { installations += 1; return true }, remove: { removals += 1 })
        lifecycle.reconcile(enabled: true, trusted: true)
        lifecycle.reconcile(enabled: true, trusted: false)
        XCTAssertEqual(lifecycle.state, .permissionRequired)
        XCTAssertEqual(removals, 1)
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(lifecycle.state, .active)
        XCTAssertEqual(installations, 2)
    }

    func testDisabledSettingStaysDisabledAfterPermissionOrWakeChange() {
        var installations = 0
        var removals = 0
        let lifecycle = SelectionMonitoringLifecycle(install: { installations += 1; return true }, remove: { removals += 1 })
        lifecycle.reconcile(enabled: true, trusted: true)
        lifecycle.reconcile(enabled: false, trusted: false)
        lifecycle.reconcile(enabled: false, trusted: true, restart: true)
        XCTAssertEqual(lifecycle.state, .disabled)
        XCTAssertEqual(installations, 1)
        XCTAssertEqual(removals, 1)
    }

    func testWakeRecoveryReplacesListenersWithoutDuplicatingThem() {
        var listeners = 0
        var installations = 0
        let lifecycle = SelectionMonitoringLifecycle(install: {
            XCTAssertEqual(listeners, 0)
            listeners += 4
            installations += 1
            return true
        }, remove: { listeners = 0 })
        lifecycle.reconcile(enabled: true, trusted: true)
        lifecycle.reconcile(enabled: true, trusted: true, restart: true)
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(listeners, 4)
        XCTAssertEqual(installations, 2)
        XCTAssertEqual(lifecycle.state, .active)
    }

    func testFailedRegistrationCleansUpAndRetries() {
        var attempts = 0
        var removals = 0
        let lifecycle = SelectionMonitoringLifecycle(install: {
            attempts += 1
            return attempts > 1
        }, remove: { removals += 1 })
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(lifecycle.state, .unavailable)
        XCTAssertEqual(removals, 1)
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(lifecycle.state, .active)
        XCTAssertEqual(attempts, 2)
    }

    func testLostEventDeliveryIsRecoveredEvenWhilePermissionRemainsGranted() {
        var healthy = true
        var installations = 0
        var removals = 0
        let lifecycle = SelectionMonitoringLifecycle(install: {
            installations += 1
            healthy = true
            return true
        }, remove: { removals += 1 }, isHealthy: { healthy })
        lifecycle.reconcile(enabled: true, trusted: true)
        healthy = false // A disabled/invalidated system tap still has an allocated token.
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(installations, 2)
        XCTAssertEqual(removals, 1)
        XCTAssertEqual(lifecycle.state, .active)
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(installations, 2, "Healthy listeners and pending selections must be left alone")
    }

    func testFailedRecoveryReportsUnavailableAndRetriesWithoutDuplicatingListeners() {
        var healthy = true
        var canInstall = true
        var listeners = 0
        let lifecycle = SelectionMonitoringLifecycle(install: {
            XCTAssertEqual(listeners, 0)
            guard canInstall else { return false }
            listeners = 1
            healthy = true
            return true
        }, remove: { listeners = 0 }, isHealthy: { healthy })
        lifecycle.reconcile(enabled: true, trusted: true)
        healthy = false
        canInstall = false
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(lifecycle.state, .unavailable)
        XCTAssertEqual(listeners, 0)
        canInstall = true
        lifecycle.reconcile(enabled: true, trusted: true)
        XCTAssertEqual(lifecycle.state, .active)
        XCTAssertEqual(listeners, 1)
        healthy = false
        lifecycle.reconcile(enabled: false, trusted: true)
        XCTAssertEqual(lifecycle.state, .disabled)
        XCTAssertEqual(listeners, 0, "Recovery must respect the user's disabled setting")
    }
}
