import AppKit
import TildaCore

/// Holds a closure for an `NSMenuItem`; the item keeps it alive through `representedObject`.
private final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

extension Workspace {
    func contextMenu(for session: TerminalSession) -> NSMenu {
        let view = session.view
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true, _ handler: @escaping () -> Void) {
            let action = MenuAction(handler)
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = action
            item.representedObject = action
            item.isEnabled = enabled
            menu.addItem(item)
        }
        let selection = view.getSelection()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let canPaste = NSPasteboard.general.string(forType: .string)?.isEmpty == false
        let running = !session.exited

        add("Copy", "c", enabled: !selection.isEmpty) { view.copy(view) }
        add("Paste", "v", enabled: canPaste && running) { view.paste(view) }
        add("Clean Paste", enabled: canPaste && running) { view.cleanPaste(nil) }
        add("Select All", "a") { view.selectAll(nil) }

        if let url = URL(string: selection), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            menu.addItem(.separator())
            add("Open URL") { NSWorkspace.shared.open(url) }
        } else if session.sshConnection == nil, let path = Self.existingPath(selection, relativeTo: session.directory) {
            menu.addItem(.separator())
            add("Open “\((path as NSString).lastPathComponent)”") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            add("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }

        menu.addItem(.separator())
        add("New Tab", "t") { [weak self] in self?.newTab() }
        add("Split Right", "d", enabled: (activeTab?.sessions.count ?? 4) < 4) { [weak self] in self?.split(vertical: true) }
        add("Split Below", "d", [.command, .shift], enabled: (activeTab?.sessions.count ?? 4) < 4) { [weak self] in self?.split(vertical: false) }
        add("Close Pane", "w") { [weak self] in self?.closePane() }

        menu.addItem(.separator())
        add("Find…", "f") { [weak self] in self?.searchVisible = true }
        add("Clear Scrollback", "k") { [weak self] in self?.clearScrollback() }
        add("Export Scrollback…") { [weak self] in self?.exportScrollback() }

        if session.sshConnection == nil {
            session.refreshDirectory()
            menu.addItem(.separator())
            add("Copy Working Directory") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.directory, forType: .string)
            }
            add("Open Working Directory in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: session.directory)) }
        }

        menu.addItem(.separator())
        add(fullScreen ? "Exit Full Screen" : "Enter Full Screen", "\r") { [weak self] in self?.toggleFullScreen?() }
        add("Settings…", ",") { [weak self] in self?.showPreferences?() }
        return menu
    }

    /// Resolves a selected single-line path (absolute, `~`, or relative to the pane's directory) if it exists.
    private static func existingPath(_ text: String, relativeTo directory: String) -> String? {
        guard !text.isEmpty, text.count < 1024, !text.contains("\n") else { return nil }
        var path = (text as NSString).expandingTildeInPath
        if !path.hasPrefix("/") { path = (directory as NSString).appendingPathComponent(path) }
        path = (path as NSString).standardizingPath
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }
}
