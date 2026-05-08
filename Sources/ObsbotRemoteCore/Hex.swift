import Foundation

public enum ParseError: Error, Equatable {
    case invalidInteger(String)
}

public func parseInteger(_ text: String) throws -> UInt32 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let radix: Int
    let digits: Substring

    if trimmed.lowercased().hasPrefix("0x") {
        radix = 16
        digits = trimmed.dropFirst(2)
    } else {
        radix = 10
        digits = Substring(trimmed)
    }

    guard !digits.isEmpty, let value = UInt32(digits, radix: radix) else {
        throw ParseError.invalidInteger(text)
    }
    return value
}

public func formatHex(_ value: UInt32, width: Int = 4) -> String {
    let raw = String(value, radix: 16, uppercase: true)
    return "0x" + String(repeating: "0", count: max(0, width - raw.count)) + raw
}
