import Foundation

public struct SSHEndpoint: Equatable {
    public let host: String
    public let user: String?
    public let port: Int?

    public var displayName: String {
        let name = host.contains(":") ? "[\(host)]" : host
        return (user.map { "\($0)@" } ?? "") + name + (port.flatMap { $0 == 22 ? nil : ":\($0)" } ?? "")
    }

    /// Reads only SSH arguments; it never loads configuration or runs ssh -G.
    public static func parse(arguments: [String]) -> SSHEndpoint? {
        guard let executable = arguments.first, URL(fileURLWithPath: executable).lastPathComponent == "ssh" else { return nil }
        let takesValue = Set("BbcDEeFIiJLlmOoPpQRSWw")
        var user: String?
        var port: Int?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { index += 1; break }
            guard argument.hasPrefix("-"), argument != "-" else { break }
            let flags = Array(argument.dropFirst())
            var flagIndex = 0
            while flagIndex < flags.count {
                let flag = flags[flagIndex]
                // Configuration queries and control operations are not remote sessions.
                if "GVQO".contains(flag) { return nil }
                if takesValue.contains(flag) {
                    let value: String
                    if flagIndex + 1 < flags.count { value = String(flags[(flagIndex + 1)...]) }
                    else {
                        index += 1
                        guard index < arguments.count else { return nil }
                        value = arguments[index]
                    }
                    if flag == "l" { user = value }
                    if flag == "p" { port = Int(value) }
                    if flag == "o" {
                        let pieces = value.split(maxSplits: 1, whereSeparator: { $0 == "=" || $0.isWhitespace })
                        if pieces.count == 2 && pieces[0].lowercased() == "user" { user = String(pieces[1]).trimmingCharacters(in: .whitespaces) }
                    }
                    break
                }
                flagIndex += 1
            }
            index += 1
        }
        guard index < arguments.count else { return nil }
        let destination = arguments[index]
        let host: String
        if destination.hasPrefix("ssh://") {
            guard let url = URLComponents(string: destination), let hostname = url.host else { return nil }
            host = hostname.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            user = user ?? url.user
            port = port ?? url.port
        } else {
            let parts = destination.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { user = user ?? String(parts[0]) }
            host = String(parts.last ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        guard !host.isEmpty, !host.hasPrefix("-"), !host.contains("/"),
              !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              user?.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) != true else { return nil }
        return SSHEndpoint(host: host, user: user, port: port)
    }
}

public struct WorkingDirectoryReport: Equatable {
    public let host: String?
    public let path: String

    public static func parse(_ value: String?) -> WorkingDirectoryReport? {
        guard let value, value.utf8.count <= 16_384 else { return nil }
        let host: String?
        let path: String
        if value.hasPrefix("/") { host = nil; path = value }
        else {
            guard let url = URLComponents(string: value), url.scheme?.lowercased() == "file",
                  url.user == nil, url.password == nil, url.port == nil else { return nil }
            host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            path = url.path
        }
        guard path.hasPrefix("/"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              host?.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) != true else { return nil }
        return WorkingDirectoryReport(host: host, path: path)
    }
}
