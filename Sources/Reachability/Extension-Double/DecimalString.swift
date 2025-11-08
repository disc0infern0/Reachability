//
//  File.swift
//  Reachability
//
//  Created by Andrew on 08/11/2025.
//

import Foundation

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
