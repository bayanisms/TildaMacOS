import AppKit
import ServiceManagement

@main
enum TildaApp {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--login-item-status") {
            let status: String
            switch SMAppService.mainApp.status {
            case .enabled: status = "enabled"
            case .requiresApproval: status = "requires-approval"
            case .notRegistered: status = "not-registered"
            case .notFound: status = "not-found"
            @unknown default: status = "unknown"
            }
            print(status)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
