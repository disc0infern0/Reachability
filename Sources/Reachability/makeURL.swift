//
//  makeURL.swift
//  Reachability
//
//  Created by Andrew on 19/11/2025.
//
import Foundation

extension Reachability {
    /// Validate the input URL string and creates a URL.
    /// It adds https:// if missing scheme, enforces http or https scheme, validates bytes and timeout arguments
    /// Throws ReachabilityError on any validation failure.
    static func makeURL(_ urlString: inout String, bytes: Int, timeout: Double) throws (ReachabilityError) -> Foundation.URL {
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
}
