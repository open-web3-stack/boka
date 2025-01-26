// swiftlint:disable all
// https://github.com/swiftlang/swift-docc/blob/afa67522d282c52ee7c647bf6c2463215c0d7891/Sources/SwiftDocC/Infrastructure/Communication/Foundation/AnyCodable.swift
/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// A type-erased codable value.
///
/// An `AnyCodable` value forwards encoding and decoding operations to the underlying base.
public struct AnyCodable: Codable, CustomDebugStringConvertible, Sendable {
    /// The base encodable value.
    public var value: Encodable & Sendable

    /// Creates a codable value that wraps the given base.
    public init(_ encodable: Encodable & Sendable) {
        value = encodable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = JSON.null
        } else {
            value = try container.decode(JSON.self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }

    public var debugDescription: String {
        String(describing: value)
    }
}
