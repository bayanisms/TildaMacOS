import AppKit
import Carbon
import SwiftUI
import TildaCore

final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x54494C44 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut) -> Bool {
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                        EventHotKeyID(signature: 0x54494C44, id: 1),
                                        GetApplicationEventTarget(), 0, &newReference)
        guard status == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        reference = newReference
        return true
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var preferences: Preferences
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.preferences = preferences
        button.target = button; button.action = #selector(RecorderButton.record)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.recording { button.title = preferences.value.shortcut.label }
    }
}

final class RecorderButton: NSButton {
    weak var preferences: Preferences?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func record() {
        recording = true; title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool {
        recording = false; title = preferences?.value.shortcut.label ?? "Set shortcut"
        return super.resignFirstResponder()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording, let preferences else { return super.keyDown(with: event) }
        if event.keyCode == 53 { _ = resignFirstResponder(); return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let functionKey = (122...126).contains(event.keyCode) || [120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90].contains(event.keyCode)
        guard !flags.intersection([.command, .control, .option]).isEmpty || functionKey else {
            preferences.shortcutError = "Include Control, Option, or Command, or use a function key."
            return
        }
        var carbon: UInt32 = 0; var label = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); label += "⌘" }
        let functions: [UInt16: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20"]
        label += functions[event.keyCode] ?? [49:"Space",48:"Tab",36:"Return",123:"←",124:"→",125:"↓",126:"↑" ][event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbon, label: label)
        if shortcut == preferences.value.shortcut || preferences.changeShortcut?(shortcut) == true {
            preferences.value.shortcut = shortcut; preferences.shortcutError = nil
        } else { preferences.shortcutError = "That shortcut is unavailable. Try another combination." }
        _ = resignFirstResponder()
    }
}
