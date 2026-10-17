import Darwin
import Foundation
import TildaCore

struct SSHProcess: Equatable {
    let pid: Int32
    let endpoint: SSHEndpoint?
}

enum ProcessContext {
    static func foregroundSSH(shellPID: Int32, terminalFD: Int32, previous: SSHProcess?) -> SSHProcess? {
        let group = tcgetpgrp(terminalFD)
        guard group > 0 else { return nil }

        func inspect(_ pid: Int32) -> SSHProcess? {
            guard getpgid(pid) == group, executableName(pid) == "ssh" else { return nil }
            if let previous, previous.pid == pid, previous.endpoint != nil { return previous }
            guard var arguments = arguments(pid) else { return SSHProcess(pid: pid, endpoint: nil) }
            // The executable path, rather than a potentially customized argv[0],
            // identifies the client. Only its arguments are used for the label.
            guard !arguments.isEmpty else { return SSHProcess(pid: pid, endpoint: nil) }
            arguments[0] = "ssh"
            guard let endpoint = SSHEndpoint.parse(arguments: arguments) else { return nil }
            return SSHProcess(pid: pid, endpoint: endpoint)
        }

        if let ssh = inspect(shellPID) { return ssh }
        // Ignore background connections when the local shell owns the terminal.
        guard group != shellPID else { return nil }
        if let ssh = inspect(group) { return ssh }
        // Pipelines and wrappers can put SSH behind another foreground process.
        var queue = children(shellPID)
        var visited = Set<Int32>()
        while !queue.isEmpty && visited.count < 128 {
            let pid = queue.removeFirst()
            guard visited.insert(pid).inserted else { continue }
            if let ssh = inspect(pid) { return ssh }
            queue.append(contentsOf: children(pid))
        }
        return nil
    }

    private static func executableName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let size = UInt32(buffer.count)
        guard proc_pidpath(pid, &buffer, size) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    private static func children(_ pid: Int32) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 128)
        let size = Int32(buffer.count * MemoryLayout<Int32>.size)
        guard proc_listchildpids(pid, &buffer, size) > 0 else { return [] }
        return buffer.filter { $0 > 0 }
    }

    private static func arguments(_ pid: Int32) -> [String]? {
        var mib = [Int32(CTL_KERN), Int32(KERN_PROCARGS2), pid]
        var size = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size < 4 { size = 262_144 }
        guard size <= 1_048_576 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0, size > 4 else { return nil }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0, count < 16_384 else { return nil }
        var cursor = MemoryLayout<Int32>.size
        while cursor < size && bytes[cursor] != 0 { cursor += 1 } // executable path
        while cursor < size && bytes[cursor] == 0 { cursor += 1 } // padding
        var result: [String] = []
        for _ in 0..<count {
            let start = cursor
            while cursor < size && bytes[cursor] != 0 { cursor += 1 }
            guard cursor < size else { return nil }
            result.append(String(decoding: bytes[start..<cursor], as: UTF8.self))
            cursor += 1
        }
        // Do not read the environment strings following argv.
        return result
    }
}
