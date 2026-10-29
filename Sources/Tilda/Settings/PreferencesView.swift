import AppKit
import ServiceManagement
import SwiftUI
import TildaCore

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @State private var selectedPane = "General"
    @State private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @FocusState private var focusedField: PathField?
    @State private var shellError: String?
    @State private var directoryError: String?
    private enum PathField { case shell, directory }
    private var fonts: [(String, String)] {
        var fonts = Preferences.fonts
        if !fonts.contains(where: { $0.1 == preferences.value.fontName }) {
            fonts.append((preferences.value.fontName, preferences.value.fontName))
        }
        return fonts
    }
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
        }.frame(width: 590, height: 620).background(Color(nsColor: .windowBackgroundColor))
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
                reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
    }
    private var general: some View {
        Form {
            Section("Window behavior") {
                HStack {
                    Text("Show / hide shortcut")
                    Spacer()
                    ShortcutRecorder(preferences: preferences).frame(width: 155, height: 28)
                    clearShortcut(\.shortcut)
                }
                HStack {
                    Text("Full screen shortcut")
                    Spacer()
                    ShortcutRecorder(preferences: preferences, keyPath: \.fullScreenShortcut).frame(width: 155, height: 28)
                    clearShortcut(\.fullScreenShortcut)
                }
                if let error = preferences.shortcutError { Text(error).font(.caption).foregroundStyle(.red) }
                Picker("Display", selection: displaySelection) {
                    Text("Display under pointer").tag(Self.pointerDisplay)
                    Text("Primary display").tag(Self.primaryDisplay)
                    ForEach(displayNames, id: \.self) { name in
                        Text(NSScreen.screens.contains { $0.localizedName == name } ? name : "\(name) (not connected)").tag(name)
                    }
                }
                Toggle("Hide when another app becomes active", isOn: $preferences.value.autoHide)
                Text("The pin button in the terminal toolbar turns this off.").font(.caption).foregroundStyle(.secondary)
                Toggle("Escape hides Tilda at an idle shell prompt", isOn: $preferences.value.escapeHides)
                Toggle("Animate showing, hiding, and full screen", isOn: $preferences.value.animate)
                if preferences.value.animate {
                    durationSlider("Dropdown", value: $preferences.value.dropdownDuration)
                    durationSlider("Full screen", value: $preferences.value.fullScreenDuration)
                }
                if reduceMotion && preferences.value.animate {
                    Text("Animation is disabled by macOS Reduce Motion.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Start with the terminal hidden", isOn: $preferences.value.startHidden)
            }
            Section("Sessions") {
                Toggle("Reopen tab layouts and working directories", isOn: $preferences.value.restoreSessions)
                Text("Restores fresh shells, not running commands or scrollback.").font(.caption).foregroundStyle(.secondary)
                Toggle("Confirm before closing running shells", isOn: $preferences.value.confirmClose)
                Toggle("Remember full screen", isOn: $preferences.value.rememberFullScreen)
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
                    ForEach(fonts, id: \.1) { font in Text(font.0).tag(font.1) }
                }
                Stepper("Font size: \(Int(preferences.value.fontSize)) pt", value: $preferences.value.fontSize, in: 10...32)
                Picker("Cursor", selection: $preferences.value.cursor) {
                    ForEach(["Bar", "Block", "Underline"], id: \.self) { Text($0) }
                }
            }
            Section("Window") {
                Picker("Position", selection: $preferences.value.position) {
                    ForEach(["Left", "Center", "Right"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                settingSlider("Width", value: $preferences.value.width, range: 0.4...1)
                settingSlider("Height", value: $preferences.value.height, range: 0.25...0.95)
                settingSlider("Opacity", value: $preferences.value.opacity, range: 0.75...1)
            }
        }.formStyle(.grouped)
    }
    private static let pointerDisplay = "\u{0}pointer"
    private static let primaryDisplay = "\u{0}primary"
    /// Connected display names, plus the saved one if it is disconnected.
    private var displayNames: [String] {
        var names = NSScreen.screens.map(\.localizedName)
        let saved = preferences.value.displayName
        if !saved.isEmpty && !names.contains(saved) { names.append(saved) }
        return names
    }
    private var displaySelection: Binding<String> {
        Binding(get: {
            let value = preferences.value
            return !value.displayName.isEmpty ? value.displayName : value.followMouse ? Self.pointerDisplay : Self.primaryDisplay
        }, set: { choice in
            switch choice {
            case Self.pointerDisplay: preferences.value.displayName = ""; preferences.value.followMouse = true
            case Self.primaryDisplay: preferences.value.displayName = ""; preferences.value.followMouse = false
            default: preferences.value.displayName = choice
            }
        })
    }
    private func clearShortcut(_ keyPath: WritableKeyPath<Configuration, Shortcut>) -> some View {
        Button {
            _ = preferences.changeShortcut?(.disabled, keyPath)
            preferences.value[keyPath: keyPath] = .disabled
            preferences.shortcutError = nil
        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain).help("Clear shortcut")
            .disabled(preferences.value[keyPath: keyPath].isDisabled)
    }
    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().frame(width: 42, alignment: .trailing).foregroundStyle(.secondary)
        }
    }
    private func durationSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: value, in: 0.05...1, step: 0.05)
            Text(String(format: "%.2f s", value.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing).foregroundStyle(.secondary)
        }
    }
    private var terminal: some View {
        Form {
            Section("New shells") {
                TextField("Shell", text: $preferences.value.shell, prompt: Text("System login shell"))
                    .focused($focusedField, equals: .shell)
                    .onSubmit { shellError = preferences.shellError }
                if let shellError { Text(shellError).font(.caption).foregroundStyle(.red) }
                TextField("Start in", text: $preferences.value.directory, prompt: Text("Home directory"))
                    .focused($focusedField, equals: .directory)
                    .onSubmit { directoryError = preferences.directoryError }
                if let directoryError { Text(directoryError).font(.caption).foregroundStyle(.red) }
                Text("Use an absolute shell path, e.g. /bin/zsh. Changes apply to new panes; splits start in the current pane's directory.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Toggle("Copy selected text automatically", isOn: $preferences.value.copyOnSelect)
                Text("Middle-click pastes.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .onAppear(perform: validatePaths)
            .onChange(of: focusedField) { _ in validatePaths() }
    }
    private func validatePaths() {
        shellError = preferences.shellError
        directoryError = preferences.directoryError
    }
    private var shortcuts: some View {
        Form {
            Section("Terminal") {
                shortcut("Show / hide", preferences.value.shortcut.label)
                shortcut("Full screen", preferences.value.fullScreenShortcut.label)
                shortcut("Full screen (terminal focused)", "⌘⏎")
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
                shortcut("Rename tab", "Double-click tab")
                shortcut("Paste", "Middle-click")
                shortcut("Context menu", "Right-click")
            }
        }.formStyle(.grouped)
    }
    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack { Text(name); Spacer(); Text(keys).foregroundStyle(.secondary).font(.system(.body, design: .monospaced)) }
    }
}
