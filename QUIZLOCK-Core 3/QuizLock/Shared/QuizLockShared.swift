import DeviceActivity
import Foundation

/// Keep these identifiers identical in the app target, monitor extension,
/// App Group entitlements, and Xcode signing configuration.
enum QuizLockShared {
    static let appGroupIdentifier = "group.com.yourcompany.QUIZLOCK"
    static let managedSettingsStoreName = "com.yourcompany.QUIZLOCK.managed-settings"

    static let selectionKey = "quizLock.familyActivitySelection"
    static let blockingEnabledKey = "quizLock.blockingEnabled"
    static let unlockExpiryKey = "quizLock.unlockExpiry"

    static let unlockActivityName = DeviceActivityName("com.yourcompany.QUIZLOCK.unlock-window")
}
