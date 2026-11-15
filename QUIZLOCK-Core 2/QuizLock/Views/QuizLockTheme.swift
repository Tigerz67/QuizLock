import SwiftUI

/// Small reusable visual system for QUIZLOCK's dark, minimal interface.
enum QuizLockTheme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.065)
    static let surface = Color(red: 0.075, green: 0.088, blue: 0.12)
    static let elevated = Color(red: 0.105, green: 0.12, blue: 0.16)
    static let accent = Color(red: 0.60, green: 0.47, blue: 0.98)
    static let accentBlue = Color(red: 0.32, green: 0.61, blue: 0.98)
    static let mint = Color(red: 0.35, green: 0.83, blue: 0.68)
    static let warning = Color(red: 0.98, green: 0.68, blue: 0.33)
    static let danger = Color(red: 0.96, green: 0.38, blue: 0.43)
    static let secondaryText = Color.white.opacity(0.62)
    static let border = Color.white.opacity(0.08)
}

struct QuizLockCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuizLockTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(QuizLockTheme.border, lineWidth: 1)
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage).fontWeight(.semibold)
                }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [QuizLockTheme.accent, QuizLockTheme.accentBlue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.48 : 1)
        .buttonStyle(.plain)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(QuizLockTheme.secondaryText)
            }
        }
    }
}

extension View {
    func quizLockScreenBackground() -> some View {
        background(QuizLockTheme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
