import Foundation
import SwiftData

// MARK: - Question configuration

enum StudyQuestionType: String, Codable, CaseIterable, Identifiable, Hashable {
    case multipleChoice
    case fillInTheBlank
    case shortAnswer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .fillInTheBlank: "Fill in the blank"
        case .shortAnswer: "Short answer"
        }
    }
}

enum StudyGradeLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case grade1, grade2, grade3, grade4, grade5, grade6
    case grade7, grade8, grade9, grade10, grade11, grade12
    case universityCollege

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grade1: "Grade 1"
        case .grade2: "Grade 2"
        case .grade3: "Grade 3"
        case .grade4: "Grade 4"
        case .grade5: "Grade 5"
        case .grade6: "Grade 6"
        case .grade7: "Grade 7"
        case .grade8: "Grade 8"
        case .grade9: "Grade 9"
        case .grade10: "Grade 10"
        case .grade11: "Grade 11"
        case .grade12: "Grade 12"
        case .universityCollege: "University / College"
        }
    }
}

enum QuizPenaltyPolicy: String, Codable, CaseIterable, Identifiable, Hashable {
    case cooldown60Seconds
    case deductOneMinute
    case cooldownAndDeduct
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cooldown60Seconds: "Lock this quiz for 60 seconds"
        case .deductOneMinute: "Deduct 1 minute from the bank"
        case .cooldownAndDeduct: "60-second lock + deduct 1 minute"
        case .none: "No penalty"
        }
    }

    var appliesCooldown: Bool {
        self == .cooldown60Seconds || self == .cooldownAndDeduct
    }

    var deductsMinute: Bool {
        self == .deductOneMinute || self == .cooldownAndDeduct
    }
}

// MARK: - Generated question value type

struct StudyQuestion: Codable, Identifiable, Hashable {
    var id: UUID
    var prompt: String
    var type: StudyQuestionType
    var options: [String]
    var correctIndex: Int?
    var acceptedAnswers: [String]
    var explanation: String

    init(
        id: UUID = UUID(),
        prompt: String,
        type: StudyQuestionType,
        options: [String] = [],
        correctIndex: Int? = nil,
        acceptedAnswers: [String] = [],
        explanation: String = ""
    ) {
        self.id = id
        self.prompt = prompt
        self.type = type
        self.options = options
        self.correctIndex = correctIndex
        self.acceptedAnswers = acceptedAnswers
        self.explanation = explanation
    }

    /// Validates the shape before a generated question is saved.
    /// Short-answer grading can later be upgraded to a local-model evaluator;
    /// acceptedAnswers remains the deterministic fallback.
    func validateStructure() throws {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyModelError.emptyQuestionPrompt
        }

        switch type {
        case .multipleChoice:
            let normalizedOptions = options.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            guard options.count == 4,
                  options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  Set(normalizedOptions).count == 4,
                  let correctIndex,
                  (0..<4).contains(correctIndex) else {
                throw StudyModelError.invalidMultipleChoiceQuestion
            }
        case .fillInTheBlank, .shortAnswer:
            guard !acceptedAnswers.isEmpty else {
                throw StudyModelError.missingAcceptedAnswer
            }
        }
    }
}

enum StudyModelError: LocalizedError {
    case emptyQuestionPrompt
    case invalidMultipleChoiceQuestion
    case missingAcceptedAnswer

    var errorDescription: String? {
        switch self {
        case .emptyQuestionPrompt:
            "A question must include its prompt."
        case .invalidMultipleChoiceQuestion:
            "A multiple-choice question must have four options and a valid correct answer index."
        case .missingAcceptedAnswer:
            "A fill-in-the-blank or short-answer question must include at least one accepted answer."
        }
    }
}

// MARK: - SwiftData models

@Model
final class StudyNote {
    @Attribute(.unique) var id: UUID
    var title: String
    var bodyText: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StudyQuestionSet.note)
    var questionSets: [StudyQuestionSet]

    init(
        id: UUID = UUID(),
        title: String,
        bodyText: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.questionSets = []
    }
}

@Model
final class StudyQuestionSet {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var gradeLevelRawValue: String
    var questionTypesRawValues: String
    var questionsData: Data
    /// Question IDs that have already earned time. Stored separately from the
    /// question payload so closing/reopening a quiz cannot award the same item twice.
    var rewardedQuestionIDsData: Data
    var penaltyPolicyRawValue: String
    var wrongAnswerCount: Int
    var cooldownEndsAt: Date?

    var note: StudyNote?

    init(
        id: UUID = UUID(),
        title: String,
        questions: [StudyQuestion],
        gradeLevel: StudyGradeLevel,
        questionTypes: Set<StudyQuestionType>,
        penaltyPolicy: QuizPenaltyPolicy = .cooldown60Seconds,
        createdAt: Date = .now,
        note: StudyNote? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.gradeLevelRawValue = gradeLevel.rawValue
        self.questionTypesRawValues = questionTypes.map(\.rawValue).sorted().joined(separator: ",")
        self.questionsData = (try? JSONEncoder().encode(questions)) ?? Data()
        self.rewardedQuestionIDsData = (try? JSONEncoder().encode([UUID]())) ?? Data()
        self.penaltyPolicyRawValue = penaltyPolicy.rawValue
        self.wrongAnswerCount = 0
        self.cooldownEndsAt = nil
        self.note = note
    }

