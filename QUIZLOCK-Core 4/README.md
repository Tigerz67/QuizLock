# QUIZLOCK — iOS 17+ SwiftUI project (Phase 1 + Phase 2)

QUIZLOCK turns a student's own notes into quizzes, awards Screen Time minutes for correct answers, and uses Apple's Screen Time frameworks to shield selected apps while focus mode is enabled.

## What is included

### Phase 1 — data and Screen Time

- SwiftData models for notes, question sets, grade/question preferences, and the earned-time bank.
- `ScreenTimeManager` for individual Family Controls authorization, app selection storage, shielding, temporary unlocks, bank deductions, foreground countdown, and restoration.
- `DeviceActivityMonitor` extension for background shield restoration.
- Shared App Group configuration for the app and extension.
- A persisted set of rewarded question IDs. A correct question can award time only once, even if the student closes and reopens the quiz.

### Phase 2 — local AI and SwiftUI

- `LocalQuestionAIService.swift` loads `mlx-community/Llama-3.2-1B-Instruct-4bit` using the current MLX Swift LM 3.x API.
- The Hugging Face snapshot downloader downloads the model on first generation and reuses its local cache on later generations.
- Questions are generated locally from the selected note and validated before they are saved to SwiftData.
- Grade levels: Grade 1 through Grade 12 and University / College.
- Question types: multiple choice, fill in the blank, and short answer.
- Configurable number of questions, minutes per correct answer, unlock duration, and wrong-answer penalty.
- File import for text, RTF, and text-based PDF files. Scanned PDF images are not OCR'd.
- Onboarding / Screen Time permissions, Study, App Blocker / Time Bank, and Settings views.

## Requirements

- A Mac with a current Xcode release and iOS 17+ SDK.
- A physical iPhone or iPad with Apple silicon (A-series device) for MLX inference and realistic Family Controls testing.
- Apple Developer signing for on-device installation.
- Family Controls development entitlement for the app and Screen Time extension; distribution entitlement approval is a separate Apple process.
- Network access on the first model download. The selected 4-bit model's Hugging Face page lists approximately 695 MB of model weights (plus tokenizer/configuration files). After it is cached, question generation runs on-device without sending notes to a server.

## Create the Xcode project

### Option A — generate the project from this folder

This ZIP includes `project.yml` for XcodeGen. On a Mac:

1. Install Xcode and open it once so its command-line tools are available.
2. Install XcodeGen if needed: `brew install xcodegen`.
3. Extract this ZIP and open Terminal in the `QUIZLOCK-Core` folder.
4. Run `xcodegen generate`.
5. Open the generated `QUIZLOCK.xcodeproj` in Xcode.
6. Select your Apple Developer Team for both targets and replace the example bundle IDs / App Group ID described below.
7. Build and run on a physical iPhone or iPad.

XcodeGen is a convenience; it does not sign the app, grant Apple's entitlements, or create an IPA by itself.

### Option B — create targets manually

1. In Xcode, choose **File → New → Project → iOS → App**.
2. Product Name: `QUIZLOCK`; Interface: **SwiftUI**; Language: **Swift**; minimum deployment: **iOS 17.0**.
3. Add a **Device Activity Monitor Extension** target named `QUIZLOCKMonitor`.
4. Add every file under `QuizLock/` to the main app target.
5. Add `QuizLockMonitor/QuizLockMonitorExtension.swift` and `QuizLock/Shared/QuizLockShared.swift` to the extension target.
6. Add the MLX Swift Package dependencies below to the main app target only.
7. Add the required Apple capabilities and set the entitlements / extension Info.plist paths shown below.

## MLX Swift package dependencies

The included `project.yml` already declares these dependencies and target products:

- `https://github.com/ml-explore/mlx-swift-lm` — `minorVersion: 3.32.3` (XcodeGen up-to-next-minor constraint, matching MLX Swift LM guidance)
  - `MLXLLM`
  - `MLXLMCommon`
  - `MLXHuggingFace`
- `https://github.com/huggingface/swift-huggingface` — from `0.9.0`
  - `HuggingFace`
- `https://github.com/huggingface/swift-transformers` — from `1.3.0`
  - `Tokenizers`

The MLX Swift LM code uses the v3 integration macros `#hubDownloader()` and `#huggingFaceTokenizerLoader()` and `ChatSession.respond(to:)`. Do not mix it with older 2.x API examples.

## Required capabilities and identifiers

Both the app and monitor extension need:

- **Family Controls** capability.
- **App Groups** capability.
- The same App Group identifier.

