//
//  Response.swift
//  Reachability
//
//  Created by Andrew on 19/11/2025.
//


import Foundation

extension Reachability {

    /// The response below is returned to the caller (but is not passed back to the client)
    internal struct Response {
        let code: Int       // code to indicate success or varying degrees of failure
        let httpMethod: String // Head or Get
        let finalURL: String // The final URL after redirects
        let size: Int // The expected content length reported by the response
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
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    static func getResponse(from url: URL, httpMethod: String = "HEAD", verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) async throws (ReachabilityError) -> Response {
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
        let sizeOfResponseBody: Int = Int(httpResponse.allHeaderFields["Content-Length"] as? String ?? "0") ?? 0
        let finalUrlString = httpResponse.url?.absoluteString ?? url.absoluteString
        return Response(code: httpResponse.statusCode, httpMethod: httpMethod, finalURL: finalUrlString, size: sizeOfResponseBody)
    }

    static func getSynchronousResponse(from url: URL, httpMethod: String = "HEAD", verbose: Bool = false, bytes: Int = 64, timeout: Double = 2.5) throws (ReachabilityError) -> Response {
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
            response = try collectSynchronousResponse(session: urlSession, request: request)
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
        let sizeOfResponseBody: Int = Int(httpResponse.allHeaderFields["Content-Length"] as? String ?? "0") ?? 0
        let finalUrlString = httpResponse.url?.absoluteString ?? url.absoluteString
        return Response(code: httpResponse.statusCode, httpMethod: httpMethod, finalURL: finalUrlString, size: sizeOfResponseBody)
    }
}
