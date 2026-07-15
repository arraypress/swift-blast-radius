//
//  SymbolImpact.swift
//  SwiftBlastRadius
//
//  The ripple of one changed symbol: its callers and covering tests.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// The impact of a single changed symbol across a project.
public struct SymbolImpact: Sendable, Equatable {

    /// The changed symbol's name.
    public let symbol: String

    /// References in non-test source files.
    public let callers: [BlastLocation]

    /// References in test files.
    public let tests: [BlastLocation]

    /// Creates an impact record.
    public init(symbol: String, callers: [BlastLocation], tests: [BlastLocation]) {
        self.symbol = symbol
        self.callers = callers
        self.tests = tests
    }
}
