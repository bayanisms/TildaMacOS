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
            var validated = value
            validated.sanitize()
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
    var changeShortcut: ((Shortcut) -> Bool)?

    init(transient: Bool = false, defaults: UserDefaults = .standard, loginItems: LoginItemControlling = SystemLoginItemController()) {
        self.transient = transient
        self.defaults = defaults
        self.loginItems = loginItems
        var config = (transient ? nil : defaults.data(forKey: "configuration.v1"))
            .flatMap { try? JSONDecoder().decode(Configuration.self, from: $0) } ?? Configuration()
        config.sanitize()
        value = config
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
