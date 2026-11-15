import Darwin
import Foundation

/// Pure matching for “is Elder Scrolls Online running?” — Mac app names/bundle IDs and Wine/CrossOver
/// command lines that contain the game binary (`eso64.exe`), not the Steam or Bethesda launchers alone.
public enum GameRunningMatcher {
    /// True for a macOS app that is the game (or a wrapper whose name/bundle clearly is the game).
    public static func matchesMacApp(localizedName: String, bundleIdentifier: String) -> Bool {
        let name = localizedName.lowercased()
        let id = bundleIdentifier.lowercased()
        return name.contains("elder scrolls")
            || name == "eso"
            || name.hasPrefix("eso64")
            || id.contains("zenimax")
    }

    /// True when a process command line is the ESO client under Wine/CrossOver.
    /// Matches `eso64.exe` only — `steam.exe`, `Bethesda.net_Launcher`, and `Client.exe` (TTC) alone do not match.
    public static func matchesWineCommandLine(_ commandLine: String) -> Bool {
        let lower = commandLine.lowercased()
        // Normalize path separators so both `eso64.exe` and `eso64.EXE` with `\` or `/` match.
        return lower.contains("eso64.exe")
    }

    /// True when any Mac app or Wine command line indicates the game is running.
    public static func isGameRunning(
        macApps: [(localizedName: String, bundleIdentifier: String)],
        wineCommandLines: [String]
    ) -> Bool {
        if macApps.contains(where: { matchesMacApp(localizedName: $0.localizedName, bundleIdentifier: $0.bundleIdentifier) }) {
            return true
        }
        return wineCommandLines.contains { matchesWineCommandLine($0) }
    }
}

/// Reads other processes' command lines (KERN_PROCARGS2) for Wine/`eso64.exe` detection.
public enum ProcessCommandLines {
    /// Command lines for every process the caller can inspect. Best-effort; permission failures skip a pid.
    public static func all() -> [String] {
        var lines: [String] = []
        var length = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        guard sysctl(&mib, 4, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        let count = length / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &length, nil, 0) == 0 else { return [] }
        let n = length / MemoryLayout<kinfo_proc>.stride
        for i in 0..<n {
            let pid = procs[i].kp_proc.p_pid
            if pid > 0, let line = commandLine(pid: pid) {
                lines.append(line)
            }
        }
        return lines
    }

    /// One process's argv-style command line, or nil when unavailable.
    public static func commandLine(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        // KERN_PROCARGS2: int argc, then exec path, then argv strings separated by NUL.
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        // Skip exec path.
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        index += 1
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var args: [String] = []
        for _ in 0..<Int(argc) {
            guard index < buffer.count else { break }
            var end = index
            while end < buffer.count, buffer[end] != 0 { end += 1 }
            if end > index {
                let slice = buffer[index..<end].map { UInt8(bitPattern: $0) }
                args.append(String(decoding: slice, as: UTF8.self))
            }
            index = end + 1
        }
        guard !args.isEmpty else { return nil }
        return args.joined(separator: " ")
    }
}