The example identifiers in this package are placeholders. Before signing, replace `com.yourcompany` with your own reverse-DNS identifier consistently in:

- `QuizLock/Shared/QuizLockShared.swift`
- `Configuration/QUIZLOCK.entitlements`
- `Configuration/QUIZLOCKMonitor.entitlements`
- `project.yml` bundle identifiers

The default example App Group is `group.com.yourcompany.QUIZLOCK`.

Entitlements files are already included:

- App: `Configuration/QUIZLOCK.entitlements`
- Extension: `Configuration/QUIZLOCKMonitor.entitlements`

For Xcode's extension target, use `Configuration/QUIZLOCKMonitor-Info.plist` as its Info.plist. It declares the `com.apple.deviceactivity.monitor-extension` extension point.

### Personal device testing vs. App Store distribution

For personal-device development, the user authorizes the app through `AuthorizationCenter.shared.requestAuthorization(for: .individual)`. Develop and test on a physical device. Simulator behavior is not a substitute for real app selection and shield testing.

For App Store distribution, the Apple Developer Account Holder must request Apple's Family Controls distribution entitlement for every target that uses the Family Controls APIs, including the relevant Screen Time extension. Development signing is not the same as distribution approval.

## How the local AI works

1. The student saves or imports a note.
2. The app loads `mlx-community/Llama-3.2-1B-Instruct-4bit` through MLX Swift LM. The first generation downloads the model snapshot from Hugging Face into the app's cache; later runs reuse it.
3. The app sends the note text directly to the model running in the app process. The prompt constrains level, selected question formats, source-grounded answers, and JSON output.
4. `LocalQuestionAIService` extracts and decodes the JSON, validates the number and structure of the questions, then returns typed `StudyQuestion` values.
5. The app saves the generated questions in SwiftData. Quiz attempts and earned minutes remain local.

The model repository lists a 1B-parameter, 4-bit MLX model with approximately 695 MB of weights. Check the model's and Meta's Llama 3.2 license terms before redistributing the model or an app bundle containing it. This project downloads the model at runtime; it does not include those weights in this ZIP.

## Question grading and reward safeguards

- Multiple-choice grading checks the selected option index.
- Fill-in-the-blank and short-answer grading compares the response to the model-provided `acceptedAnswers` after trimming, case/diacritic folding, and punctuation normalization. This is deterministic and local; it does not ask a second model call to grade answers. To reduce false rewards, the model is instructed to supply concise accepted-answer variants. A production version should let students review or edit generated answers before a quiz.
- An incorrect answer applies the selected per-quiz policy: cooldown, one-minute bank deduction, both, or no penalty.
- Correct question IDs are persisted before the reward is saved. Reopening a quiz skips previously rewarded questions, preventing the same question from repeatedly granting minutes.

## Screen Time and unlock timing limitations

Apple's Screen Time frameworks own the shields. QUIZLOCK can shield only the apps, categories, and websites selected through Apple's `FamilyActivityPicker` after authorization. It cannot silently enumerate all installed apps or force a user to grant authorization.

The app runs a foreground countdown while it is active and uses the Device Activity extension to restore shielding at the scheduled interval end. iOS controls when extension callbacks are delivered, particularly while a device is idle, so treat background restoration timing as something that must be tested on real devices and supported iOS versions. Do not treat this mechanism as a tamper-proof parental-control boundary.

## SwiftData schema note

The project is still in active development. Phase 2 adds `rewardedQuestionIDsData` to `StudyQuestionSet` so each question reward is issued only once. If you installed a previous Phase 1 build with an older schema and reuse that app's database, add a SwiftData migration plan before shipping. For a clean development test, delete the previous app from the device to reset its local database before installing the updated schema.

## Build-fix review

- `RootTabView.swift` imports `SwiftData`, which is required for `FetchDescriptor`, `ModelContext`, and SwiftData fetch operations in that file.
- `StudyModels.swift` already imports `SwiftData`; the four persisted classes are declared with `@Model`, which generates `PersistentModel` conformance. No model declarations were removed or replaced.
- `QUIZLOCKApp.swift` builds a `Schema` containing all four models, creates a persistent `ModelConfiguration`, initializes the `ModelContainer`, and injects it into the SwiftUI hierarchy.
- The `ScreenTimeManager` countdown now binds the expiration date to a value that is actually used by the task, eliminating the unused-binding warning.
- The app and extension deployment targets remain iOS 17.0. MLX Swift LM 3.32.3 declares iOS 17 support; this establishes package deployment-target compatibility, not a guarantee of inference on every iOS 17 device/OS point release.
- The GitHub Actions workflow and build script both retain the unsigned Release build path and explicitly pass `-skipMacroValidation`.

