import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftData

@MainActor
final class ScreenTimeManager: ObservableObject {
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var selection: FamilyActivitySelection
    @Published private(set) var isBlockingEnabled: Bool
    @Published private(set) var unlockEndsAt: Date?
    @Published private(set) var remainingUnlockSeconds: Int = 0
    @Published private(set) var lastErrorMessage: String?

    private let authorizationCenter = AuthorizationCenter.shared
    private let managedSettingsStore: ManagedSettingsStore
    private let activityCenter = DeviceActivityCenter()
    private let sharedDefaults: UserDefaults?
    private var countdownTask: Task<Void, Never>?

    private let minimumDeviceActivityInterval: TimeInterval = 15 * 60

    init() {
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        self.sharedDefaults = UserDefaults(suiteName: QuizLockShared.appGroupIdentifier)
        self.managedSettingsStore = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(QuizLockShared.managedSettingsStoreName)
        )

        if let defaults = sharedDefaults,
           let data = defaults.data(forKey: QuizLockShared.selectionKey),
           let savedSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            self.selection = savedSelection
        } else {
            self.selection = FamilyActivitySelection()
        }

        self.isBlockingEnabled = sharedDefaults?.bool(forKey: QuizLockShared.blockingEnabledKey) ?? false
        self.unlockEndsAt = sharedDefaults?.object(forKey: QuizLockShared.unlockExpiryKey) as? Date

        restoreBlockingStateAfterLaunch()
    }

    // MARK: Authorization

    func requestAuthorization() async throws {
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
            lastErrorMessage = nil
        } catch {
            authorizationStatus = authorizationCenter.authorizationStatus
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: App selection

    func saveSelection(_ newSelection: FamilyActivitySelection) throws {
        guard let sharedDefaults else { throw ScreenTimeManagerError.appGroupUnavailable }

        let encodedSelection = try JSONEncoder().encode(newSelection)
        sharedDefaults.set(encodedSelection, forKey: QuizLockShared.selectionKey)
        selection = newSelection

        if isBlockingEnabled && unlockIsNotActive {
            if hasShieldTargets(in: newSelection) {
                applyShield(for: newSelection)
            } else {
                disableBlocking()
            }
        }
        lastErrorMessage = nil
    }

    // MARK: Blocking controls

    func enableBlocking() throws {
        guard authorizationCenter.authorizationStatus == .approved else {
            throw ScreenTimeManagerError.authorizationRequired
        }
        guard !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty else {
            throw ScreenTimeManagerError.noAppsSelected
        }
        guard let sharedDefaults else { throw ScreenTimeManagerError.appGroupUnavailable }

        sharedDefaults.set(true, forKey: QuizLockShared.blockingEnabledKey)
        isBlockingEnabled = true
        applyShield(for: selection)
        lastErrorMessage = nil
    }

    func disableBlocking() {
        sharedDefaults?.set(false, forKey: QuizLockShared.blockingEnabledKey)
        sharedDefaults?.removeObject(forKey: QuizLockShared.unlockExpiryKey)
        activityCenter.stopMonitoring([QuizLockShared.unlockActivityName])
        countdownTask?.cancel()
        countdownTask = nil
        managedSettingsStore.clearAllSettings()
        isBlockingEnabled = false
        unlockEndsAt = nil
        remainingUnlockSeconds = 0
        lastErrorMessage = nil
    }

    // MARK: Earned-time spending

    /// Temporarily removes this app's shields and deducts the requested number
    /// of minutes from SwiftData. The Device Activity monitor extension restores
    /// the shields after the unlock window, even if this app is suspended.
    func spendMinutes(
        _ minutes: Int = 10,
        from bank: StudyTimeBank,
        in modelContext: ModelContext
    ) throws {
        guard minutes > 0 else { throw ScreenTimeManagerError.invalidUnlockDuration }
        guard isBlockingEnabled else { throw ScreenTimeManagerError.blockingIsOff }
        guard authorizationCenter.authorizationStatus == .approved else {
            throw ScreenTimeManagerError.authorizationRequired
        }
        guard bank.availableMinutes >= minutes else {
            throw ScreenTimeManagerError.insufficientBalance(
                required: minutes,
                available: bank.availableMinutes
            )
        }
        guard let sharedDefaults else { throw ScreenTimeManagerError.appGroupUnavailable }

        let now = Date()
        if let unlockEndsAt, unlockEndsAt > now {
            throw ScreenTimeManagerError.unlockAlreadyActive
        }
        guard hasShieldTargets(in: selection) else {
            throw ScreenTimeManagerError.noAppsSelected
        }
        let expiry = now.addingTimeInterval(TimeInterval(minutes * 60))

        // DeviceActivity rejects schedules shorter than 15 minutes. For a
        // shorter unlock, start the 15-minute monitoring interval in the past
        // so its scheduled end is still exactly `expiry`.
        // Apple documents that a schedule already in progress calls
        // intervalDidStart immediately when monitoring begins.
        let intervalStart = min(now, expiry.addingTimeInterval(-minimumDeviceActivityInterval))
        let schedule = DeviceActivitySchedule(
            intervalStart: Self.dateComponents(for: intervalStart),
            intervalEnd: Self.dateComponents(for: expiry),
            repeats: false
        )

        let originalBalance = bank.availableMinutes
        let originalSpent = bank.totalMinutesSpent
        let originalUpdatedAt = bank.updatedAt

        sharedDefaults.set(expiry, forKey: QuizLockShared.unlockExpiryKey)
        sharedDefaults.set(true, forKey: QuizLockShared.blockingEnabledKey)

        do {
            try activityCenter.startMonitoring(QuizLockShared.unlockActivityName, during: schedule)

            bank.availableMinutes -= minutes
            bank.totalMinutesSpent += minutes
            bank.updatedAt = now
            try modelContext.save()

            managedSettingsStore.clearAllSettings()
            unlockEndsAt = expiry
            isBlockingEnabled = true
            lastErrorMessage = nil
            startForegroundCountdown()
        } catch {
            bank.availableMinutes = originalBalance
            bank.totalMinutesSpent = originalSpent
            bank.updatedAt = originalUpdatedAt
            sharedDefaults.removeObject(forKey: QuizLockShared.unlockExpiryKey)
            activityCenter.stopMonitoring([QuizLockShared.unlockActivityName])
            applyShield(for: selection)
            try? modelContext.save()
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    /// Call this from scenePhase/on-appear so an expired unlock is reconciled
    /// immediately when the student returns to the app.
    func refresh() {
        authorizationStatus = authorizationCenter.authorizationStatus
        restoreBlockingStateAfterLaunch()
    }

    // MARK: Internal timer and restoration

    private var unlockIsNotActive: Bool {
        guard let unlockEndsAt else { return true }
        return unlockEndsAt <= .now
    }

    private func restoreBlockingStateAfterLaunch() {
        guard let sharedDefaults else { return }

        isBlockingEnabled = sharedDefaults.bool(forKey: QuizLockShared.blockingEnabledKey)
        unlockEndsAt = sharedDefaults.object(forKey: QuizLockShared.unlockExpiryKey) as? Date

        if let expiry = unlockEndsAt, expiry > .now {
            startForegroundCountdown()
        } else {
            unlockEndsAt = nil
            remainingUnlockSeconds = 0
            sharedDefaults.removeObject(forKey: QuizLockShared.unlockExpiryKey)
            if isBlockingEnabled && authorizationCenter.authorizationStatus == .approved {
                if hasShieldTargets(in: selection) {
                    applyShield(for: selection)
                } else {
                    lastErrorMessage = ScreenTimeManagerError.noAppsSelected.localizedDescription
                }
            }
        }
    }

    private func startForegroundCountdown() {
        countdownTask?.cancel()
        guard let unlockEndsAt else { return }

        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = Int(ceil(self.unlockEndsAt?.timeIntervalSinceNow ?? 0))
                self.remainingUnlockSeconds = max(0, remaining)

                if remaining <= 0 {
                    self.finishUnlockIfExpired()
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func finishUnlockIfExpired() {
        guard let expiry = unlockEndsAt, Date() >= expiry else { return }

        if isBlockingEnabled && authorizationCenter.authorizationStatus == .approved,
           hasShieldTargets(in: selection) {
            applyShield(for: selection)
        }

        sharedDefaults?.removeObject(forKey: QuizLockShared.unlockExpiryKey)
        activityCenter.stopMonitoring([QuizLockShared.unlockActivityName])
        countdownTask?.cancel()
        countdownTask = nil
        unlockEndsAt = nil
        remainingUnlockSeconds = 0
    }

    private func hasShieldTargets(in selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    private func applyShield(for selection: FamilyActivitySelection) {
        guard hasShieldTargets(in: selection) else { return }
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

    private static func dateComponents(for date: Date) -> DateComponents {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        components.calendar = Calendar.current
        components.timeZone = Calendar.current.timeZone
        return components
    }
}

enum ScreenTimeManagerError: LocalizedError {
    case appGroupUnavailable
    case authorizationRequired
    case noAppsSelected
    case blockingIsOff
    case invalidUnlockDuration
    case unlockAlreadyActive
    case insufficientBalance(required: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The App Group is not available. Check the App Groups capability and matching identifier on both targets."
        case .authorizationRequired:
            "Allow QUIZLOCK to use Screen Time in the system authorization prompt first."
        case .noAppsSelected:
            "Choose at least one app, app category, or website to block."
        case .blockingIsOff:
            "Turn blocking on before spending banked time."
        case .invalidUnlockDuration:
            "Unlock duration must be at least one minute."
        case .unlockAlreadyActive:
            "Your apps are already temporarily unlocked. Wait for that session to finish."
        case let .insufficientBalance(required, available):
            "You need \(required) minutes, but your bank has \(available) minutes."
        }
    }
}
