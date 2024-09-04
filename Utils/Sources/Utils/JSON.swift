// swiftlint:disable all
// https://github.com/swiftlang/swift-docc/blob/afa67522d282c52ee7c647bf6c2463215c0d7891/Sources/SwiftDocC/Infrastructure/Communication/Foundation/JSON.swift
/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

public indirect enum JSON: Codable, Equatable {
    case dictionary([String: JSON])
    case array([JSON])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .boolean(boolValue)
        } else if let numericValue = try? container.decode(Double.self) {
            self = .number(numericValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSON].self) {
            self = .array(arrayValue)
        } else {
            self = try .dictionary(container.decode([String: JSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .dictionary(dictionary):
            try container.encode(dictionary)
        case let .array(array):
            try container.encode(array)
        case let .string(string):
            try container.encode(string)
        case let .number(number):
            try container.encode(number)
        case let .boolean(boolean):
            try container.encode(boolean)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSON: CustomDebugStringConvertible {
    public var debugDescription: String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.prettyPrinted]
        }

        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8) ?? "JSON(error decoding UTF8 string)"
        } catch {
            return "JSON(error encoding description: '\(error.localizedDescription)')"
        }
    }
}

extension JSON {
    public subscript(key: Any) -> JSON? {
        if let array, let index = key as? Int, index < array.count {
            array[index]
        } else if let dic = dictionary, let key = key as? String, let obj = dic[key] {
            obj
        } else {
            nil
        }
    }

    /// Returns a `JSON` dictionary, if possible.
    public var dictionary: [String: JSON]? {
        switch self {
        case let .dictionary(dict):
            dict
        default:
            nil
        }
    }

    /// Returns a `JSON` array, if possible.
    public var array: [JSON]? {
        switch self {
        case let .array(array):
            array
        default:
            nil
        }
    }

    /// Returns a `String` value, if possible.
    public var string: String? {
        switch self {
        case let .string(value):
            value
        default:
            nil
        }
    }

    /// Returns a `Double` value, if possible.
    public var number: Double? {
        switch self {
        case let .number(number):
            number
        default:
            nil
        }
    }

    /// Returns a `Bool` value, if possible.
    public var bool: Bool? {
        switch self {
        case let .boolean(value):
            value
        default:
            nil
        }
    }
}

extension JSON {
    /// An integer coding key.
    struct IntegerKey: CodingKey {
        var intValue: Int?
        var stringValue: String

        init(_ value: Int) {
            intValue = value
            stringValue = value.description
        }

        init(_ value: String) {
            intValue = nil
            stringValue = value
        }

        init?(intValue: Int) {
            self.init(intValue)
        }

        init?(stringValue: String) {
            guard let intValue = Int(stringValue) else {
                return nil
            }

            self.intValue = intValue
            self.stringValue = stringValue
        }
    }
}

extension [String: JSON] {
    public var json: JSON {
        JSON.dictionary(self)
    }
}

extension [JSON] {
    public var json: JSON {
        JSON.array(self)
    }
}

extension String {
    public var json: JSON {
        JSON.string(self)
    }
}

extension BinaryInteger {
    public var json: JSON {
        JSON.number(Double(self))
    }
}

extension Bool {
    public var json: JSON {
        JSON.boolean(self)
    }
}
