import AppKit
import Combine
import SwiftUI
import ServiceManagement
import TildaCore

final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let preferences: Preferences
    lazy var workspace = Workspace(preferences: preferences)
    let hotKey = GlobalHotKey()
    var panel: DropdownPanel!
    var dropdown: DropdownContentView!
    var settings: NSWindow?
    var statusItem: NSStatusItem!
    var subscription: AnyCancellable?
    var localMonitor: Any?
    var timer: Timer?
    var previousApp: NSRunningApplication?
    var observers: [NSObjectProtocol] = []
    var visible = false
    private var pendingHide: (() -> Void)?
    var loginPermissionAlert: NSAlert?
    private var didShutDown = false
    private var animationsEnabled: Bool { preferences.value.animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        panel = DropdownPanel(contentRect: .init(x: 0, y: 0, width: 1000, height: 600), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Tilda"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.animationBehavior = .none
        panel.delegate = self; panel.acceptsMouseMovedEvents = true
        dropdown = DropdownContentView(content: NSHostingView(rootView: TerminalWindowView(workspace: workspace, preferences: preferences)))
        panel.contentView = dropdown
        workspace.hide = { [weak self] in self?.hide() }
        workspace.showPreferences = { [weak self] in self?.openPreferences() }
        workspace.toggleFullScreen = { [weak self] in self?.toggleFullScreen() }
        hotKey.actions[HotKeyID.toggle] = { [weak self] in self?.toggle() }
        hotKey.actions[HotKeyID.fullScreen] = { [weak self] in self?.toggleFullScreen() }
        preferences.changeShortcut = { [weak self] shortcut, keyPath in
            guard let self else { return false }
            let id = keyPath == \Configuration.fullScreenShortcut ? HotKeyID.fullScreen : HotKeyID.toggle
            if shortcut.isDisabled { self.hotKey.unregister(id: id); return true }
            return self.hotKey.register(shortcut, id: id)
        }
        var hotKeyErrors: [String] = []
        if !preferences.value.shortcut.isDisabled && !hotKey.register(preferences.value.shortcut, id: HotKeyID.toggle) {
            hotKeyErrors.append("Your saved show / hide shortcut is in use. Set another in General. The menu bar button always works.")
        }
        if !preferences.value.fullScreenShortcut.isDisabled && !hotKey.register(preferences.value.fullScreenShortcut, id: HotKeyID.fullScreen) {
            hotKeyErrors.append("Your saved full screen shortcut is in use. Set another in General.")
        }
        if !hotKeyErrors.isEmpty { preferences.shortcutError = hotKeyErrors.joined(separator: " ") }
        workspace.restore()
        subscription = preferences.$value.dropFirst().debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.workspace.applyPreferences()
            self.panel.alphaValue = self.preferences.value.opacity
            if self.visible { self.updatePanelFrame() } else { self.stopAnimationIfDisabled() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, self.visible, self.preferences.value.autoHide,
                  self.settings?.isVisible != true, self.panel.attachedSheet == nil, NSApp.modalWindow == nil,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.hide(restoreFocus: false)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.visible else { return }
            self.updatePanelFrame()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopAnimationIfDisabled()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.preferences.refreshLoginStatus()
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.visible else { return }
            self.workspace.activeSession?.refreshDirectory()
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        if preferences.value.rememberFullScreen && !preferences.transient && preferences.defaults.bool(forKey: "fullScreen.v1") {
            workspace.fullScreen = true
        }
        if !preferences.value.startHidden { show() }
        if !preferences.transient && ProcessInfo.processInfo.arguments.contains("--settings") { openPreferences() }
        if preferences.shouldAskForLoginPermission {
            DispatchQueue.main.async { [weak self] in self?.offerLoginPermission() }
        }
    }

    func offerLoginPermission() {
        guard loginPermissionAlert == nil, preferences.shouldAskForLoginPermission else { return }
        let alert = NSAlert()
        alert.messageText = "Launch Tilda at login?"
        alert.informativeText = "Tilda will open automatically when you sign in."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not Now")
        loginPermissionAlert = alert
        let parent: NSWindow
        if let settings, settings.isVisible { parent = settings }
        else { show(); parent = panel }
        NSApp.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: parent) { [weak self] response in
            guard let self else { return }
            self.loginPermissionAlert = nil
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            self.preferences.recordLoginChoice(allow: response == .alertFirstButtonReturn)
            if response == .alertFirstButtonReturn, let error = self.preferences.loginError,
               self.preferences.loginStatus != .requiresApproval {
                let failure = NSAlert()
                failure.messageText = "Could not enable launch at login"
                failure.informativeText = error
                failure.beginSheetModal(for: parent)
            }
        }
    }

    /// The display the panel opens on: the chosen display if connected, else under the pointer
    /// when Follow Mouse is on, else the primary display.
    private func showScreen() -> NSScreen? {
        let name = preferences.value.displayName
        if !name.isEmpty, let chosen = NSScreen.screens.first(where: { $0.localizedName == name }) { return chosen }
        let screen = preferences.value.followMouse
            ? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            : NSScreen.screens.first
        return screen ?? NSScreen.main
    }
    /// Full screen fills the display's visible area; otherwise the configured dropdown size.
    private func frame(on screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if workspace.fullScreen { return visibleFrame }
        return TerminalUtilities.panelFrame(visibleFrame: visibleFrame, width: preferences.value.width, height: preferences.value.height, position: preferences.value.position)
    }
    @objc func toggle() { visible && panel.isKeyWindow ? hide() : show() }
    @objc func toggleFullScreen() {
        defer { if !preferences.transient { preferences.defaults.set(workspace.fullScreen, forKey: "fullScreen.v1") } }
        guard visible else { workspace.fullScreen = true; show(); return }
        workspace.fullScreen.toggle()
        let target = frame(on: panel.screen ?? showScreen())
        if animationsEnabled {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = preferences.value.fullScreenDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else { panel.setFrame(target, display: true) }
        panel.makeKeyAndOrderFront(nil)
        workspace.focus()
    }
    private func updatePanelFrame() {
        let frame = frame(on: panel.screen ?? showScreen())
        if panel.frame != frame {
            finishTransition()
            panel.setFrame(frame, display: true)
        } else { stopAnimationIfDisabled() }
    }
    private func stopAnimationIfDisabled() {
        if !animationsEnabled && dropdown.isAnimating { finishTransition() }
    }
    private func finishTransition() {
        dropdown.setRevealed(visible, animated: false)
        panel.hasShadow = visible
        if !visible {
            let finish = pendingHide
            pendingHide = nil
            if let finish { finish() } else { panel.orderOut(nil) }
        }
    }
    func show() {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        if !panel.isVisible, let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = frontmost }
        let frame = frame(on: showScreen())
        let wasVisible = visible
        let wasOrdered = panel.isVisible
        visible = true
        pendingHide = nil
        panel.alphaValue = preferences.value.opacity
        panel.ignoresMouseEvents = false
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        if !wasOrdered { dropdown.setRevealed(false, animated: false) }
        panel.makeKeyAndOrderFront(nil)
        if !wasVisible || !wasOrdered {
            panel.hasShadow = false
            dropdown.setRevealed(true, animated: animationsEnabled, duration: preferences.value.dropdownDuration) { [weak self] in
                guard let self, self.visible else { return }
                self.panel.hasShadow = true
            }
        }
        workspace.focus()
    }
    func hide(restoreFocus: Bool = true) {
        guard visible else { return }
        visible = false
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        workspace.persist()
        let finish = { [weak self] in
            guard let self, !self.visible else { return }
            self.panel.orderOut(nil)
            if restoreFocus, self.previousApp?.isTerminated == false { self.previousApp?.activate(options: []) }
        }
        pendingHide = finish
        dropdown.setRevealed(false, animated: animationsEnabled, duration: preferences.value.dropdownDuration) { [weak self] in
            self?.pendingHide = nil
            finish()
        }
    }

    @objc func openPreferences() {
        preferences.refreshLoginStatus()
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Tilda Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(preferences: preferences))
            window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.visible, !self.panel.isKeyWindow,
                  self.preferences.value.autoHide,
                  self.settings?.isVisible != true, self.panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
            self.hide(restoreFocus: false)
        }
    }
    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, NSApp.modalWindow == nil else { return event }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command) && !flags.contains(.control) {
            switch key {
            case "t": workspace.newTab()
            case "w": flags.contains(.shift) ? workspace.selectedTab.map { workspace.closeTab($0) } : workspace.closePane()
            case "d": workspace.split(vertical: !flags.contains(.shift))
            case "f": workspace.searchVisible = true
            case "g": workspace.find(previous: flags.contains(.shift))
            case "k": workspace.clearScrollback()
            case ",": openPreferences()
            case "q": NSApp.terminate(nil)
            case "+", "=": preferences.value.fontSize = min(32, preferences.value.fontSize + 1)
            case "-": preferences.value.fontSize = max(10, preferences.value.fontSize - 1)
            case "0": preferences.value.fontSize = 13
            case "[", "{": workspace.cycleTab(-1)
            case "]", "}": workspace.cycleTab(1)
            case "\r" where flags == [.command]: toggleFullScreen()
            default:
                if event.keyCode == 124 && flags.contains(.option) { workspace.cyclePane() }
                else if let index = Int(key), (1...9).contains(index), workspace.tabs.count >= index { workspace.selectTab(workspace.tabs[index - 1].id) }
                else { return event }
            }
            return nil
        }
        if event.keyCode == 53 && flags.isEmpty {
            if workspace.searchVisible { workspace.searchVisible = false; workspace.focus(); return nil }
            // Escape remains available to Vim, less, fzf, SSH, and foreground commands.
            if preferences.value.escapeHides, let pane = workspace.activeSession, !pane.view.getTerminal().isCurrentBufferAlternate,
               tcgetpgrp(pane.view.process.childfd) == pane.view.process.shellPid {
                hide(); return nil
            }
        }
        return event
    }

    func buildMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item("About Tilda", #selector(about), ""))
        appMenu.addItem(item("Settings…", #selector(openPreferences), ","))
        appMenu.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services; appMenu.addItem(servicesItem); NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Tilda", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]; appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Tilda", #selector(quit), "q"))
        let root = NSMenuItem(title: "Tilda", action: nil, keyEquivalent: ""); root.submenu = appMenu; menu.addItem(root)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editRoot.submenu = edit; menu.addItem(editRoot)
        let terminalMenu = NSMenu(title: "Terminal")
        terminalMenu.addItem(item("Show Terminal", #selector(showFromMenu), ""))
        terminalMenu.addItem(item("New Tab", #selector(newTabFromMenu), "t"))
        terminalMenu.addItem(item("Toggle Full Screen", #selector(toggleFullScreen), ""))
        terminalMenu.addItem(item("Save Scrollback…", #selector(export), ""))
        let terminalRoot = NSMenuItem(title: "Terminal", action: nil, keyEquivalent: "")
        terminalRoot.submenu = terminalMenu; menu.addItem(terminalRoot)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        let windowRoot = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowRoot.submenu = windowMenu; menu.addItem(windowRoot); NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Tilda")
        let statusMenu = NSMenu()
        statusMenu.addItem(item("Show / Hide Tilda", #selector(toggle), ""))
        statusMenu.addItem(item("Toggle Full Screen", #selector(toggleFullScreen), ""))
        statusMenu.addItem(item("New Tab", #selector(newTabFromMenu), ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(item("Save Scrollback…", #selector(export), ""))
        statusMenu.addItem(item("Settings…", #selector(openPreferences), ","))
        statusMenu.addItem(item("About Tilda", #selector(about), ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(item("Quit Tilda", #selector(quit), "q"))
        statusItem.menu = statusMenu
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item("Show Terminal", #selector(showFromMenu), ""))
        menu.addItem(item("New Tab", #selector(newTabFromMenu), ""))
        menu.addItem(item("Settings…", #selector(openPreferences), ""))
        return menu
    }
    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    @objc func newTabFromMenu() { workspace.newTab(); show() }
    /// Finder service: opens a tab in the selected folder, or in the folder containing the selected file.
    @objc func newTabHere(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { error.pointee = "No folder selected."; return }
        for url in urls.prefix(9) {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            workspace.newTab(directory: (isDirectory ? url : url.deletingLastPathComponent()).path)
        }
        NSApp.activate(ignoringOtherApps: true)
        show()
    }
    @objc func showFromMenu() { show() }
    @objc func export() { show(); workspace.exportScrollback() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Tilda", .applicationVersion: version])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace.confirmClosing(workspace.allSessions) ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }
    func shutdown() {
        guard !didShutDown else { return }
        didShutDown = true
        pendingHide = nil
        workspace.persist(); workspace.allSessions.forEach { $0.stop() }
        timer?.invalidate()
        subscription?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        panel?.orderOut(nil); settings?.orderOut(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
