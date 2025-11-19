//
//  reachable.swift
//  Reachability
//
//  Created by Andrew on 19/11/2025.
//
import Foundation

extension Reachability {

    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    static func reachable(url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async -> ReachableResult {
        let startTime = DispatchTime.now()
        do {
            var isReachable = false

            /// Get httpResponse to a HEAD  method first
            var httpMethod = "HEAD"
            var response = try await getResponse(from: url, httpMethod: httpMethod, verbose: verbose, bytes: bytes, timeout: timeout)
            if (200...299).contains(response.code) || [401, 403].contains(response.code) {
                isReachable = true
            }

            // Fallback: some servers don't support HEAD; retry with GET on 405/501
            if !isReachable && [405, 501].contains(response.code) {
                httpMethod = "GET"
                response = try await getResponse(from: url, httpMethod: httpMethod, verbose: verbose, bytes: bytes, timeout: timeout)
                if (200...299).contains(response.code) || [401, 403].contains(response.code) {
                    isReachable = true
                }
            }

            let elapsed = elapsedMS(since: startTime)
            var description = isReachable ? "success" : "failed"
            if verbose {
                description += "\n\(response.code) received from \(response.httpMethod) request to \(response.finalURL)"
                description += "\nTime taken: \(elapsed.decimalString)ms\n"
            }
            return ReachableResult(reachable: isReachable, description: description, responseTime: elapsed,
                                   finalURL: response.finalURL, responseCode: response.code, size: response.size,  httpMethod: response.httpMethod)
        }
        catch {
            return ReachableResult(reachable: false, description: error.localizedDescription, responseTime: elapsedMS(since: startTime), finalURL: nil, responseCode: nil, size: -1, httpMethod: "")
        }
    }
    static func synchronousReachable(url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5)  -> ReachableResult {
        let startTime = DispatchTime.now()
        do {
            var isReachable = false

            /// Get httpResponse to a HEAD  method first
            var httpMethod = "HEAD"
            var response = try getSynchronousResponse(from: url, httpMethod: httpMethod, verbose: verbose, bytes: bytes, timeout: timeout)
            if (200...299).contains(response.code) || [401, 403].contains(response.code) {
                isReachable = true
            }

            // Fallback: some servers don't support HEAD; retry with GET on 405/501
            if !isReachable && [405, 501].contains(response.code) {
                httpMethod = "GET"
                response = try getSynchronousResponse(from: url, httpMethod: httpMethod, verbose: verbose, bytes: bytes, timeout: timeout)
                if (200...299).contains(response.code) || [401, 403].contains(response.code) {
                    isReachable = true
                }
            }

            let elapsed = elapsedMS(since: startTime)
            var description = isReachable ? "success" : "failed"
            if verbose {
                description += "\n\(response.code) received from \(response.httpMethod) request to \(response.finalURL)"
                description += "\nTime taken: \(elapsed.decimalString)ms\n"
            }
            return ReachableResult(reachable: isReachable, description: description, responseTime: elapsed,
                                   finalURL: response.finalURL, responseCode: response.code, size: response.size,  httpMethod: response.httpMethod)
        }
        catch {
            return ReachableResult(reachable: false, description: error.localizedDescription, responseTime: elapsedMS(since: startTime), finalURL: nil, responseCode: nil, size: -1, httpMethod: "")
        }
    }


    /// convert from Time Interval to Double
    static func elapsedMS(since startTime: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
    }
}
