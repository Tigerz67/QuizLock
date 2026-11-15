import SwiftUI

struct AppRootView: View {
    @AppStorage("quizLock.didFinishOnboarding") private var didFinishOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var bootstrapError: String?

    var body: some View {
        Group {
            if didFinishOnboarding {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .quizLockScreenBackground()
        .task {
            bootstrapLocalData()
            screenTimeManager.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                screenTimeManager.refresh()
            }
        }
        .alert("QUIZLOCK setup", isPresented: Binding(
            get: { bootstrapError != nil },
            set: { if !$0 { bootstrapError = nil } }
        )) {
            Button("OK", role: .cancel) { bootstrapError = nil }
        } message: {
            Text(bootstrapError ?? "")
        }
    }

    private func bootstrapLocalData() {
        do {
            let preferences = try modelContext.fetch(FetchDescriptor<StudyPreferences>())
            if preferences.isEmpty {
                modelContext.insert(StudyPreferences())
            }

            let banks = try modelContext.fetch(FetchDescriptor<StudyTimeBank>())
            if banks.isEmpty {
                modelContext.insert(StudyTimeBank())
            }
            try modelContext.save()
        } catch {
            bootstrapError = "QUIZLOCK could not initialize local storage: \(error.localizedDescription)"
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                StudyNotesView()
            }
            .tabItem {
                Label("Study", systemImage: "book.closed.fill")
            }

            NavigationStack {
                AppBlockerView()
            }
            .tabItem {
                Label("Blocker", systemImage: "lock.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(QuizLockTheme.accent)
    }
}
