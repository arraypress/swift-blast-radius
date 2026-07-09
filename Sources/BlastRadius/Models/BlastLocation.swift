//
//  BlastLocation.swift
//  SwiftBlastRadius
//
//  A single place a changed symbol is referenced.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// One reference to a changed symbol, found during impact analysis.
public struct BlastLocation: Sendable, Equatable {

    /// Project-relative path of the file containing the reference.
    public let file: String

    /// 1-based line number of the reference.
    public let line: Int

    /// The trimmed text of the referencing line.
    public let text: String

    /// Absolute path of the file (for opening / jumping).
    public let absPath: String

    /// Whether this reference lives in a test file.
    public let isTest: Bool

    public init(file: String, line: Int, text: String, absPath: String, isTest: Bool) {
        self.file = file
        self.line = line
        self.text = text
        self.absPath = absPath
        self.isTest = isTest
    }
}
