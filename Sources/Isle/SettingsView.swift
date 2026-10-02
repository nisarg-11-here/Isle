import SwiftUI

/// The settings page: theme, glass look, reminder sound, launch at login.
struct SettingsView: View {
    @Environment(IslandModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isOn

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Theme")
            HStack(spacing: 10) {
                ForEach(IslandTheme.available, id: \.self) { theme in
                    ThemeTile(theme: theme, on: model.theme == theme) {
                        withAnimation(.island) { model.theme = theme }
                    }
                }
            }
            if model.theme.isGlass {
                SettingRow("Glass look") {
                    Picker("Glass look", selection: $model.glassLook) {
                        ForEach(GlassLook.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Separator()
            SettingRow("Reminder sound") { Switch(isOn: $model.reminderSound) }
            SettingRow("Launch at login") {
                Switch(isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        // The write-back below lands here too. Do not answer it with the opposite call:
                        // after "requires approval" that would undo the user's registration.
                        guard on != LaunchAtLogin.isOn else { return }
                        LaunchAtLogin.set(on)
                        launchAtLogin = LaunchAtLogin.isOn  // show the real state if macOS refused
                    }
            }
            Separator()
            HStack {
                Text("⌃⌥T opens Isle from anywhere · ⌘, settings")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink.opacity(0.45))
                Spacer()
                Button("Quit Isle") { NSApp.terminate(nil) }
                    .buttonStyle(PillButton(fill: Color.ink.opacity(0.12), text: .ink))
            }
            .padding(.horizontal, 10)
        }
        .animation(.snappy, value: model.theme)
    }
}

/// "‹ Settings" in the header, in place of the tabs.
struct SettingsBack: View {
    @Environment(IslandModel.self) private var model

    var body: some View {
        Button { model.toggleSettings() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text("Settings").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.ink.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(Color.ink.opacity(0.92))
            Spacer()
            control
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
}

private struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(.isleGreen)
    }
}

private struct Separator: View {
    var body: some View {
        Rectangle().fill(Color.ink.opacity(0.08)).frame(height: 1).padding(.horizontal, 10)
    }
}

/// A theme choice: a small island with one task, on a gradient, drawn in that theme.
private struct ThemeTile: View {
    let theme: IslandTheme
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.07, green: 0.37, blue: 0.35), Color(red: 0.19, green: 0.18, blue: 0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    preview
                }
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text(theme.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.92))
                    Spacer()
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(on ? Color.isleGreen : Color.ink.opacity(0.3))
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.ink.opacity(on ? 0.1 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.isleOrange.opacity(on ? 0.8 : 0), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Glass uses a material here, not glassEffect: Apple's guidance is no glass on glass.
    private var preview: some View {
        ZStack {
            if theme == .glass {
                // Frosted, with a bright edge, so it reads as glass even where a material cannot blur.
                Rectangle().fill(.ultraThinMaterial)
                Color.white.opacity(0.16)
                NotchShape(top: 4, bottom: 12).stroke(Color.white.opacity(0.45), lineWidth: 1)
            } else {
                Color.black
            }
            HStack(spacing: 6) {
                Circle().fill(Color.isleGreen).frame(width: 8, height: 8)
                Capsule().fill(Color.white.opacity(0.85)).frame(width: 52, height: 5)
            }
            .padding(.top, 8)
        }
        .frame(width: 124, height: 34)
        .clipShape(NotchShape(top: 4, bottom: 12))
        .environment(\.colorScheme, .dark)
    }
}
