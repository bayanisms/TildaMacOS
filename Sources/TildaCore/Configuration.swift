import Foundation
import CoreGraphics

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var label: String
    public init(keyCode: UInt32 = 50, modifiers: UInt32 = 4096, label: String = "⌃`") {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
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
    }
}

public struct SavedTab: Codable, Equatable {
    public var directories: [String]
    public var vertical: Bool
    public init(directories: [String], vertical: Bool) {
        self.directories = Array(directories.prefix(4)); self.vertical = vertical
    }
}

public enum TerminalUtilities {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    public static func panelFrame(visibleFrame: CGRect, width: Double, height: Double) -> CGRect {
        let w = min(visibleFrame.width, max(0, visibleFrame.width * width))
        let h = min(visibleFrame.height, max(0, visibleFrame.height * height))
        return CGRect(x: visibleFrame.midX - w / 2, y: visibleFrame.maxY - h, width: w, height: h)
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
