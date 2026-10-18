import AppKit
import Darwin
import SwiftTerm
import TildaCore

final class TerminalSession: NSObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let view: ShellTerminalView
    var title = "Shell"
    var directory: String
    var exited = false
    var columns = 80
    var rows = 24
    var onChange: (() -> Void)?
    var onFocus: (() -> Void)?
    private(set) var sshConnection: SSHProcess?
    private var remoteDirectory: WorkingDirectoryReport?
    private var stopped = false

    var locationLabel: String { exited ? "SESSION ENDED" : sshConnection == nil ? "LOCAL" : "SSH" }
    var displayLocation: String {
        if let connection = sshConnection {
            let reportedHost = remoteDirectory?.host.flatMap { $0.isEmpty ? nil : $0 }
            let name: String
            if let reportedHost, reportedHost.caseInsensitiveCompare(connection.endpoint?.host ?? "") != .orderedSame {
                name = reportedHost
            } else { name = connection.endpoint?.displayName ?? reportedHost ?? "—" }
            return name + (remoteDirectory.map { " · \($0.path)" } ?? "")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return directory == home ? "~" : directory.hasPrefix(home + "/") ? "~" + directory.dropFirst(home.count) : directory
    }

    init(directory: String?, configuration: Configuration) {
        let requested = (directory ?? configuration.directory) as NSString?
        let expanded = requested?.expandingTildeInPath ?? ""
        var isDirectory: ObjCBool = false
        self.directory = expanded.hasPrefix("/") && FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) && isDirectory.boolValue
            ? expanded : FileManager.default.homeDirectoryForCurrentUser.path
        view = ShellTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 400), options: TerminalOptions(scrollback: configuration.scrollback, kittyImageCacheLimitBytes: 16 * 1024 * 1024))
        super.init()
        view.processDelegate = self
        view.onFocus = { [weak self] in self?.onFocus?() }
        view.setAccessibilityLabel("Shell terminal")
        apply(configuration)
        DispatchQueue.main.async { [weak self] in self?.start(configuration) }
    }

    private func start(_ configuration: Configuration) {
        guard !stopped else { return }
        let accountShell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        let shell = configuration.shell.isEmpty ? accountShell : (configuration.shell as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard shell.hasPrefix("/"), FileManager.default.fileExists(atPath: shell, isDirectory: &isDirectory),
              !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: shell) else {
            exited = true
            view.feed(text: "\r\n  Cannot launch shell: \(shell)\r\n  Choose an executable in Preferences → Terminal, then open a new pane.\r\n")
            onChange?(); return
        }
        title = URL(fileURLWithPath: shell).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
        environment += ["TERM_PROGRAM=Tilda", "TERM_PROGRAM_VERSION=\(version)", "SHELL=\(shell)", "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        environment.append("TERM_SESSION_ID=\(id.uuidString)")
        for key in ["SSH_AUTH_SOCK", "TMPDIR"] {
            if let value = ProcessInfo.processInfo.environment[key] { environment.append("\(key)=\(value)") }
        }
        view.startProcess(executable: shell, args: ["-l"], environment: environment, execName: URL(fileURLWithPath: shell).lastPathComponent, currentDirectory: directory)
        onChange?()
    }

    func apply(_ configuration: Configuration) {
        let theme = TerminalTheme.named(configuration.theme)
        view.font = NSFont(name: configuration.fontName, size: configuration.fontSize) ?? NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        view.nativeBackgroundColor = theme.background
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.accent
        view.selectedTextBackgroundColor = theme.accent.withAlphaComponent(0.25)
        view.optionAsMetaKey = configuration.optionAsMeta
        view.bellStyle = configuration.audibleBell ? .sound : .visual
        view.installColors(theme.palette.map {
            let n = UInt32($0, radix: 16) ?? 0
            return SwiftTerm.Color(red: UInt16((n >> 16) & 255) * 257, green: UInt16((n >> 8) & 255) * 257, blue: UInt16(n & 255) * 257)
        })
        let cursor: CursorStyle = configuration.cursor == "Block" ? .steadyBlock : configuration.cursor == "Underline" ? .steadyUnderline : .blinkBar
        view.getTerminal().setCursorStyle(cursor)
        view.needsDisplay = true
    }

    func refreshDirectory() {
        guard view.process.running, view.process.shellPid > 0 else { return }
        let connection = ProcessContext.foregroundSSH(shellPID: view.process.shellPid, terminalFD: view.process.childfd, previous: sshConnection)
        if connection != sshConnection {
            sshConnection = connection
            remoteDirectory = nil
            onChange?()
        }
        var info = proc_vnodepathinfo()
        let count = proc_pidinfo(view.process.shellPid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard count == MemoryLayout<proc_vnodepathinfo>.size else { return }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        if path != directory && !path.isEmpty { directory = path; onChange?() }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if view.process.running {
            let foreground = tcgetpgrp(view.process.childfd)
            if foreground > 0 && foreground != getpgrp() { kill(-foreground, SIGHUP); kill(-foreground, SIGTERM) }
            let shell = view.process.shellPid
            if shell > 0 && shell != foreground { kill(-shell, SIGHUP) }
            view.terminate()
        }
        view.processDelegate = nil
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Publish outside the AppKit layout pass to keep SwiftUI updates consistent.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.columns != newCols || self.rows != newRows else { return }
            self.columns = newCols; self.rows = newRows; self.onChange?()
        }
    }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(100).map(String.init).joined())
        onChange?()
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        refreshDirectory()
        if sshConnection != nil {
            remoteDirectory = WorkingDirectoryReport.parse(directory)
            onChange?()
        } else if let path = TerminalUtilities.localDirectory(directory) {
            self.directory = path; onChange?()
        }
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard !stopped else { return }
        exited = true
        sshConnection = nil; remoteDirectory = nil
        view.feed(text: "\r\n\u{1B}[90m  Session ended\(exitCode.map { " (\($0))" } ?? ""). Open a new tab with ⌘T.\u{1B}[0m\r\n")
        onChange?()
    }
}

final class ShellTerminalView: LocalProcessTerminalView {
    var onFocus: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        if result != nil && NSApp.currentEvent?.type == .leftMouseDown {
            DispatchQueue.main.async { [weak self] in self?.onFocus?() }
        }
        return result
    }
    override func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme) else { NSSound.beep(); return }
        NSWorkspace.shared.open(url)
    }
}
