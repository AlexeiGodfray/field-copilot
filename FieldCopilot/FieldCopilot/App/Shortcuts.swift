import AppIntents
import Observation

/// "Scan a label with Field Copilot": opens the app on the camera.
struct ScanLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a label"
    static let description: IntentDescription? = IntentDescription("Opens the camera to scan an equipment label.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRequests.shared.scanLabel = true
        return .result()
    }
}

/// What Siri, Spotlight and the Shortcuts app offer as soon as the app is installed.
struct FieldCopilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanLabelIntent(),
            phrases: [
                "Scan a label with \(.applicationName)",
                "Scan a label in \(.applicationName)",
                "Scan equipment with \(.applicationName)",
            ],
            shortTitle: "Scan label",
            systemImageName: "camera.viewfinder"
        )
    }
}

/// What a shortcut asked the app to do, for the screens to act on.
@Observable
final class ShortcutRequests {
    static let shared = ShortcutRequests()
    /// Open the camera.
    var scanLabel = false
}
