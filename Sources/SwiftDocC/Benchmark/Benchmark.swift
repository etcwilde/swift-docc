/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// A logger that runs benchmarks and stores the results.
public class Benchmark: Encodable {
    /// True if the process is supposed to run benchmarks.
    public let isEnabled: Bool
    
    /// If defined, filter the metrics to log with that value.
    public let metricsFilter: String?
    
    /// Creates a new benchmark log that can store metric results.
    /// - Parameters:
    ///   - isEnabled: If `true`, store metrics in the data model.
    ///   - metricsFilter: If set, filter the logged metrics with this string.
    ///   If `nil`, all metrics are stored in the log.
    init(isEnabled: Bool = true, metricsFilter: String? = nil) {
        self.isEnabled = isEnabled
        self.metricsFilter = metricsFilter
    }
    
    /// The shared instance to use for logging.
    public static let main: Benchmark = Benchmark(
        isEnabled: ProcessInfo.processInfo.environment["DOCC_BENCHMARK"] == "YES",
        metricsFilter: ProcessInfo.processInfo.environment["DOCC_BENCHMARK_FILTER"]
    )

    /// The benchmark timestamp.
    public let date = Date()

    /// The benchmark platform name.
    #if os(macOS)
    public let platform = "macOS"
    #elseif os(iOS)
    public let platform = "iOS"
    #elseif os(Linux)
    public let platform = "Linux"
    #else
    public let platform = "unsupported"
    #endif

    /// The list of metrics included in this benchmark.
    public var metrics: [BenchmarkMetric] = []
    
    enum CodingKeys: String, CodingKey {
        case date, metrics, arguments, platform
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        try container.encode(dateFormatter.string(from: date), forKey: .date)

        let arguments = Array(CommandLine.arguments.dropFirst())
        try container.encode(arguments, forKey: .arguments)

        try container.encode(platform, forKey: .platform)

        let metrics = self.metrics.compactMap { log -> BenchmarkResult? in
            guard let result = log.result else {
                return nil
            }
            let id = (log as? DynamicallyIdentifiableMetric)?.identifier ?? type(of: log).identifier
            let displayName = (log as? DynamicallyIdentifiableMetric)?.displayName ?? type(of: log).displayName
            return BenchmarkResult(identifier: id, displayName: displayName, result: result)
        }
        try container.encode(metrics, forKey: .metrics)
    }
}

private extension Benchmark {
    func shouldLogMetricType(_ metricType: BenchmarkMetric.Type) -> Bool {
        return isEnabled && (metricsFilter == nil || metricType.identifier.hasPrefix(metricsFilter!))
    }
}

/// Logs a one-off metric value.
/// - Parameter event: The metric to add to the log.
public func benchmark<E>(add event: @autoclosure () -> E, benchmarkLog log: Benchmark = .main) where E: BenchmarkMetric {
    guard log.shouldLogMetricType(E.self) else { return }

    log.metrics.append(event())
}

/// Starts the given metric.
/// - Parameter event: The metric to start.
public func benchmark<E>(begin event: @autoclosure () -> E, benchmarkLog log: Benchmark = .main) -> E? where E: BenchmarkBlockMetric {
    guard log.shouldLogMetricType(E.self) else { return nil }

    let event = event()
    event.begin()
    return event
}

/// Ends the given metric and adds it to the log.
/// - Parameter event: The metric to end and log.
public func benchmark<E>(end event: @autoclosure () -> E?, benchmarkLog log: Benchmark = .main) where E: BenchmarkBlockMetric {
    guard log.shouldLogMetricType(E.self), let event = event() else { return }

    event.end()
    log.metrics.append(event)
}

/// Ends the given metric and adds it to the log.
/// - Parameter event: The metric to end and log.
@discardableResult
public func benchmark<E, Result>(wrap event: @autoclosure () -> E, benchmarkLog log: Benchmark = .main, body: () throws -> Result) rethrows -> Result where E: BenchmarkBlockMetric {
    if log.shouldLogMetricType(E.self) {
        let event = event()
        event.begin()
        let result = try body()
        event.end()
        log.metrics.append(event)
        return result
    } else {
        return try body()
    }
}
