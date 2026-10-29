import Foundation
import CoreGraphics

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var label: String
    public init(keyCode: UInt32 = 50, modifiers: UInt32 = 4096, label: String = "⌃`") {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    public static let disabled = Shortcut(keyCode: UInt32.max, modifiers: 0, label: "None")
    public var isDisabled: Bool { keyCode == UInt32.max }
}

public struct Configuration: Codable, Equatable {
    public var width: Double = 0.92
    public var height: Double = 0.52
    public var opacity: Double = 0.98
    public var fontName = "Menlo-Regular"
    public var fontSize: Double = 13
    public var theme = "Midnight"
    public var cursor = "Bar"
    public var scrollback = 10_000
    public var shell = ""
    public var directory = ""
    public var followMouse = true
    public var autoHide = false
    public var escapeHides = false
    public var animate = true
    public var startHidden = false
    public var restoreSessions = true
    public var confirmClose = true
    public var optionAsMeta = true
    public var audibleBell = false
    public var shortcut = Shortcut()
    public var fullScreenShortcut = Shortcut(keyCode: 50, modifiers: 4608, label: "⌃⇧`")
    public var dropdownDuration: Double = 0.25
    public var fullScreenDuration: Double = 0.25
    /// Screen name to open on; empty uses `followMouse` (pointer display) or the primary display.
    public var displayName = ""
    public var position = "Center"
    public var rememberFullScreen = false
    public var copyOnSelect = false
    public init() {}

    /// Missing or invalid keys fall back to defaults so older saved settings keep loading.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func load<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let decoded = try? container.decodeIfPresent(T.self, forKey: key) { value = decoded }
        }
        load(.width, &width); load(.height, &height); load(.opacity, &opacity)
        load(.fontName, &fontName); load(.fontSize, &fontSize); load(.theme, &theme); load(.cursor, &cursor)
        load(.scrollback, &scrollback); load(.shell, &shell); load(.directory, &directory)
        load(.followMouse, &followMouse); load(.autoHide, &autoHide); load(.escapeHides, &escapeHides)
        load(.animate, &animate); load(.startHidden, &startHidden); load(.restoreSessions, &restoreSessions)
        load(.confirmClose, &confirmClose); load(.optionAsMeta, &optionAsMeta); load(.audibleBell, &audibleBell)
        load(.shortcut, &shortcut); load(.fullScreenShortcut, &fullScreenShortcut)
        load(.dropdownDuration, &dropdownDuration); load(.fullScreenDuration, &fullScreenDuration)
        load(.displayName, &displayName); load(.position, &position)
        load(.rememberFullScreen, &rememberFullScreen); load(.copyOnSelect, &copyOnSelect)
    }

    public mutating func sanitize() {
        width = width.isFinite ? min(1, max(0.4, width)) : 0.92
        height = height.isFinite ? min(0.95, max(0.25, height)) : 0.52
        opacity = opacity.isFinite ? min(1, max(0.75, opacity)) : 0.98
        fontSize = fontSize.isFinite ? min(32, max(10, fontSize)) : 13
        scrollback = min(100_000, max(1_000, scrollback))
        dropdownDuration = dropdownDuration.isFinite ? min(1, max(0.05, dropdownDuration)) : 0.25
        fullScreenDuration = fullScreenDuration.isFinite ? min(1, max(0.05, fullScreenDuration)) : 0.25
        if !["Midnight", "Nord", "Dracula", "Daylight"].contains(theme) { theme = "Midnight" }
        if !["Bar", "Block", "Underline"].contains(cursor) { cursor = "Bar" }
        if !["Left", "Center", "Right"].contains(position) { position = "Center" }
    }
}

public struct SavedTab: Codable, Equatable {
    public var directories: [String]
    public var vertical: Bool
    public var title: String?
    public init(directories: [String], vertical: Bool, title: String? = nil) {
        self.directories = Array(directories.prefix(4)); self.vertical = vertical; self.title = title
    }
}

public enum TerminalUtilities {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    public static func panelFrame(visibleFrame: CGRect, width: Double, height: Double, position: String = "Center") -> CGRect {
        let w = min(visibleFrame.width, max(0, visibleFrame.width * width))
        let h = min(visibleFrame.height, max(0, visibleFrame.height * height))
        let x = position == "Left" ? visibleFrame.minX : position == "Right" ? visibleFrame.maxX - w : visibleFrame.midX - w / 2
        return CGRect(x: x, y: visibleFrame.maxY - h, width: w, height: h)
    }
    /// Normalizes text copied from documents and web pages so it pastes as plain shell input:
    /// typographic quotes and dashes become ASCII, invisible characters and control codes are removed,
    /// line endings become `\n`, and trailing whitespace is trimmed so the paste does not run a command.
    public static func cleanPaste(_ text: String) -> String {
        let replacements: [Character: String] = [
            "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{2032}": "'",
            "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
            "\u{2013}": "-", "\u{2014}": "-", "\u{2212}": "-",
            "\u{00A0}": " ", "\u{202F}": " ", "\u{2009}": " ", "\u{2026}": "...",
            "\u{200B}": "", "\u{200C}": "", "\u{200D}": "", "\u{2060}": "", "\u{FEFF}": ""
        ]
        var result = ""
        for character in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") {
            if let replacement = replacements[character] { result += replacement; continue }
            if character == "\n" || character == "\t" { result.append(character); continue }
            if character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { continue }
            result.append(character)
        }
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }
    public static func localDirectory(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("file:") {
            guard let url = URL(string: value), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost" || url.host == ProcessInfo.processInfo.hostName else { return nil }
            return url.path
        }
        return value.hasPrefix("/") ? value : nil
    }
    /// Expands `~` and returns the path if it names an existing directory by absolute path.
    public static func directoryPath(_ value: String) -> String? {
        let path = (value as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue ? path : nil
    }
    /// Expands `~` and returns the path if it names an executable regular file by absolute path.
    public static func executablePath(_ value: String) -> String? {
        let path = (value as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
