import AppKit
import Combine
import Foundation
import ServiceManagement
import TildaCore

final class Preferences: ObservableObject {
    static let shared = Preferences()
    let transient: Bool
    let defaults: UserDefaults
    private let loginItems: LoginItemControlling
    private static let loginPermissionKey = "loginPermissionAsked.v1"
    @Published var value: Configuration {
        didSet {
            let validated = Self.validated(value, checkFont: value.fontName != oldValue.fontName)
            if validated != value { value = validated }
            if !transient, let data = try? JSONEncoder().encode(validated) { defaults.set(data, forKey: "configuration.v1") }
        }
    }
    @Published var shortcutError: String?
    @Published var loginError: String?
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    var loginEnabled: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var shouldAskForLoginPermission: Bool {
        !transient && !defaults.bool(forKey: Self.loginPermissionKey) && loginStatus != .enabled
    }
    var changeShortcut: ((Shortcut, WritableKeyPath<Configuration, Shortcut>) -> Bool)?
    var shellError: String? {
        value.shell.isEmpty || TerminalUtilities.executablePath(value.shell) != nil ? nil : "Shell must be an executable file at an absolute path."
    }
    var directoryError: String? {
        value.directory.isEmpty || TerminalUtilities.directoryPath(value.directory) != nil ? nil : "Directory not found. New tabs will open in the current pane's directory."
    }

    /// Fonts offered in Preferences, limited to those available on this Mac.
    static let fonts = [("Menlo", "Menlo-Regular"), ("SF Mono", "SFMono-Regular"), ("Monaco", "Monaco"), ("Courier", "Courier")]
        .filter { terminalFont($0.1, size: 13) != nil }

    /// SF Mono is the system monospaced font and may not resolve by name.
    static func terminalFont(_ name: String, size: Double) -> NSFont? {
        NSFont(name: name, size: size) ?? (name == "SFMono-Regular" ? .monospacedSystemFont(ofSize: size, weight: .regular) : nil)
    }

    private static func validated(_ value: Configuration, checkFont: Bool = true) -> Configuration {
        var config = value
        config.sanitize()
        if checkFont && terminalFont(config.fontName, size: config.fontSize) == nil { config.fontName = "Menlo-Regular" }
        return config
    }

    init(transient: Bool = false, defaults: UserDefaults = .standard, loginItems: LoginItemControlling = SystemLoginItemController()) {
        self.transient = transient
        self.defaults = defaults
        self.loginItems = loginItems
        let config = (transient ? nil : defaults.data(forKey: "configuration.v1"))
            .flatMap { try? JSONDecoder().decode(Configuration.self, from: $0) } ?? Configuration()
        value = Self.validated(config)
        if !transient { refreshLoginStatus() }
    }

    func setLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                if loginItems.status != .enabled && loginItems.status != .requiresApproval { try loginItems.register() }
            } else if loginItems.status != .notRegistered { try loginItems.unregister() }
            refreshLoginStatus()
            if enabled && loginStatus == .requiresApproval { loginItems.openSettings() }
        } catch {
            loginStatus = loginItems.status
            if enabled && loginStatus == .requiresApproval {
                loginError = "Approval required in System Settings."
                loginItems.openSettings()
            } else { loginError = error.localizedDescription }
        }
    }

    func refreshLoginStatus() {
        guard !transient else { return }
        loginStatus = loginItems.status
        loginError = loginStatus == .requiresApproval ? "Approval required in System Settings." : nil
        if loginStatus == .enabled { defaults.set(true, forKey: Self.loginPermissionKey) }
    }

    func recordLoginChoice(allow: Bool) {
        guard !transient else { return }
        defaults.set(true, forKey: Self.loginPermissionKey)
        if allow { setLogin(true) }
    }

    func openLoginSettings() {
        loginItems.openSettings()
    }
}
