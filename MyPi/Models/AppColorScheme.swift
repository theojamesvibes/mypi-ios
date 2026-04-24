import SwiftUI

/// User preference for the app's appearance. Stored as a `String`-raw enum
/// so `@AppStorage` can persist it directly without a custom codec.
///
/// The `.system` case returns `nil` from `colorScheme` which, applied to
/// `.preferredColorScheme(_:)`, means "defer to the OS". Light and dark
/// force the respective scheme across the whole view hierarchy including
/// sheets and the splash — ContentView applies this at its root so no
/// individual screen needs to remember it.
enum AppColorScheme: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// `@AppStorage` key used across `ContentView` (reader/apply) and
    /// `AppSettingsView` (editor). Shared constant so both sides can't
    /// drift onto different keys.
    static let storageKey = "appColorScheme"
}