    var questions: [StudyQuestion] {
        get { (try? JSONDecoder().decode([StudyQuestion].self, from: questionsData)) ?? [] }
        set { questionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var rewardedQuestionIDs: Set<UUID> {
        get { Set((try? JSONDecoder().decode([UUID].self, from: rewardedQuestionIDsData)) ?? []) }
        set { rewardedQuestionIDsData = (try? JSONEncoder().encode(Array(newValue))) ?? Data() }
    }

    func hasRewardedQuestion(_ questionID: UUID) -> Bool {
        rewardedQuestionIDs.contains(questionID)
    }

    /// Returns true only once per question, preventing repeat rewards after a relaunch.
    @discardableResult
    func markQuestionRewarded(_ questionID: UUID) -> Bool {
        var rewarded = rewardedQuestionIDs
        guard !rewarded.contains(questionID) else { return false }
        rewarded.insert(questionID)
        rewardedQuestionIDs = rewarded
        return true
    }

    var gradeLevel: StudyGradeLevel {
        get { StudyGradeLevel(rawValue: gradeLevelRawValue) ?? .grade9 }
        set { gradeLevelRawValue = newValue.rawValue }
    }

    var questionTypes: Set<StudyQuestionType> {
        get {
            Set(questionTypesRawValues
                .split(separator: ",")
                .compactMap { StudyQuestionType(rawValue: String($0)) })
        }
        set { questionTypesRawValues = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    var penaltyPolicy: QuizPenaltyPolicy {
        get { QuizPenaltyPolicy(rawValue: penaltyPolicyRawValue) ?? .cooldown60Seconds }
        set { penaltyPolicyRawValue = newValue.rawValue }
    }

    var cooldownRemainingSeconds: Int {
        guard let cooldownEndsAt, cooldownEndsAt > .now else { return 0 }
        return max(0, Int(ceil(cooldownEndsAt.timeIntervalSinceNow)))
    }

    var isInCooldown: Bool { cooldownRemainingSeconds > 0 }
}

@Model
final class StudyPreferences {
    @Attribute(.unique) var id: String
    var gradeLevelRawValue: String
    var questionTypesRawValues: String
    var penaltyPolicyRawValue: String
    var questionsPerSet: Int
    var minutesPerCorrectAnswer: Int
    var defaultUnlockMinutes: Int
    var cooldownSeconds: Int

    init(
        id: String = "primary",
        gradeLevel: StudyGradeLevel = .grade9,
        questionTypes: Set<StudyQuestionType> = [.multipleChoice],
        penaltyPolicy: QuizPenaltyPolicy = .cooldown60Seconds,
        questionsPerSet: Int = 5,
        minutesPerCorrectAnswer: Int = 3,
        defaultUnlockMinutes: Int = 10,
        cooldownSeconds: Int = 60
    ) {
        self.id = id
        self.gradeLevelRawValue = gradeLevel.rawValue
        self.questionTypesRawValues = questionTypes.map(\.rawValue).sorted().joined(separator: ",")
        self.penaltyPolicyRawValue = penaltyPolicy.rawValue
        self.questionsPerSet = max(1, questionsPerSet)
        self.minutesPerCorrectAnswer = max(1, minutesPerCorrectAnswer)
        self.defaultUnlockMinutes = max(1, defaultUnlockMinutes)
        self.cooldownSeconds = max(1, cooldownSeconds)
    }

    var gradeLevel: StudyGradeLevel {
        get { StudyGradeLevel(rawValue: gradeLevelRawValue) ?? .grade9 }
        set { gradeLevelRawValue = newValue.rawValue }
    }

    var selectedQuestionTypes: Set<StudyQuestionType> {
        get {
            Set(questionTypesRawValues
                .split(separator: ",")
                .compactMap { StudyQuestionType(rawValue: String($0)) })
        }
        set { questionTypesRawValues = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    var penaltyPolicy: QuizPenaltyPolicy {
        get { QuizPenaltyPolicy(rawValue: penaltyPolicyRawValue) ?? .cooldown60Seconds }
        set { penaltyPolicyRawValue = newValue.rawValue }
    }
}

@Model
final class StudyTimeBank {
    @Attribute(.unique) var id: String
    var availableMinutes: Int
    var totalMinutesEarned: Int
    var totalMinutesSpent: Int
    var totalPenaltyMinutes: Int
    var updatedAt: Date

    init(
        id: String = "primary",
        availableMinutes: Int = 0,
        totalMinutesEarned: Int = 0,
        totalMinutesSpent: Int = 0,
        totalPenaltyMinutes: Int = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.availableMinutes = max(0, availableMinutes)
        self.totalMinutesEarned = max(0, totalMinutesEarned)
        self.totalMinutesSpent = max(0, totalMinutesSpent)
        self.totalPenaltyMinutes = max(0, totalPenaltyMinutes)
        self.updatedAt = updatedAt
    }

    func awardCorrectAnswer(minutes: Int, at date: Date = .now) {
        let award = max(0, minutes)
        availableMinutes += award
        totalMinutesEarned += award
        updatedAt = date
    }

    /// Applies the quiz's selected wrong-answer penalty.
    /// A cooldown is stored on that quiz, so closing the app does not bypass it.
    func registerIncorrectAnswer(
        in questionSet: StudyQuestionSet,
        policy: QuizPenaltyPolicy,
        cooldownSeconds: Int = 60,
        at date: Date = .now
    ) {
        questionSet.wrongAnswerCount += 1

        if policy.appliesCooldown {
            questionSet.cooldownEndsAt = date.addingTimeInterval(TimeInterval(max(1, cooldownSeconds)))
        }

        if policy.deductsMinute, availableMinutes > 0 {
            availableMinutes -= 1
            totalPenaltyMinutes += 1
        }

        updatedAt = date
    }
}
