import SwiftData
import SwiftUI

@main
struct QUIZLOCKApp: App {
    @StateObject private var screenTimeManager: ScreenTimeManager
    private let modelContainer: ModelContainer

    init() {
        _screenTimeManager = StateObject(wrappedValue: ScreenTimeManager())

        let schema = Schema([
            StudyNote.self,
            StudyQuestionSet.self,
            StudyPreferences.self,
            StudyTimeBank.self
        ])
        let configuration = ModelConfiguration(
            "QUIZLOCK",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("QUIZLOCK could not create its local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(screenTimeManager)
                .modelContainer(modelContainer)
        }
    }
}
