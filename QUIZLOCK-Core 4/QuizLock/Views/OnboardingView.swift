import FamilyControls
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @AppStorage("quizLock.didFinishOnboarding") private var didFinishOnboarding = false

    @State private var isRequestingAuthorization = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [QuizLockTheme.accent, QuizLockTheme.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                Image(systemName: "lock.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: QuizLockTheme.accent.opacity(0.25), radius: 24, y: 12)

            Text("QUIZLOCK")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(1.5)
                .padding(.top, 26)

            Text("Study first. Earn your screen time.")
                .font(.headline)
                .foregroundStyle(QuizLockTheme.secondaryText)
                .padding(.top, 7)

            Spacer().frame(height: 38)

            VStack(alignment: .leading, spacing: 18) {
                onboardingFeature(
                    icon: "doc.text.fill",
                    title: "Use your own notes",
                    detail: "Paste or import what you're studying. Your notes stay on your device."
                )
                onboardingFeature(
                    icon: "sparkles",
                    title: "Generate questions offline",
                    detail: "A small local AI model turns your notes into grade-appropriate quizzes."
                )
                onboardingFeature(
                    icon: "hourglass",
                    title: "Earn focused screen time",
                    detail: "Correct answers add minutes to your bank. Spend them to unlock selected apps."
                )
            }
            .padding(20)
            .background(QuizLockTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(QuizLockTheme.border, lineWidth: 1)
            }

            Spacer(minLength: 28)

            PrimaryActionButton(
                title: "Allow Screen Time Access",
                systemImage: "lock.shield.fill",
                isLoading: isRequestingAuthorization
            ) {
                Task { await authorizeScreenTime() }
            }

            Button("Set this up later") {
                didFinishOnboarding = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(QuizLockTheme.secondaryText)
            .padding(.top, 17)
            .padding(.bottom, 24)

            Text("The first Study screen visit downloads about 695 MB of AI model weights. Later quiz generation works offline. QUIZLOCK uses Apple's Screen Time APIs; you choose what to shield and can change your selection in Settings.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(QuizLockTheme.secondaryText.opacity(0.85))
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quizLockScreenBackground()
        .alert("Screen Time permission", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Authorization was not completed.")
        }
    }

    private func onboardingFeature(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(QuizLockTheme.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(QuizLockTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private func authorizeScreenTime() async {
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        do {
            try await screenTimeManager.requestAuthorization()
            if screenTimeManager.authorizationStatus == .approved {
                didFinishOnboarding = true
            } else {
                errorMessage = "Screen Time access was not approved. You can try again in Settings."
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
