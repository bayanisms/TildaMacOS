import AppKit

struct TerminalTheme {
    let background: NSColor
    let foreground: NSColor
    let accent: NSColor
    let palette: [String]
    static func named(_ name: String) -> TerminalTheme {
        switch name {
        case "Nord": return .init(background: .hex("242933"), foreground: .hex("D8DEE9"), accent: .hex("88C0D0"), palette: ["3B4252","BF616A","A3BE8C","EBCB8B","81A1C1","B48EAD","88C0D0","E5E9F0","4C566A","BF616A","A3BE8C","EBCB8B","81A1C1","B48EAD","8FBCBB","ECEFF4"])
        case "Dracula": return .init(background: .hex("282A36"), foreground: .hex("F8F8F2"), accent: .hex("BD93F9"), palette: ["21222C","FF5555","50FA7B","F1FA8C","BD93F9","FF79C6","8BE9FD","F8F8F2","6272A4","FF6E6E","69FF94","FFFFA5","D6ACFF","FF92DF","A4FFFF","FFFFFF"])
        case "Daylight": return .init(background: .hex("F6F7FA"), foreground: .hex("24292F"), accent: .hex("0969DA"), palette: ["24292F","CF222E","116329","9A6700","0550AE","8250DF","1B7C83","6E7781","57606A","A40E26","1A7F37","8C6A00","0969DA","A475F9","3192AA","8C959F"])
        default: return .init(background: .hex("10141D"), foreground: .hex("D9E1F2"), accent: .hex("79D7B0"), palette: ["202837","F07F88","79D7B0","EAC58B","8BAEF4","BEA0F2","7DCEDE","D9E1F2","64738C","FFA0A7","9BEBC5","F5D9AA","ABC8FF","D6BEFF","A2E5EE","F6F8FC"])
        }
    }
}

extension NSColor {
    static func hex(_ value: String) -> NSColor {
        let n = UInt32(value, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
}