## Build verification and IPA status

The source was reviewed for framework imports, SwiftData model registration, package constraints, and unsigned IPA packaging. The missing `import SwiftData` in `RootTabView.swift` was added, the unused optional binding in `ScreenTimeManager.startForegroundCountdown()` was replaced with an immutable captured expiry value, and the MLX Swift LM constraint was narrowed to the 3.32 minor line. All Swift files were syntax-parsed with Swift 6.2.1; the project YAML, workflow YAML, plists, entitlements, and shell build script passed their available syntax/structure checks. This Linux environment does not have Xcode, the iOS SDK, Apple signing certificates, or the Family Controls provisioning entitlements. Therefore the source has **not** been type-checked against Apple's frameworks, compiled for iOS, device-tested, or packaged as an `.ipa` here.

For the requested unsigned build, use `scripts/build-unsigned-ipa.sh` or the GitHub Actions workflow below. An Xcode Organizer archive/export is a separate signed-distribution workflow and is not required to produce `QUIZLOCK-unsigned.ipa`.

Do not submit to the App Store until the Family Controls distribution entitlement is approved.

## Folder structure

```text
QUIZLOCK-Core/
├── project.yml
├── README.md
├── Configuration/
│   ├── QUIZLOCK.entitlements
│   ├── QUIZLOCKMonitor.entitlements
│   └── QUIZLOCKMonitor-Info.plist
├── QuizLock/
│   ├── App/
│   │   └── QUIZLOCKApp.swift
│   ├── Models/
│   │   └── StudyModels.swift
│   ├── Services/
│   │   ├── LocalQuestionAIService.swift
│   │   └── ScreenTimeManager.swift
│   ├── Shared/
│   │   └── QuizLockShared.swift
│   └── Views/
│       ├── AppBlockerView.swift
│       ├── OnboardingView.swift
│       ├── QuizLockTheme.swift
│       ├── RootTabView.swift
│       ├── SettingsView.swift
│       └── StudyNotesView.swift
└── QuizLockMonitor/
    └── QuizLockMonitorExtension.swift
```

## Build an unsigned IPA (no certificates or profiles)

The repository includes `scripts/build-unsigned-ipa.sh`. It must be run on macOS with Xcode and XcodeGen installed:

```bash
brew install xcodegen
./scripts/build-unsigned-ipa.sh
```

The script generates the Xcode project, resolves Swift packages, and builds a Release configuration for `generic/platform=iOS`. It passes `-skipMacroValidation`, `CODE_SIGN_IDENTITY=''`, `CODE_SIGNING_REQUIRED=NO`, and `CODE_SIGNING_ALLOWED=NO`; it does not use a certificate or provisioning profile. It packages the resulting app and embedded `QUIZLOCKMonitor` extension as `dist/QUIZLOCK-unsigned.ipa`, verifies that both bundles are present, and removes code-signature/provisioning remnants.

Alternatively, push the project to a GitHub repository, open **Actions → Build unsigned QUIZLOCK IPA → Run workflow**, and download the `QUIZLOCK-unsigned-IPA` artifact when the workflow completes. The workflow uses `macos-latest`, finds `project.yml` whether the project is at the repository root or in a nested folder, generates the project with XcodeGen, calls the same build script, and uploads `dist/QUIZLOCK-unsigned.ipa`. It does not require signing secrets.

**Installation and entitlement limitations:** An unsigned IPA is a package, not an install-ready iPhone app. iOS requires executable code to be signed before it can run; an appropriate sideloading tool may sign it locally during installation. Separately, adding the Family Controls key to the source entitlements file does not grant the entitlement: Apple must authorize the Family Controls capability for the relevant app/extension provisioning profiles. Without that entitlement, the Screen Time blocker cannot request authorization or reliably function. See [Apple's Family Controls setup](https://developer.apple.com/documentation/xcode/configuring-family-controls) and [distribution entitlement request process](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

This Linux workspace cannot execute the build script. No `.ipa` is produced until the build runs on macOS with Xcode.

## Embedded Screen Time extension build diagnostics

The app and monitor extension now explicitly share `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`, and the extension Info.plist declares its bundle
identifier, executable, package type (`XPC!`), and matching version keys.

The unsigned build script writes the full Xcode output to
`build/xcodebuild.log`. If `ValidateEmbeddedBinary` fails, it prints the nearby
error/warning lines, displays the host/extension bundle identifiers and build
versions, and reruns Xcode's `embeddedBinaryValidationUtility` to expose its
full diagnostic. Upload this log when reporting a remaining failure.
