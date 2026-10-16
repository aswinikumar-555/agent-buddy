// This Mac: CPU load, memory in use, and free disk space. Read from the kernel
// (host_statistics) and the file system; nothing leaves the Mac.
import Darwin
import Foundation

struct SystemStats: Equatable {
    var cpu: Double = 0            // 0…1, all cores together
    var memUsed: Double = 0        // bytes in use (app memory + wired + compressed)
    var memTotal: Double = 0
    var diskFree: Double = 0       // bytes free for new files
    var diskTotal: Double = 0

    var memFraction: Double { memTotal > 0 ? memUsed / memTotal : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? 1 - diskFree / diskTotal : 0 }

    static func gb(_ bytes: Double) -> String {
        let g = bytes / 1_073_741_824
        return g >= 100 ? String(format: "%.0f GB", g) : String(format: "%.1f GB", g)
    }
}

/// Keeps the previous CPU tick counts, since CPU load is the change between two readings.
final class SystemMonitor {
    private var lastTicks: (busy: UInt64, total: UInt64)?

    func read() -> SystemStats {
        var s = SystemStats()
        s.cpu = cpuLoad()
        (s.memUsed, s.memTotal) = memory()
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            s.diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            s.diskTotal = Double(v.volumeTotalCapacity ?? 0)
        }
        return s
    }

    private func cpuLoad() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard ok == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice, total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return 0 }
        return Double(busy - last.busy) / Double(total - last.total)
    }

    private func memory() -> (used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard ok == KERN_SUCCESS else { return (0, total) }
        let page = Double(vm_kernel_page_size)
        // What Activity Monitor calls "Memory Used": app memory + wired + compressed.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }
}
