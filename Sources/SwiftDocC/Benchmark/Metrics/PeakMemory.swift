/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

extension Benchmark {
    /// A peak memory footprint metric for the current process.
    public class PeakMemory: BenchmarkMetric {
        public static let identifier = "peak-memory"
        public static let displayName = "Peak memory footprint (bytes)"
        
        private var memoryPeak: Double?
        
        /// Creates a new instance and fetches the peak memory usage.
        public init() {
            memoryPeak = Self.peakMemory()
        }
        
        #if os(macOS) || os(iOS)
        private static func peakMemory() -> Double? {
            // On macOS we use the Kernel framework to read a pretty accurate
            // memory footprint for the current task. The value reported here
            // is comparable to what Xcode displays in the debug memory gauge.
            var vmInfo = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
            let vmResult: kern_return_t = withUnsafeMutablePointer(to: &vmInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard vmResult == KERN_SUCCESS else { return nil }
            return Double(vmInfo.ledger_phys_footprint_peak)
        }
        
        #elseif os(Linux)
        private static func peakMemory() -> Double? {
            // On Linux we cannot use the Kernel framework, so we tap into the
            // kernel proc file system to read the vm peak reported in the process status.
            let statusFileURL = URL(fileURLWithPath: "/proc/self/status")

            guard let statusString = try? String(contentsOf: statusFileURL),
                let peakMemoryString = statusString.components(separatedBy: .newlines)
                    .first(where: { $0.hasPrefix("VmPeak") })?
                    .components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .filter({ !$0.isEmpty })
                    .first,
                let peakMemory = Double(peakMemoryString) else { return nil }

            return peakMemory * 1024 // convert from KBytes to bytes
        }
        #endif
        
        public var result: MetricValue? {
            return memoryPeak.map(MetricValue.number)
        }
    }
}
