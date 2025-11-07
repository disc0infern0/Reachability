//  Reachability.swift
//
import Foundation

/// Helper functions for network testing of url strings
/// Key design:
///     must be called from async context
///     maintains no state
///     performs no I/O whatsoever, leaving that to caller
///     defines two versions of checkReachable that takes either a URL or a urlString
@MainActor
public struct Reachability: Sendable  {

    /// Public API to check if a URL  is reachable.
    /// - Parameters:
    ///   - url: A prevalidated non optional  URL  to check.
    ///   - verbose: If true, returns a descriptive message with timings, else returns "success" for reachable.
    ///   - bytes: Number of bytes to request in GET request range header (default 64).
    ///   - timeout: Timeout for the request in seconds (default 2.5).
    /// - Throws: Throws on failure. The error.localizedDescription will contain details of why the failure occurred.
    /// - Returns: String "success" or verbose message.

    public func checkReachable(_ url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async  -> ReachableResult {
        await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
    }

    /// Public API to check if a URL  is reachable.
    /// - Parameters:
    ///   - urlString: The URL string to check.
    ///   - verbose: If true, returns a descriptive message with timings, else returns "success" for reachable.
    ///   - bytes: Number of bytes to request in GET request range header (default 64).
    ///   - timeout: Timeout for the request in seconds (default 2.5).
    /// - Throws: Throws on failure. The error.localizedDescription will contain details of why the failure occurred.
    /// - Returns: String "success" or verbose message.
    public func checkReachable(_ urlString: String, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async -> ReachableResult {
        do {
            var urlString = urlString
            let url = try makeURL(&urlString, bytes: bytes, timeout: timeout)
            return  await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
        } catch {
            return ReachableResult(reachable: false, description: error.localizedDescription, responseTime: nil, finalURL: nil, responseCode: nil)
        }
    }

    public nonisolated struct ReachableResult: Equatable, Sendable, CustomStringConvertible {
        public let reachable: Bool
        public let description: String
        public let responseTime: Double?
        public let finalURL: String?
        public let responseCode: Int?
    }

    public init() {}

    /// Validate the input URL string and creates a URL.
    /// It adds https:// if missing scheme, enforces http or https scheme, validates bytes and timeout arguments
    /// Throws ReachabilityError on any validation failure.
    func makeURL(_ urlString: inout String, bytes: Int, timeout: Double) throws (ReachabilityError) -> Foundation.URL {
        if urlString.isEmpty {
            throw ReachabilityError.noInput
        }

        guard bytes >= 0 else {
            throw ReachabilityError.bytes
        }

        guard timeout >= 0 else {
            throw ReachabilityError.timeoutValue
        }

        guard let url = Foundation.URL(string: urlString) else {
            throw ReachabilityError.url(urlString)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ReachabilityError.components(urlString)
        }

        // If a valid http scheme, e.g. https:// , has not been supplied, add it
        guard let scheme = components.scheme, !scheme.isEmpty else {
            urlString = "https://\(urlString)"
            return try makeURL(&urlString, bytes: bytes, timeout: timeout)
        }

        guard scheme.hasPrefix("http") else { throw ReachabilityError.prefix }

        guard let host = components.host, !host.isEmpty else {
            throw ReachabilityError.host
        }

        return url
    }

    func reachable(url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async -> ReachableResult {
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
            return ReachableResult(reachable: isReachable, description: description, responseTime: elapsed, finalURL: response.finalURL, responseCode: response.code)
        }
        catch {
            return ReachableResult(reachable: false, description: error.localizedDescription, responseTime: elapsedMS(since: startTime), finalURL: nil, responseCode: nil)
        }
    }

    /// convert from Time Interval to Double
    func elapsedMS(since startTime: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
    }

    struct Response {
        let code: Int       // code to indicate success or varying degrees of failure
        let httpMethod: String // Head or Get
        let finalURL: String // The final URL after redirects
    }

    /// getResponse
    ///
    /// Query a given URL and return a code/message describing the server response, following redirects and optionally requesting only a small byte range.
    ///
    /// - Parameters:
    ///   - url: The URL to query.
    ///   - httpMethod: The HTTP method to use (default "HEAD"). Falls back to "GET" when the caller requests it.
    ///   - verbose: If true, the returned Response.message contains a descriptive sentence; otherwise it is "success" on reachable responses.
    ///   - bytes: Number of bytes to request via the Range header when using GET (default 64). Ignored for HEAD.
    ///   - timeout: Timeout interval in seconds for the request (default 2.5).
    /// - Throws: `ReachabilityError` describing network or validation failures, or unexpected response conditions.
    /// - Returns: A `Response` containing the HTTP status `code`, a human-readable `message`, and the `finalURL` after following redirects.
    func getResponse(from url: URL, httpMethod: String = "HEAD", verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async throws (ReachabilityError) -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.timeoutInterval = timeout
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if httpMethod == "GET" {
            /// Ask for the specified number of bytes of the body if doing a GET request.
            request.setValue("bytes=0-\(bytes)", forHTTPHeaderField: "Range")
        }

        // Create a session that follows redirects and preserves the request method.
        let delegate = RedirectPreservingDelegate(originalMethod: httpMethod)
        let urlSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        let response: URLResponse
        do {
            response = try await collectResponse(session: urlSession, request: request)
        }
        catch { /// Only need to catch and diagnose URLError type
            switch error.code {
                case .timedOut: throw ReachabilityError.timedOut
                case .dnsLookupFailed, .cannotFindHost: throw ReachabilityError.hostNotFound
                case .cannotConnectToHost: throw ReachabilityError.hostUnreachable
                case .notConnectedToInternet: throw ReachabilityError.message("not connected to the Internet")
                case .networkConnectionLost: throw ReachabilityError.message("network connection lost")
                case .secureConnectionFailed: throw ReachabilityError.message("secure connection failed")
                case .unknown: throw ReachabilityError.message("Unknown network error when contacting \(url.absoluteString)")
                case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
                    throw ReachabilityError.message("TLS/Certificate error")
                default:
                    throw ReachabilityError.message("Network error \(error.errorCode) from \(url.absoluteString): \(error.localizedDescription)")
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReachabilityError.unexpected
        }
        let finalUrlString = httpResponse.url?.absoluteString ?? url.absoluteString
        return Response(code: httpResponse.statusCode, httpMethod: httpMethod, finalURL: finalUrlString)
    }

}

extension Double {
    /// String representation limited to two decimal places.
    public var decimalString: String {
        self.decimalString( decimalPlaces: 2)
    }
    /// String representation limited to the specified number of decimal places.
    func decimalString(decimalPlaces: Int = 2) -> String {
        /// Use NumberFormatter to create %.2f format, instead of the String(format: ) function, which is apparently "unsafe" as of Swift 6.2
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimalPlaces
        return formatter.string(from: NSNumber(value: self)) ?? "0.\(String(repeating: "0", count: decimalPlaces))"
    }
}
