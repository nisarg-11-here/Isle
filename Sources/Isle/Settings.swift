import ServiceManagement
import SwiftUI

/// What the open island shows.
enum Page { case tasks, settings }

enum IslandTheme: String, CaseIterable {
    case standard, glass
    var title: String { self == .standard ? "Standard" : "Glass" }
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
