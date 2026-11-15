import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Runs outside the main app process and restores shields after a paid unlock.
final class QuizLockMonitorExtension: DeviceActivityMonitor {
    private let managedSettingsStore = ManagedSettingsStore(
        named: ManagedSettingsStore.Name(QuizLockShared.managedSettingsStoreName)
    )

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard activity == QuizLockShared.unlockActivityName,
              let defaults = UserDefaults(suiteName: QuizLockShared.appGroupIdentifier),
              defaults.bool(forKey: QuizLockShared.blockingEnabledKey),
              let expiry = defaults.object(forKey: QuizLockShared.unlockExpiryKey) as? Date,
              Date() >= expiry,
              let selectionData = defaults.data(forKey: QuizLockShared.selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) else {
            return
        }

        applyShield(for: selection)
        defaults.removeObject(forKey: QuizLockShared.unlockExpiryKey)
    }

    private func applyShield(for selection: FamilyActivitySelection) {
        let applications = selection.applicationTokens
        let categories = selection.categoryTokens
        let webDomains = selection.webDomainTokens

        managedSettingsStore.shield.applications = applications.isEmpty ? nil : applications
        managedSettingsStore.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: [])
        managedSettingsStore.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        managedSettingsStore.shield.webDomainCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: [])
    }
}
