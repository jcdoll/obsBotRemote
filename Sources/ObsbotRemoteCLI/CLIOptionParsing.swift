import Foundation
import ObsbotRemoteCore

func parseUInt8(_ text: String, option: String) throws -> UInt8 {
  let value = try parseInteger(text)
  guard let narrowed = UInt8(exactly: value) else {
    throw CLIError("\(option) must fit in 8 bits")
  }
  return narrowed
}

func parseUInt16(_ text: String, option: String) throws -> UInt16 {
  let value = try parseInteger(text)
  guard let narrowed = UInt16(exactly: value) else {
    throw CLIError("\(option) must fit in 16 bits")
  }
  return narrowed
}

func parseSignedInteger(_ text: String, option: String) throws -> Int {
  guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    throw CLIError("\(option) must be an integer")
  }
  return value
}

func parseBoundedInteger(
  _ text: String,
  option: String,
  minimum: Int,
  maximum: Int
) throws -> Int {
  let value = try parseSignedInteger(text, option: option)
  guard value >= minimum, value <= maximum else {
    throw CLIError("\(option) must be between \(minimum) and \(maximum)")
  }
  return value
}

func parseInt32(_ text: String, option: String) throws -> Int32 {
  let value = try parseSignedInteger(text, option: option)
  guard let narrowed = Int32(exactly: value) else {
    throw CLIError("\(option) must fit in 32 bits")
  }
  return narrowed
}
