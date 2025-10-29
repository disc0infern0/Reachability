//
//  ReachabilityError.swift
//  Reachability
//
//  Created by Andrew on 22/10/2025.
//
import Foundation

public enum ReachabilityError: LocalizedError {
    case url(String)
    case components(String)
    case count
    case bytes
    case timeoutValue, timedOut
    case prefix
    case host, hostNotFound, hostUnreachable
    case unexpected
    case unreachable(String)
    case noInput
    case message(String)

    public var errorDescription: String? {
        return switch self {
            case .url(let urlString): "\(urlString) is an invalid URL"
            case .components(let urlString): "Invalid components within \(urlString)"
            case .count: "Please specify a zero (for indefinite repeats) or higher value for the 'count' of times to repeat the check."
            case .bytes: "Please specify a non-negative value for the 'bytes'."
            case .timeoutValue: "Please specify a non-negative value for the 'timeout'."
            case .timedOut: "Connection timed out"
            case .prefix: "The url prefix must be http:// or https://"
            case .host: "No host, or invalid host, specified in the URL"
            case .hostNotFound: "Cannot find host"
            case .hostUnreachable: "Cannot connect to host"
            case .unexpected: "Unexpected error. Please report this as a bug."
            case .message(let msg): "\(msg)"
            case .unreachable (let errmsg): "Supplied URL is valid, but is currently unreachable:\n\(errmsg)\n"
            case .noInput: "No input supplied. exiting."
        }
    }
}
