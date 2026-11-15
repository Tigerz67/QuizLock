import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StudyNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \StudyQuestionSet.createdAt, order: .reverse) private var questionSets: [StudyQuestionSet]
    @Query private var preferences: [StudyPreferences]
    @Query private var banks: [StudyTimeBank]

    @StateObject private var aiService = LocalQuestionAIService()
    @State private var noteTitle = ""
    @State private var noteText = ""
    @State private var selectedNote: StudyNote?
    @State private var selectedQuestionSet: StudyQuestionSet?
    @State private var isFileImporterPresented = false
    @State private var isQuizPresented = false
    @State private var isGenerating = false
    @State private var alertMessage: String?
    @State private var isAlertPresented = false

    private var settings: StudyPreferences? {
        preferences.first(where: { $0.id == "primary" }) ?? preferences.first
    }
    private var timeBank: StudyTimeBank? {
        banks.first(where: { $0.id == "primary" }) ?? banks.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                modelStatusSection
                noteComposer
                savedNotesSection
                questionSetsSection
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .quizLockScreenBackground()
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.large)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.plainText, .pdf, .rtf],
            allowsMultipleSelection: false,
            onCompletion: importNotesFile
        )
        .sheet(isPresented: $isQuizPresented) {
            if let selectedQuestionSet, let timeBank {
                NavigationStack {
                    QuizPlayerView(
                        questionSet: selectedQuestionSet,
                        timeBank: timeBank,
                        rewardMinutes: settings?.minutesPerCorrectAnswer ?? 3,
                        cooldownSeconds: settings?.cooldownSeconds ?? 60
                    )
                }
            }
        }
        .alert("QUIZLOCK", isPresented: $isAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            await prepareLocalModel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Turn notes into focus time")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("Add what you're studying. QUIZLOCK builds a quiz from it.")
                        .font(.subheadline)
                        .foregroundStyle(QuizLockTheme.secondaryText)
                }
                Spacer(minLength: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(QuizLockTheme.accent)
            }
        }
        .padding(.top, 6)
    }

    private var noteComposer: some View {
        QuizLockCard {
            HStack {
                SectionHeading(title: "Your study material", subtitle: "Paste text or import a TXT, RTF, or PDF file.")
                Spacer()
                Button {
                    isFileImporterPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import study notes")
            }

            TextField("Note title (e.g. Biology Unit 2)", text: $noteTitle)
                .textInputAutocapitalization(.sentences)
                .padding(13)
                .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 13))

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Paste your notes, definitions, study guide, or class material here…")
                        .font(.body)
                        .foregroundStyle(QuizLockTheme.secondaryText.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                }
                TextEditor(text: $noteText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 170)
                    .padding(4)
                    .foregroundStyle(.white)
            }
            .background(QuizLockTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(QuizLockTheme.border, lineWidth: 1)
            }

            HStack {
                Text("\(noteText.count) characters")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(QuizLockTheme.secondaryText)
                Spacer()
                Button {
                    saveNote()
                } label: {
                    Label("Save notes", systemImage: "square.and.arrow.down.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(QuizLockTheme.elevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
    }

    private var savedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Saved notes", subtitle: "Select a note to generate a quiz.")

            if notes.isEmpty {
                emptyState(
                    icon: "doc.text",
                    title: "No notes yet",
                    detail: "Save your first set of study notes above."
                )
            } else {
                ForEach(notes) { note in
                    Button {
                        selectedNote = note
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(QuizLockTheme.accent.opacity(0.15))
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundStyle(QuizLockTheme.accent)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text(note.bodyText.replacingOccurrences(of: "\n", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(QuizLockTheme.secondaryText)
                                    .lineLimit(1)
                                Text(note.updatedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(QuizLockTheme.secondaryText.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: selectedNote?.id == note.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedNote?.id == note.id ? QuizLockTheme.mint : QuizLockTheme.secondaryText)
                        }
                        .padding(13)
                        .background(
                            selectedNote?.id == note.id ? QuizLockTheme.accent.opacity(0.15) : QuizLockTheme.surface,
                            in: RoundedRectangle(cornerRadius: 17)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 17)
                                .stroke(selectedNote?.id == note.id ? QuizLockTheme.accent.opacity(0.5) : QuizLockTheme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let selectedNote {
                    QuizLockCard {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("READY TO GENERATE")
                                .font(.caption2.weight(.bold))
                                .tracking(1)
                                .foregroundStyle(QuizLockTheme.mint)
                            Text(selectedNote.title)
                                .font(.headline)
                            Text("\(settings?.gradeLevel.title ?? StudyGradeLevel.grade9.title) • \(settings?.questionsPerSet ?? 5) questions • \(selectedTypeSummary)")
                                .font(.caption)
                                .foregroundStyle(QuizLockTheme.secondaryText)
                        }

                        PrimaryActionButton(
                            title: "Generate quiz",
                            systemImage: "sparkles",
                            isLoading: isGenerating,
                            isDisabled: (settings?.selectedQuestionTypes.isEmpty ?? true)
                                || aiService.isLoadingModel
                                || aiService.isGenerating
                        ) {
                            Task { await generateQuiz(for: selectedNote) }
                        }

                        Text("First use downloads the model. After that, questions are generated on-device without sending your notes to a server.")
                            .font(.caption2)
                            .foregroundStyle(QuizLockTheme.secondaryText)
                    }
                }
            }
        }
    }

    private var questionSetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Your quizzes", subtitle: "Saved question sets are available offline.")

            if questionSets.isEmpty {
                emptyState(
                    icon: "checklist",
                    title: "No quizzes yet",
                    detail: "Choose a saved note and generate your first quiz."
                )
            } else {
                ForEach(questionSets) { questionSet in
                    QuizLockCard(padding: 15) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(questionSet.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(questionSet.gradeLevel.title) • \(questionSet.questions.count) questions")
                                    .font(.caption)
                                    .foregroundStyle(QuizLockTheme.secondaryText)
                                Text(questionSet.createdAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(QuizLockTheme.secondaryText.opacity(0.75))
                            }
                            Spacer()
                            Button {
                                selectedQuestionSet = questionSet
                                isQuizPresented = true
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 42, height: 42)
                                    .background(QuizLockTheme.accent, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(questionSet.title)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var modelStatusSection: some View {
        if aiService.isLoadingModel || aiService.isGenerating || aiService.isModelReady {
            QuizLockCard {
                HStack(spacing: 10) {
                    Image(systemName: aiService.isModelReady ? "checkmark.circle.fill" : "cpu.fill")
                        .foregroundStyle(aiService.isModelReady ? QuizLockTheme.mint : QuizLockTheme.accent)
                    Text(aiService.statusMessage)
                        .font(.caption)
                        .foregroundStyle(QuizLockTheme.secondaryText)
                    Spacer(minLength: 0)
                }
                if aiService.isLoadingModel {
                    ProgressView(value: aiService.downloadProgress)
                        .tint(QuizLockTheme.accent)
                } else if aiService.isGenerating {
                    ProgressView().tint(QuizLockTheme.accent)
                }
            }
        }
    }

    private var selectedTypeSummary: String {
        let selected = settings?.selectedQuestionTypes ?? [.multipleChoice]
        return selected.map(\.title).sorted().joined(separator: ", ")
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(QuizLockTheme.secondaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(QuizLockTheme.secondaryText)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuizLockTheme.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func saveNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = StudyNote(
            title: title.isEmpty ? "Untitled study notes" : title,
            bodyText: trimmed
        )
        modelContext.insert(note)

        do {
            try modelContext.save()
            selectedNote = note
            noteTitle = ""
            noteText = ""
        } catch {
            presentError("Could not save your notes: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func prepareLocalModel() async {
        guard !aiService.isModelReady && !aiService.isLoadingModel else { return }
        do {
            try await aiService.loadModelIfNeeded()
        } catch {
            presentError("The offline AI model could not be prepared. You can still save notes and retry when you have a connection.\n\n\(error.localizedDescription)")
        }
    }

    @MainActor
    private func generateQuiz(for note: StudyNote) async {
        guard let settings else {
            presentError("Your study preferences have not been initialized.")
            return
        }
        guard !settings.selectedQuestionTypes.isEmpty else {
            presentError("Choose at least one question type in Settings.")
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let questions = try await aiService.generateQuestions(
                from: note.bodyText,
                noteTitle: note.title,
                gradeLevel: settings.gradeLevel,
                questionTypes: settings.selectedQuestionTypes,
                questionCount: settings.questionsPerSet
            )

            let questionSet = StudyQuestionSet(
                title: note.title + " Quiz",
                questions: questions,
                gradeLevel: settings.gradeLevel,
                questionTypes: settings.selectedQuestionTypes,
                penaltyPolicy: settings.penaltyPolicy,
                note: note
            )
            modelContext.insert(questionSet)
            note.updatedAt = .now
            try modelContext.save()
            selectedQuestionSet = questionSet
            isQuizPresented = true
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func importNotesFile(_ result: Result<[URL], Error>) {
        do {
            guard let fileURL = try result.get().first else { return }
            let didAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { fileURL.stopAccessingSecurityScopedResource() }
            }

            let importedText: String
            switch fileURL.pathExtension.lowercased() {
            case "pdf":
                guard let document = PDFDocument(url: fileURL),
                      let extractedText = document.string,
                      !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NotesImportError.couldNotReadPDF
                }
                importedText = extractedText
            case "rtf":
                let data = try Data(contentsOf: fileURL)
                let attributed = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                importedText = attributed.string
            default:
                importedText = try String(contentsOf: fileURL, encoding: .utf8)
            }

            noteTitle = fileURL.deletingPathExtension().lastPathComponent
            noteText = importedText
        } catch {
            presentError("Could not import that file: \(error.localizedDescription)")
        }
    }

    private func presentError(_ message: String) {
        alertMessage = message
        isAlertPresented = true
    }
}

private enum NotesImportError: LocalizedError {
    case couldNotReadPDF

    var errorDescription: String? {
        switch self {
        case .couldNotReadPDF:
            return "The PDF did not contain readable text. Scanned-image PDFs need OCR before they can be used as notes."
        }
    }
}

struct QuizPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let questionSet: StudyQuestionSet
    let timeBank: StudyTimeBank
    let rewardMinutes: Int
    let cooldownSeconds: Int

    @State private var questionIndex = 0
    @State private var selectedOption: Int?
    @State private var answerText = ""
    @State private var feedback: String?
    @State private var didAnswerCorrectly = false
    @State private var isComplete = false
    @State private var saveError: String?
    @State private var showSaveError = false

    private var questions: [StudyQuestion] { questionSet.questions }
    private var currentQuestion: StudyQuestion? {
        guard questions.indices.contains(questionIndex) else { return nil }
        return questions[questionIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isComplete {
                    completionState
                } else if let question = currentQuestion {
                    quizHeader
                    questionCard(question)
                    answerArea(question)
                    feedbackArea
                    actionArea
                } else {
                    completionState
                }
            }
            .padding(20)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .quizLockScreenBackground()
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
                    .foregroundStyle(QuizLockTheme.secondaryText)
            }
        }
        .alert("Could not save quiz progress", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            moveToNextUnrewardedQuestion()
        }
    }

    private var quizHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(questionSet.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            HStack {
                Text("QUESTION \(questionIndex + 1) OF \(questions.count)")
                Spacer()
                Text(questionSet.gradeLevel.title)
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(QuizLockTheme.secondaryText)
            ProgressView(value: Double(questionIndex + 1), total: Double(max(questions.count, 1)))
                .tint(QuizLockTheme.accent)
        }
    }

    private func questionCard(_ question: StudyQuestion) -> some View {
        QuizLockCard {
            Text(question.type.title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(QuizLockTheme.accent)
            Text(question.prompt)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func answerArea(_ question: StudyQuestion) -> some View {
        switch question.type {
        case .multipleChoice:
            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        selectedOption = index
                        feedback = nil
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(UnicodeScalar(65 + index)!))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(selectedOption == index ? .white : QuizLockTheme.secondaryText)
                                .frame(width: 30, height: 30)
                                .background(
                                    selectedOption == index ? QuizLockTheme.accent : QuizLockTheme.elevated,
                                    in: Circle()
                                )
                            Text(option)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selectedOption == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(QuizLockTheme.accent)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedOption == index ? QuizLockTheme.accent.opacity(0.13) : QuizLockTheme.surface,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(selectedOption == index ? QuizLockTheme.accent.opacity(0.65) : QuizLockTheme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(didAnswerCorrectly || questionSet.cooldownRemainingSeconds > 0)
                }
            }
        case .fillInTheBlank, .shortAnswer:
            VStack(alignment: .leading, spacing: 9) {
                Text(question.type == .fillInTheBlank ? "YOUR ANSWER" : "WRITE A SHORT ANSWER")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(QuizLockTheme.secondaryText)
                TextField("Type your answer…", text: $answerText, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.sentences)
                    .padding(14)
                    .background(QuizLockTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .disabled(didAnswerCorrectly || questionSet.cooldownRemainingSeconds > 0)
                    .onChange(of: answerText) { _, _ in feedback = nil }
            }
        }
    }

    @ViewBuilder
    private var feedbackArea: some View {
        if let feedback {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: didAnswerCorrectly ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(didAnswerCorrectly ? QuizLockTheme.mint : QuizLockTheme.warning)
                Text(feedback)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (didAnswerCorrectly ? QuizLockTheme.mint : QuizLockTheme.warning).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 15)
            )
        }
    }

    private var actionArea: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let cooldown = questionSet.cooldownRemainingSeconds

            VStack(spacing: 12) {
                if cooldown > 0 {
                    Label("Quiz locked for \(cooldown) seconds", systemImage: "timer")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(QuizLockTheme.warning)
                }

                if didAnswerCorrectly {
                    PrimaryActionButton(
                        title: questionIndex == questions.count - 1 ? "Finish quiz" : "Next question",
                        systemImage: "arrow.right"
                    ) {
                        advanceQuestion()
                    }
                } else {
                    PrimaryActionButton(
                        title: "Check answer",
                        systemImage: "checkmark",
                        isDisabled: cooldown > 0 || !hasAnswer
                    ) {
                        submitAnswer()
                    }
                }
            }
        }
    }

    private var completionState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 35)
            ZStack {
                Circle().fill(QuizLockTheme.mint.opacity(0.14)).frame(width: 100, height: 100)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(QuizLockTheme.mint)
            }
            Text("Quiz complete")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Nice work. Your correct answers have been added to your Screen Time Bank.")
                .font(.subheadline)
                .foregroundStyle(QuizLockTheme.secondaryText)
                .multilineTextAlignment(.center)
            QuizLockCard {
                HStack {
                    Text("Available minutes")
                    Spacer()
                    Text("\(timeBank.availableMinutes) min")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(QuizLockTheme.mint)
                }
            }
            PrimaryActionButton(title: "Done", systemImage: "checkmark") {
                dismiss()
            }
            Spacer(minLength: 30)
        }
    }

    private var hasAnswer: Bool {
        guard let question = currentQuestion else { return false }
        switch question.type {
        case .multipleChoice:
            return selectedOption != nil
        case .fillInTheBlank, .shortAnswer:
            return !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submitAnswer() {
        guard let question = currentQuestion,
              !didAnswerCorrectly,
              questionSet.cooldownRemainingSeconds == 0 else { return }

        let isCorrect: Bool
        switch question.type {
        case .multipleChoice:
            isCorrect = selectedOption == question.correctIndex
        case .fillInTheBlank, .shortAnswer:
            let normalized = Self.normalize(answerText)
            isCorrect = question.acceptedAnswers.contains { Self.normalize($0) == normalized }
        }

        if isCorrect {
            if questionSet.markQuestionRewarded(question.id) {
                timeBank.awardCorrectAnswer(minutes: rewardMinutes)
                feedback = "Correct! +\(rewardMinutes) minutes added to your bank.\n\(question.explanation)"
            } else {
                feedback = "You've already earned the reward for this question.\n\(question.explanation)"
            }
            didAnswerCorrectly = true
        } else {
            timeBank.registerIncorrectAnswer(
                in: questionSet,
                policy: questionSet.penaltyPolicy,
                cooldownSeconds: cooldownSeconds
            )
            feedback = incorrectFeedback(for: questionSet.penaltyPolicy)
            if questionSet.penaltyPolicy.appliesCooldown {
                selectedOption = nil
                answerText = ""
            }
        }

        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }

    private func incorrectFeedback(for policy: QuizPenaltyPolicy) -> String {
        switch policy {
        case .cooldown60Seconds:
            return "Not quite. This quiz is locked for \(cooldownSeconds) seconds. Review your notes and try again."
        case .deductOneMinute:
            return "Not quite. One minute has been deducted from your bank. Try again."
        case .cooldownAndDeduct:
            return "Not quite. One minute was deducted and this quiz is locked for \(cooldownSeconds) seconds."
        case .none:
            return "Not quite. Take another look at your notes and try again."
        }
    }

    private func advanceQuestion() {
        questionIndex += 1
        selectedOption = nil
        answerText = ""
        feedback = nil
        didAnswerCorrectly = false
        moveToNextUnrewardedQuestion()
    }

    private func moveToNextUnrewardedQuestion() {
        while questionIndex < questions.count,
              questionSet.hasRewardedQuestion(questions[questionIndex].id) {
            questionIndex += 1
        }
        if questionIndex >= questions.count {
            isComplete = true
        }
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
