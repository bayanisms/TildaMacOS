import AppKit
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @State private var selectedPane = "General"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(["General", "Appearance", "Terminal", "Shortcuts"], id: \.self) { pane in
                    Button { selectedPane = pane } label: {
                        Label(pane, systemImage: ["General": "slider.horizontal.3", "Appearance": "paintpalette", "Terminal": "terminal", "Shortcuts": "keyboard"][pane]!)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(selectedPane == pane ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
            Group {
                switch selectedPane {
                case "Appearance": appearance
                case "Terminal": terminal
                case "Shortcuts": shortcuts
                default: general
                }
            }.padding(.horizontal, 20).padding(.bottom, 16)
        }.frame(width: 590, height: 540).background(Color(nsColor: .windowBackgroundColor))
    }
    private var general: some View {
        Form {
            Section("Window behavior") {
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    ShortcutRecorder(preferences: preferences).frame(width: 155, height: 28)
                }
                if let error = preferences.shortcutError { Text(error).font(.caption).foregroundStyle(.red) }
                Toggle("Open on the display under the pointer", isOn: $preferences.value.followMouse)
                Toggle("Hide when another app becomes active", isOn: $preferences.value.autoHide)
                Toggle("Escape hides Tilda at an idle shell prompt", isOn: $preferences.value.escapeHides)
                Toggle("Animate the dropdown", isOn: $preferences.value.animate)
                Toggle("Start with the terminal hidden", isOn: $preferences.value.startHidden)
            }
            Section("Sessions") {
                Toggle("Reopen tab layouts and working directories", isOn: $preferences.value.restoreSessions)
                Text("Restores fresh shells, not running commands or scrollback.").font(.caption).foregroundStyle(.secondary)
                Toggle("Confirm before closing running shells", isOn: $preferences.value.confirmClose)
                Toggle("Launch at login", isOn: Binding(get: { preferences.loginEnabled }, set: { preferences.setLogin($0) }))
                if let error = preferences.loginError { Text(error).font(.caption).foregroundStyle(.secondary) }
                if preferences.loginStatus == .requiresApproval {
                    Button("Open Login Items…", action: preferences.openLoginSettings)
                }
            }
        }.formStyle(.grouped)
    }
    private var appearance: some View {
        Form {
            Section("Text and colors") {
                Picker("Theme", selection: $preferences.value.theme) {
                    ForEach(["Midnight", "Nord", "Dracula", "Daylight"], id: \.self) { Text($0) }
                }
                Picker("Font", selection: $preferences.value.fontName) {
                    Text("Menlo").tag("Menlo-Regular")
                    Text("SF Mono").tag("SFMono-Regular")
                    Text("Monaco").tag("Monaco")
                    Text("Courier").tag("Courier")
                }
                Stepper("Font size: \(Int(preferences.value.fontSize)) pt", value: $preferences.value.fontSize, in: 10...32)
                Picker("Cursor", selection: $preferences.value.cursor) {
                    ForEach(["Bar", "Block", "Underline"], id: \.self) { Text($0) }
                }
            }
            Section("Window") {
                settingSlider("Width", value: $preferences.value.width, range: 0.4...1)
                settingSlider("Height", value: $preferences.value.height, range: 0.25...0.95)
                settingSlider("Opacity", value: $preferences.value.opacity, range: 0.75...1)
            }
        }.formStyle(.grouped)
    }
    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().frame(width: 42, alignment: .trailing).foregroundStyle(.secondary)
        }
    }
    private var terminal: some View {
        Form {
            Section("New shells") {
                TextField("Shell", text: $preferences.value.shell, prompt: Text("System login shell"))
                TextField("Start in", text: $preferences.value.directory, prompt: Text("Home directory"))
                Text("Use an absolute shell path, e.g. /bin/zsh. Changes apply to new panes.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Interaction") {
                Picker("Scrollback", selection: $preferences.value.scrollback) {
                    Text("1,000 lines").tag(1_000)
                    Text("10,000 lines").tag(10_000)
                    Text("50,000 lines").tag(50_000)
                    Text("100,000 lines").tag(100_000)
                }
                Text("Scrollback changes apply to new panes.").font(.caption).foregroundStyle(.secondary)
                Toggle("Use Option as the Meta key", isOn: $preferences.value.optionAsMeta)
                Toggle("Audible terminal bell", isOn: $preferences.value.audibleBell)
            }
        }.formStyle(.grouped)
    }
    private var shortcuts: some View {
        Form {
            Section("Terminal") {
                shortcut("Show / hide", preferences.value.shortcut.label)
                shortcut("New tab / close pane", "⌘T / ⌘W")
                shortcut("Select tab", "⌘1 … ⌘9")
                shortcut("Previous / next tab", "⌘⇧[ / ⌘⇧]")
                shortcut("Find / find next", "⌘F / ⌘G")
                shortcut("Hide terminal", "Escape (if enabled in General)")
            }
            Section("Workspace") {
                shortcut("Split right / split below", "⌘D / ⌘⇧D")
                shortcut("Next pane", "⌘⌥→")
                shortcut("Increase / decrease font size", "⌘+ / ⌘−")
                shortcut("Reset font size / clear scrollback", "⌘0 / ⌘K")
                shortcut("Preferences / quit", "⌘, / ⌘Q")
            }
        }.formStyle(.grouped)
    }
    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack { Text(name); Spacer(); Text(keys).foregroundStyle(.secondary).font(.system(.body, design: .monospaced)) }
    }
}
