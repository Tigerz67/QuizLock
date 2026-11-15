import FamilyControls
import SwiftData
import SwiftUI

struct AppBlockerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @Query private var banks: [StudyTimeBank]
    @Query private var preferences: [StudyPreferences]

    @State private var unlockMinutes = 10
    @State private var activitySelection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var bank: StudyTimeBank? { banks.first(where: { $0.id == "primary" }) ?? banks.first }
    private var settings: StudyPreferences? {
        preferences.first(where: { $0.id == "primary" }) ?? preferences.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                timeBankCard
                blockerCard
                unlockCard
                if let lastError = screenTimeManager.lastErrorMessage {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(QuizLockTheme.warning)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .quizLockScreenBackground()
        .navigationTitle("App Blocker")
        .navigationBarTitleDisplayMode(.large)
        .familyActivityPicker(
            headerText: "Choose apps, categories, and websites to shield.",
            footerText: "QUIZLOCK stores only the private tokens provided by Apple.",
            isPresented: $isPickerPresented,
            selection: $activitySelection
        )
        .onAppear {
            screenTimeManager.refresh()
            activitySelection = screenTimeManager.selection
            unlockMinutes = settings?.defaultUnlockMinutes ?? 10
        }
        .onChange(of: activitySelection) { _, newSelection in
            do {
                try screenTimeManager.saveSelection(newSelection)
            } catch {
                presentError(error)
            }
        }
        .onChange(of: settings?.defaultUnlockMinutes) { _, newValue in
            if let newValue, unlockMinutes == 10 {
                unlockMinutes = newValue
            }
        }
        .alert("QUIZLOCK", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Protect your focus")
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text("Selected apps stay shielded while blocking is on.")
                .font(.subheadline)
                .foregroundStyle(QuizLockTheme.secondaryText)
        }
        .padding(.top, 6)
    }

    private var timeBankCard: some View {
        QuizLockCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AVAILABLE TIME")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(QuizLockTheme.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(bank?.availableMinutes ?? 0)")
                            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("min")
                            .font(.headline)
                            .foregroundStyle(QuizLockTheme.secondaryText)
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(QuizLockTheme.accent.opacity(0.15)).frame(width: 68, height: 68)
                    Image(systemName: "hourglass")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(QuizLockTheme.accent)
                }
            }

            Divider().overlay(QuizLockTheme.border)

            HStack {
                bankStat(title: "Earned", value: bank?.totalMinutesEarned ?? 0, tint: QuizLockTheme.mint)
                Spacer()
                bankStat(title: "Spent", value: bank?.totalMinutesSpent ?? 0, tint: QuizLockTheme.accentBlue)
                Spacer()
                bankStat(title: "Penalties", value: bank?.totalPenaltyMinutes ?? 0, tint: QuizLockTheme.warning)
            }
        }
    }

    private var blockerCard: some View {
        QuizLockCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App blocking")
                        .font(.headline)
                    Text(screenTimeManager.isBlockingEnabled ? "Your selected apps are shielded" : "Blocking is currently off")
                        .font(.caption)
                        .foregroundStyle(QuizLockTheme.secondaryText)
                }
                Spacer()
                Toggle("Blocking", isOn: blockingBinding)
                    .labelsHidden()
                    .tint(QuizLockTheme.mint)
            }

            Divider().overlay(QuizLockTheme.border)

            HStack(spacing: 10) {
                Label("\(screenTimeManager.selection.applicationTokens.count) apps", systemImage: "app.fill")
                Label("\(screenTimeManager.selection.categoryTokens.count) categories", systemImage: "square.grid.2x2.fill")
                Label("\(screenTimeManager.selection.webDomainTokens.count) sites", systemImage: "globe")
            }
            .font(.caption)
            .foregroundStyle(QuizLockTheme.secondaryText)

            Button {
                activitySelection = screenTimeManager.selection
                isPickerPresented = true
            } label: {
                Label("Edit selected apps", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var unlockCard: some View {
        QuizLockCard {
            SectionHeading(
                title: "Spend earned time",
                subtitle: "Correct quiz answers add minutes to this bank."
            )

            if screenTimeManager.remainingUnlockSeconds > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                        .font(.title2)
                        .foregroundStyle(QuizLockTheme.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Temporary unlock active")
                            .font(.subheadline.weight(.semibold))
                        Text(timeString(screenTimeManager.remainingUnlockSeconds) + " remaining")
                            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                            .foregroundStyle(QuizLockTheme.mint)
                    }
                    Spacer()
                }
                .padding(14)
                .background(QuizLockTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            } else {
                Stepper(value: $unlockMinutes, in: 1...120) {
                    HStack {
                        Text("Unlock duration")
                        Spacer()
                        Text("\(unlockMinutes) minutes")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                .tint(QuizLockTheme.accent)

                PrimaryActionButton(
                    title: "Spend \(unlockMinutes) minutes",
                    systemImage: "lock.open.fill",
                    isDisabled: !canSpend
                ) {
                    spendTime()
                }

                Text("This subtracts \(unlockMinutes) minutes from your bank. Shields are scheduled to return when the unlock ends.")
                    .font(.caption2)
                    .foregroundStyle(QuizLockTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canSpend: Bool {
        guard let bank else { return false }
        return screenTimeManager.isBlockingEnabled
            && screenTimeManager.authorizationStatus == .approved
            && bank.availableMinutes >= unlockMinutes
            && screenTimeManager.remainingUnlockSeconds == 0
    }

    private var blockingBinding: Binding<Bool> {
        Binding(
            get: { screenTimeManager.isBlockingEnabled },
            set: { isEnabled in
                if isEnabled {
                    do { try screenTimeManager.enableBlocking() }
                    catch { presentError(error) }
                } else {
                    screenTimeManager.disableBlocking()
                }
            }
        )
    }

    private func bankStat(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(QuizLockTheme.secondaryText)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func spendTime() {
        guard let bank else {
            presentError("The time bank has not been initialized yet.")
            return
        }
        do {
            try screenTimeManager.spendMinutes(unlockMinutes, from: bank, in: modelContext)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        presentError(error.localizedDescription)
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
