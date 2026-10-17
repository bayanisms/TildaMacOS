import AppKit
import SwiftTerm
import SwiftUI
import TildaCore

struct TerminalTab: Identifiable {
    let id = UUID()
    var sessions: [TerminalSession]
    var selected: UUID
    var vertical = true
    var title: String { sessions.first(where: { $0.id == selected })?.title ?? "Shell" }
}

final class Workspace: ObservableObject {
    @Published var tabs: [TerminalTab] = []
    @Published var selectedTab: UUID?
    @Published var pinned = false
    @Published var searchVisible = false
    @Published var searchQuery = ""
    @Published var caseSensitive = false
    @Published var regex = false
    @Published var matchLabel = ""
    let preferences: Preferences
    var showPreferences: (() -> Void)?
    var hide: (() -> Void)?
    var activeTab: TerminalTab? { tabs.first { $0.id == selectedTab } }
    var activeSession: TerminalSession? { activeTab.flatMap { tab in tab.sessions.first { $0.id == tab.selected } } }
    var allSessions: [TerminalSession] { tabs.flatMap(\.sessions) }

    init(preferences: Preferences) { self.preferences = preferences }

    private func session(directory: String?) -> TerminalSession {
        let session = TerminalSession(directory: directory, configuration: preferences.value)
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        session.onFocus = { [weak self, weak session] in
            guard let self, let session,
                  let index = self.tabs.firstIndex(where: { $0.sessions.contains(where: { $0.id == session.id }) }) else { return }
            guard self.selectedTab != self.tabs[index].id || self.tabs[index].selected != session.id else { return }
            self.tabs[index].selected = session.id
            self.selectedTab = self.tabs[index].id
        }
        return session
    }

    func restore() {
        if !preferences.transient, preferences.value.restoreSessions,
           let data = preferences.defaults.data(forKey: "sessions.v1"),
           let saved = try? JSONDecoder().decode([SavedTab].self, from: data) {
            for tab in saved.prefix(12) where !tab.directories.isEmpty {
                let sessions = tab.directories.prefix(4).map { session(directory: $0) }
                tabs.append(TerminalTab(sessions: sessions, selected: sessions[0].id, vertical: tab.vertical))
            }
        }
        if tabs.isEmpty { newTab() }
        selectedTab = tabs.first?.id
    }
    func persist() {
        allSessions.forEach { $0.refreshDirectory() }
        guard !preferences.transient else { return }
        let saved = tabs.map { SavedTab(directories: $0.sessions.map(\.directory), vertical: $0.vertical) }
        if let data = try? JSONEncoder().encode(saved) { preferences.defaults.set(data, forKey: "sessions.v1") }
    }
    func newTab() {
        guard tabs.count < 12 else { NSSound.beep(); return }
        activeSession?.refreshDirectory()
        let pane = session(directory: activeSession?.directory)
        let tab = TerminalTab(sessions: [pane], selected: pane.id)
        tabs.append(tab); selectedTab = tab.id
        focus(); persist()
    }
    func split(vertical: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTab }), tabs[index].sessions.count < 4 else { NSSound.beep(); return }
        activeSession?.refreshDirectory()
        let pane = session(directory: activeSession?.directory)
        tabs[index].vertical = vertical
        tabs[index].sessions.append(pane)
        tabs[index].selected = pane.id
        focus(); persist()
    }
    func selectTab(_ id: UUID) { selectedTab = id; activeSession?.refreshDirectory(); searchVisible = false; focus() }
    func cycleTab(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex(where: { $0.id == selectedTab }) ?? 0
        selectTab(tabs[(index + offset + tabs.count) % tabs.count].id)
    }
    func cyclePane() {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTab }) else { return }
        let tab = tabs[index]
        let selected = tab.sessions.firstIndex(where: { $0.id == tab.selected }) ?? 0
        tabs[index].selected = tab.sessions[(selected + 1) % tab.sessions.count].id
        focus()
    }
    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.activeSession?.view else { return }
            view.window?.makeFirstResponder(view)
        }
    }
    func confirmClosing(_ sessions: [TerminalSession]) -> Bool {
        guard preferences.value.confirmClose, sessions.contains(where: { !$0.exited }) else { return true }
        let alert = NSAlert()
        alert.messageText = sessions.count == 1 ? "Close this terminal?" : "Close \(sessions.count) terminals?"
        alert.informativeText = "This ends the shells and any commands running in them. Hide Tilda to keep them running."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Close")
        alert.alertStyle = .warning
        return alert.runModal() == .alertSecondButtonReturn
    }
    func closePane() {
        guard let pane = activeSession, confirmClosing([pane]),
              let index = tabs.firstIndex(where: { $0.id == selectedTab }) else { return }
        pane.stop()
        tabs[index].sessions.removeAll { $0.id == pane.id }
        if tabs[index].sessions.isEmpty {
            tabs.remove(at: index)
            selectedTab = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        } else { tabs[index].selected = tabs[index].sessions[0].id }
        if tabs.isEmpty { newTab(); hide?() } else { focus() }
        persist()
    }
    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), confirmClosing(tabs[index].sessions) else { return }
        tabs[index].sessions.forEach { $0.stop() }
        tabs.remove(at: index)
        if selectedTab == id { selectedTab = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
        if tabs.isEmpty { newTab(); hide?() } else { focus() }
        persist()
    }
    func applyPreferences() { allSessions.forEach { $0.apply(preferences.value) }; objectWillChange.send() }
    func find(previous: Bool = false, reset: Bool = false) {
        guard let pane = activeSession else { return }
        if reset { pane.view.clearSearch() }
        guard !searchQuery.isEmpty else { matchLabel = ""; return }
        if regex, (try? NSRegularExpression(pattern: searchQuery)) == nil { matchLabel = "Invalid regex"; return }
        let options = SearchOptions(caseSensitive: caseSensitive, regex: regex)
        if previous { pane.view.findPrevious(searchQuery, options: options) }
        else { pane.view.findNext(searchQuery, options: options) }
        let result = pane.view.searchMatchSummary(searchQuery, options: options)
        matchLabel = result.total == 0 ? "No matches" : "\(result.index) of \(result.total)\(result.total == 1000 ? "+" : "")"
    }
    func clearScrollback() { activeSession?.view.getTerminal().clearScrollback(); activeSession?.view.needsDisplay = true }
    func exportScrollback() {
        guard let session = activeSession else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tilda-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try session.view.getTerminal().getBufferAsData().write(to: url, options: .atomic) }
        catch { NSAlert(error: error).runModal() }
    }
}
