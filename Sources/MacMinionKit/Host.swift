import Darwin
import Foundation

/// What this Mac can give a local model: the chip, all memory, and memory free right now.
public struct HostProfile: Sendable, Equatable {
    public let chip: String
    public let memoryBytes: UInt64
    /// Free, inactive, purgeable, and speculative pages: what a model can take without pushing apps out.
    public let availableBytes: UInt64
    public let performanceCores: Int

    public init(chip: String, memoryBytes: UInt64, availableBytes: UInt64, performanceCores: Int) {
        self.chip = chip; self.memoryBytes = memoryBytes; self.availableBytes = availableBytes
        self.performanceCores = performanceCores
    }

    public static func current() -> HostProfile {
        HostProfile(chip: sysctlString("machdep.cpu.brand_string") ?? "this Mac",
                    memoryBytes: ProcessInfo.processInfo.physicalMemory,
                    availableBytes: availableMemory() ?? ProcessInfo.processInfo.physicalMemory / 2,
                    performanceCores: sysctlInt("hw.perflevel0.physicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount)
    }

    /// "Apple M2 Ultra, 192 GB (120 GB free)".
    public var summary: String {
        let total = ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
        let free = ByteCountFormatter.string(fromByteCount: Int64(availableBytes), countStyle: .memory)
        return "\(chip), \(total) (\(free) free)"
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    static func availableMemory() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)
        return pages * UInt64(sysconf(_SC_PAGESIZE))
    }
}

/// How fast one model wrote on this Mac.
public struct ModelSpeed: Codable, Sendable, Equatable {
    public let tokensPerSecond: Double
    public let loadSeconds: Double
    public let measured: Date

    public init(tokensPerSecond: Double, loadSeconds: Double, measured: Date = .now) {
        self.tokensPerSecond = tokensPerSecond; self.loadSeconds = loadSeconds; self.measured = measured
    }
}
