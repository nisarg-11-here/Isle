import ServiceManagement
import SwiftUI

/// What the open island shows.
enum Page { case tasks, settings, plan, notes }

enum IslandTheme: String, CaseIterable {
    case standard, glass
    var title: String { self == .standard ? "Standard" : "Glass" }

    /// Liquid Glass needs macOS 26. Before it, a saved Glass choice draws as Standard.
    static var glassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// The themes this Mac can show.
    static var available: [IslandTheme] { glassAvailable ? allCases : [.standard] }

    /// True when the island draws Liquid Glass.
    var isGlass: Bool { self == .glass && Self.glassAvailable }
}

/// The color scheme of the Glass theme.
enum GlassLook: String, CaseIterable {
    case system, light, dark
    var title: String { rawValue.capitalized }
}

enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            NSLog("Isle: launch at login failed: \(error)")
        }
    }
}
