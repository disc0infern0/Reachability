//
//  RedirectPreservingDelegate.swift
//  Reachability
//
//  Created by Andrew on 29/10/2025.
//

import Foundation

/// URLSession delegate that preserves the original HTTP method and headers across redirects.
/// Some servers and default URL loading behaviors may change the method to GET on certain redirects
/// (such as 301/302/303). This delegate ensures the session continues with the original method
/// and attempts to carry over headers and body when appropriate.
final class RedirectPreservingDelegate: NSObject, URLSessionTaskDelegate {
    private let originalMethod: String

    init(originalMethod: String) {
        self.originalMethod = originalMethod
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Make a mutable copy of the proposed redirect request
        var newRequest = request

        switch response.statusCode {
            case 301, 302, 303:
                // Switch to GET per common redirect semantics
                newRequest.httpMethod = "GET"
                newRequest.httpBody = nil
                newRequest.httpBodyStream = nil
            default:
                // Default to preserving the original method
                newRequest.httpMethod = originalMethod
                // If the original request had a body, attempt to carry it over
                if let originalBody = task.originalRequest?.httpBody {
                    newRequest.httpBody = originalBody
                } else if let originalBodyStream = task.originalRequest?.httpBodyStream, newRequest.httpBody == nil {
                    newRequest.httpBodyStream = originalBodyStream
                }
        }

        // Optionally carry forward non security headers from the proposed request
        let sameOrigin = task.originalRequest?.url?.host == request.url?.host
        if let headers = request.allHTTPHeaderFields {
            // Before applying headers, check hosts match and not copying a security field
            for (key, value) in headers {
                if !sameOrigin, ["Authorization", "Cookie"].contains(key) {
                    continue
                }
                newRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        // If method is GET, scrub body-specific headers
        if newRequest.httpMethod == "GET" {
            newRequest.setValue(nil, forHTTPHeaderField: "Content-Type")
            newRequest.setValue(nil, forHTTPHeaderField: "Content-Length")
        }

        completionHandler(newRequest)
    }
}

