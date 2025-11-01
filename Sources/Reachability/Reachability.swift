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

    public func checkReachable(_ url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async throws -> String {
        try await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
    }

    /// Public API to check if a URL  is reachable.
    /// - Parameters:
    ///   - urlString: The URL string to check.
    ///   - verbose: If true, returns a descriptive message with timings, else returns "success" for reachable.
    ///   - bytes: Number of bytes to request in GET request range header (default 64).
    ///   - timeout: Timeout for the request in seconds (default 2.5).
    /// - Throws: Throws on failure. The error.localizedDescription will contain details of why the failure occurred.
    /// - Returns: String "success" or verbose message.
    public func checkReachable(_ urlString: String, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async throws -> String {
        var urlString = urlString
        let url = try makeURL(&urlString, bytes: bytes, timeout: timeout)
        return  try await reachable(url: url, verbose: verbose, bytes: bytes, timeout: timeout)
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

    func reachable(url: URL, verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async throws -> String {
        var isReachable = false

        let startTime = DispatchTime.now()

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

        if isReachable {
            return verbose ? response.message + " in \(elapsedMS(since: startTime))ms" : response.message
        }
        var message = "failed. Received \(response.code) from \(response.finalURL)"
        if verbose {
            message += " in \(elapsedMS(since: startTime))ms"
        }
        throw ReachabilityError.unreachable(message)
    }

    /// Use NumberFormatter to create %.2f format, instead of the String(format: ) function, which is apparently "unsafe" as of Swift 6.2
    func elapsedMS(since startTime: DispatchTime) -> String {
        let now = DispatchTime.now()
        let elapsedMS =  Double(now.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: elapsedMS)) ?? "0.00"
    }

    struct Response {
        let code: Int       // code to indicate success or varying degrees of failure
        let message: String // Messages to be passed back to the caller
        let finalURL: String // The final URL after redirects
        init(_ code: Int, _ message: String = "", finalURL: String) {
            self.code = code
            self.message = message
            self.finalURL = finalURL
        }
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
        let message: String
        if verbose {
            message = "\(httpMethod) request to \(finalUrlString) received a \(httpResponse.statusCode) response"
        } else {
            message = "success"
        }
        return Response(httpResponse.statusCode, message, finalURL: finalUrlString)
    }


    /// 3 different ways to get a session response based on what tools are available.
    ///  the legacy method is isolated to the main actor in order to allow modification of variables soutside the completion handler (which cannot throw)
    private func collectResponse(session: URLSession, request: URLRequest) async throws (URLError) -> URLResponse {
        var response: URLResponse?
        do {
            //            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            //                (_, response) = try await session.data(for: request)
            //            } else
            //            if #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) {
            //                response = try await dataTaskCompat(session: session, request: request)
            //            } else {
            // Legacy separated out to run on MainActor
            response = try await legacy()
            //            }
            guard let response else {
                throw URLError(.unknown)
            }
            return response
        }
        catch let urlError as URLError {
            throw urlError
        }
        catch {
            print("unknown")
            throw URLError(.unknown)
        }

        // Assumes settings set to default MainActor
        func legacy() async throws  -> URLResponse? {

            LegacyResponse.shared.reset()
            await Self.legacyGet(request: request) { result in
                /// This closure must be Sendable
                switch result {
                    case .success(let response):
                        DispatchQueue.main.async { LegacyResponse.shared.setResponse( response ) }
                    case .failure(let error):
                        DispatchQueue.main.async { LegacyResponse.shared.setError( error ) }
                }
            }
            while !LegacyResponse.shared.isCompleted {}
            if let e = LegacyResponse.shared.urlError {
                throw e
            }
            if let r = LegacyResponse.shared.urlResponse {
                return r
            }
            print("\(LegacyResponse.shared.urlResponse.debugDescription)  and \(LegacyResponse.shared.urlError.debugDescription)")
            print("isCompleted: \(LegacyResponse.shared.isCompleted)")
            print("unknown error :S ")
            throw URLError(.unknown)
        }


    }
    static func legacyGet(request: URLRequest, completion: @Sendable @escaping (Result<URLResponse, URLError>) -> Void) async {


        // Create URL session data task
        let task = URLSession.shared.dataTask(with: request) { _, response, error in

            if let error = error as? URLError {
                completion(.failure(error))
                return
            }

            guard let response = response else {
                completion(.failure(URLError(.unknown)))
                return
            }
            completion(.success(response))

        }
        task.resume()
    }
    /// Compatibility helper for platforms/OS versions where URLSession.data(for:) isn't available,
    /// but CheckedContinuations are supported to bridge the completion handler to async/await
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    private func dataTaskCompat(session: URLSession, request: URLRequest) async throws -> URLResponse {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
            let task = session.dataTask(with: request) { _ , response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
    }

}


@MainActor
final class LegacyResponse {
    var urlResponse: URLResponse?
    var urlError: URLError?
    private var isDone: Bool = false
    static let shared = LegacyResponse()
    init() {}
    func reset() {
        urlResponse = nil
        urlError = nil
        isDone = false
    }
    func setResponse(_ response: URLResponse) {
        urlResponse = response
        isDone = true
    }
    func setError(_ error: URLError) {
        urlError = error
        isDone = true
    }
    var isCompleted: Bool { isDone }
}
