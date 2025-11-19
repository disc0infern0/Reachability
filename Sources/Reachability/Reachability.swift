//  Reachability.swift
//
import Foundation

/// Helper type containing methods for testing web presence
/// Key design:
///     can be called from any OS, including those that don't support async context
///     maintains no state
///     performs no I/O whatsoever, leaving that to caller
///     defines two versions of checkReachable that takes either a URL or a urlString

@MainActor
public struct Reachability: Sendable  {

    /// Simple Boolean result:
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public static func isReachable(_ url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async  -> Bool {
        await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout).reachable
    }
    @available(iOS, deprecated: 13.0, message: "Use async version")
    @available(macOS, deprecated: 10.15, message: "Use async version")
    @available(tvOS, deprecated: 13.0, message: "Use async version")
    @available(watchOS, deprecated: 6.0, message: "Use async version")
    public static func isReachable(_ url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5)  -> Bool {
        synchronousReachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout).reachable
    }
    /// The return type:
    public nonisolated struct ReachableResult: Equatable, Sendable, CustomStringConvertible {

        public let reachable: Bool
        public let description: String
        public let responseTime: Double?
        public let finalURL: String?
        public let responseCode: Int?
        public let size: Int
        public let httpMethod: String // Head or Get
    }


    /// Public API to check if a URL  is reachable.
    /// - Parameters:
    ///   - url: A prevalidated non optional  URL  to check.
    ///   - verbose: If true, returns a descriptive message with timings, else returns "success" for reachable.
    ///   - bytes: Number of bytes to request in GET request range header (default 64).
    ///   - timeout: Timeout for the request in seconds (default 2.5).
    /// - Throws: Throws on failure. The error.localizedDescription will contain details of why the failure occurred.
    /// - Returns: ``ReachableResult``



    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public static func checkReachable(_ url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async  -> ReachableResult {
        await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
    }

    @available(iOS, deprecated: 13.0, message: "Use async version")
    @available(macOS, deprecated: 10.15, message: "Use async version")
    @available(tvOS, deprecated: 13.0, message: "Use async version")
    @available(watchOS, deprecated: 6.0, message: "Use async version")
    public static func checkReachable(_ url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5)  -> ReachableResult {

        synchronousReachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
    }

    /// Public API to check if a URL  is reachable.
    /// - Parameters:
    ///   - urlString: The URL string to check.
    ///   - verbose: If true, returns a descriptive message with timings, else returns "success" for reachable.
    ///   - bytes: Number of bytes to request in GET request range header (default 64).
    ///   - timeout: Timeout for the request in seconds (default 2.5).
    /// - Throws: Throws on failure. The error.localizedDescription will contain details of why the failure occurred.
    /// - Returns: ``ReachableResult``
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public static func checkReachable(_ urlString: String, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async -> ReachableResult {
        do {
            var urlString = urlString
            let url = try makeURL(&urlString, bytes: bytes, timeout: timeout)
            return  await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
        } catch {
            return ReachableResult(reachable: false, description: error.localizedDescription, responseTime: nil, finalURL: nil, responseCode: nil, size: -1, httpMethod: "")
        }
    }

    public static func checkSynchronouslyReachable(_ urlString: String, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5)  -> ReachableResult {
        do {
            var urlString = urlString
            let url = try makeURL(&urlString, bytes: bytes, timeout: timeout)
            return synchronousReachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
        } catch {
            return ReachableResult(reachable: false, description: error.localizedDescription, responseTime: nil, finalURL: nil, responseCode: nil, size: -1, httpMethod: "")
        }
    }

}

