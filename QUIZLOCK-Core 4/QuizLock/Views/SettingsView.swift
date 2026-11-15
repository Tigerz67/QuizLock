import FamilyControls
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @Query private var preferences: [StudyPreferences]

    @State private var activitySelection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var isRequestingAuthorization = false
    @State private var feedbackMessage: String?
    @State private var showFeedback = false

    private var settings: StudyPreferences? {
        preferences.first(where: { $0.id == "primary" }) ?? preferences.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                QuizLockCard {
                    SectionHeading(
                        title: "Study level",
                        subtitle: "Questions are written for this level, not just simplified randomly."
                    )
                    Picker("Grade level", selection: gradeBinding) {
                        ForEach(StudyGradeLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                }

                QuizLockCard {
                    SectionHeading(
                        title: "Question formats",
                        subtitle: "Choose what QUIZLOCK can generate. Keep at least one enabled."
                    )
                    ForEach(StudyQuestionType.allCases) { type in
                        Toggle(isOn: questionTypeBinding(type)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.title).font(.subheadline.weight(.medium))
                                Text(questionTypeDescription(type))
                                    .font(.caption)
                                    .foregroundStyle(QuizLockTheme.secondaryText)
                            }
                        }
                        .tint(QuizLockTheme.accent)
                        if type != StudyQuestionType.allCases.last {
                            Divider().overlay(QuizLockTheme.border)
                        }
                    }
                }

                QuizLockCard {
                    SectionHeading(
                        title: "Quiz rewards",
                        subtitle: "Set how many minutes each correct answer earns."
                    )
                    settingStepper(
                        title: "Questions per quiz",
                        value: questionsPerSetBinding,
                        range: 1...20,
                        suffix: "questions"
                    )
                    Divider().overlay(QuizLockTheme.border)
                    settingStepper(
                        title: "Reward per correct answer",
                        value: rewardBinding,
                        range: 1...30,
                        suffix: "min"
                    )
                    Divider().overlay(QuizLockTheme.border)
                    settingStepper(
                        title: "Default app unlock",
                        value: defaultUnlockBinding,
                        range: 1...120,
                        suffix: "min"
                    )
                }

                QuizLockCard {
                    SectionHeading(
                        title: "Wrong-answer penalty",
                        subtitle: "Choose what happens when an answer is incorrect."
                    )
                    Picker("Penalty", selection: penaltyBinding) {
                        ForEach(QuizPenaltyPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 12))

                    if settings?.penaltyPolicy.appliesCooldown == true {
                        settingStepper(
                            title: "Quiz cooldown",
                            value: cooldownBinding,
                            range: 15...600,
                            suffix: "sec"
                        )
                    }
                }

                QuizLockCard {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(QuizLockTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Screen Time access")
                                .font(.headline)
                            Text(authorizationDescription)
                                .font(.caption)
                                .foregroundStyle(QuizLockTheme.secondaryText)
                        }
                        Spacer()
                    }

                    if screenTimeManager.authorizationStatus != .approved {
                        PrimaryActionButton(
                            title: "Authorize Screen Time",
                            systemImage: "checkmark.shield",
                            isLoading: isRequestingAuthorization
                        ) {
                            Task { await requestAuthorization() }
                        }
                    }

                    Divider().overlay(QuizLockTheme.border)

                    SectionHeading(
                        title: "Apps and websites",
                        subtitle: "Apple's picker keeps your selected app identities private from QUIZLOCK."
                    )
                    Text(selectionSummary)
                        .font(.subheadline)
                        .foregroundStyle(QuizLockTheme.secondaryText)

                    Button {
                        activitySelection = screenTimeManager.selection
                        isPickerPresented = true
                    } label: {
                        Label("Choose apps to block", systemImage: "square.grid.2x2")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                Text("Your notes, questions, settings, and time bank are saved locally. The model is downloaded from Hugging Face on first use; inference is performed on this device.")
                    .font(.caption2)
                    .foregroundStyle(QuizLockTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .quizLockScreenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .familyActivityPicker(
            headerText: "Choose the apps, categories, and websites QUIZLOCK should shield.",
            footerText: "Your choices are represented by private system tokens.",
            isPresented: $isPickerPresented,
            selection: $activitySelection
        )
        .onAppear {
            activitySelection = screenTimeManager.selection
        }
        .onChange(of: activitySelection) { _, newSelection in
            do {
                try screenTimeManager.saveSelection(newSelection)
            } catch {
                feedbackMessage = error.localizedDescription
                showFeedback = true
            }
        }
        .alert("QUIZLOCK", isPresented: $showFeedback) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Personalize your focus")
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text("Set your level, quiz style, rewards, and blocked apps.")
                .font(.subheadline)
                .foregroundStyle(QuizLockTheme.secondaryText)
        }
        .padding(.top, 6)
    }

    private var gradeBinding: Binding<StudyGradeLevel> {
        Binding(
            get: { settings?.gradeLevel ?? .grade9 },
            set: { value in updateSettings { $0.gradeLevel = value } }
        )
    }

    private var penaltyBinding: Binding<QuizPenaltyPolicy> {
        Binding(
            get: { settings?.penaltyPolicy ?? .cooldown60Seconds },
            set: { value in updateSettings { $0.penaltyPolicy = value } }
        )
    }

    private var questionsPerSetBinding: Binding<Int> {
        integerBinding(keyPath: \.questionsPerSet, fallback: 5)
    }

    private var rewardBinding: Binding<Int> {
        integerBinding(keyPath: \.minutesPerCorrectAnswer, fallback: 3)
    }

    private var defaultUnlockBinding: Binding<Int> {
        integerBinding(keyPath: \.defaultUnlockMinutes, fallback: 10)
    }

    private var cooldownBinding: Binding<Int> {
        integerBinding(keyPath: \.cooldownSeconds, fallback: 60)
    }

    private func integerBinding(
        keyPath: ReferenceWritableKeyPath<StudyPreferences, Int>,
        fallback: Int
    ) -> Binding<Int> {
        Binding(
            get: { settings?[keyPath: keyPath] ?? fallback },
            set: { value in updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func questionTypeBinding(_ type: StudyQuestionType) -> Binding<Bool> {
        Binding(
            get: { settings?.selectedQuestionTypes.contains(type) ?? (type == .multipleChoice) },
            set: { isEnabled in
                updateSettings { preference in
                    var selected = preference.selectedQuestionTypes
                    if isEnabled {
                        selected.insert(type)
                    } else {
                        selected.remove(type)
                    }
                    if selected.isEmpty {
                        selected.insert(type)
                    }
                    preference.selectedQuestionTypes = selected
                }
            }
        )
    }

    private var authorizationDescription: String {
        screenTimeManager.authorizationStatus == .approved
            ? "Authorized on this device"
            : "Not authorized yet"
    }

    private var selectionSummary: String {
        let selection = screenTimeManager.selection
        return "\(selection.applicationTokens.count) apps • \(selection.categoryTokens.count) categories • \(selection.webDomainTokens.count) websites selected"
    }

    private func questionTypeDescription(_ type: StudyQuestionType) -> String {
        switch type {
        case .multipleChoice: "Four answer options, one correct answer"
        case .fillInTheBlank: "Complete a missing word or phrase"
        case .shortAnswer: "Write a short response in your own words"
        }
    }

    private func settingStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String
    ) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) \(suffix)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 66, alignment: .trailing)
            }
            .labelsHidden()
            Text("\(value.wrappedValue) \(suffix)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(QuizLockTheme.secondaryText)
                .frame(minWidth: 58, alignment: .trailing)
        }
    }

    private func updateSettings(_ change: (StudyPreferences) -> Void) {
        guard let settings else { return }
        change(settings)
        do {
            try modelContext.save()
        } catch {
            feedbackMessage = error.localizedDescription
            showFeedback = true
        }
    }

    @MainActor
    private func requestAuthorization() async {
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        do {
            try await screenTimeManager.requestAuthorization()
        } catch {
            feedbackMessage = error.localizedDescription
            showFeedback = true
        }
    }
}
