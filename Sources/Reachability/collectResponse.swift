//
//  File.swift
//  Reachability
//
//  Created by Andrew on 04/11/2025.
//

import Foundation
import Synchronization

extension Reachability {


    /// 3 different ways to get a session response based on what tools are available.
    ///  the legacy method uses unchecked Sendable  to allow modification of variables soutside the completion handler (which cannot throw)
    internal func collectResponse(session: URLSession, request: URLRequest) async throws (URLError) -> URLResponse {
        do {
            return if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                /// The best result - we can use Swift Concurrency totally safely.
                try await session.data(for: request).1
            } else
            if #available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *) {
                /// The next best result - we can use continuations to execute the legacy dataTask  totally safely.
                try await dataTaskCompat(session: session, request: request)
            } else {
                /// Work as best we can - using an unchecked Sendable store inside the completion handler in order to appease the compiler,
                /// and use DispatchGroup semaphores to wait for task completion.
                try legacyGet(session: session, request: request)
            }
        } catch {
            throw error as? URLError ?? URLError(.unknown)
        }
    }


/// Compatibility helper for platforms/OS versions where URLSession.data(for:) isn't available,
    /// but CheckedContinuations are supported to bridge the completion handler to async/await
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    private func dataTaskCompat(session: URLSession, request: URLRequest) async throws -> URLResponse {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
            let task = session.dataTask(with: request) { _ , response, error in
                if let e = error as? URLError {
                    continuation.resume(throwing: e)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
    }

    nonisolated
    private func legacyGet(session: URLSession, request: URLRequest) throws -> URLResponse { //}, completion: @Sendable @escaping (Result<URLResponse, URLError>) -> Void) {
        // Create URL session data task
        let store = LegacyResponseStore()
        let d = DispatchGroup()
        d.enter()
        let task = session.dataTask(with: request) { _, response, error in
            /// This closure must not throw, and so we store any error for retrieval later.
            store.save(response, error)
            d.leave()
        }
        task.resume()
        d.wait() // == await for the d.leave() event.
        if let response = store.urlResponse {
            return response
        }
        else {
            throw store.urlError ?? URLError(.unknown)
        }
        /// In an ideal world, this would use a mutex, but it's raison d'etre is to handle old OS versions
        /// which sadly preclude the use of Mutex. C'est la vie. @unchecked it is.
        nonisolated
        final class LegacyResponseStore: @unchecked Sendable {
            private(set) var urlResponse: URLResponse?
            private(set) var urlError: (any Error)?
            func save(_ response: URLResponse?, _ error: (any Error)?) {
                urlResponse = response
                urlError = error
            }
        }
    }
}



