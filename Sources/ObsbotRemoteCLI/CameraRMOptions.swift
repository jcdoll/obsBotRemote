import Foundation
import ObsbotRemoteCore

struct CameraRMOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var commandSet: UInt8?
  var commandID: UInt16?
  var payload: [UInt8] = []
  var sequence: UInt16 = 0x0016
  var readLength: Int = OBSBOTRemoteProtocol.uvcPacketLength
  var readDelay: TimeInterval = 0.05

  static func parse(_ arguments: [String]) throws -> CameraRMOptions {
    var options = CameraRMOptions()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--vendor-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--vendor-id requires a value")
        }
        options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
      case "--product-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--product-id requires a value")
        }
        options.productID = try parseUInt16(arguments[index], option: "--product-id")
      case "--command-set":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--command-set requires a value")
        }
        options.commandSet = try parseUInt8(arguments[index], option: "--command-set")
      case "--command-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--command-id requires a value")
        }
        options.commandID = try parseUInt16(arguments[index], option: "--command-id")
      case "--payload":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--payload requires a quoted byte list")
        }
        options.payload = try parsePayload(arguments[index])
      case "--sequence":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--sequence requires a value")
        }
        let sequence = try parseUInt16(arguments[index], option: "--sequence")
        guard sequence != 0 else {
          throw CLIError("--sequence must be non-zero")
        }
        options.sequence = sequence
      case "--read-length":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--read-length requires a value")
        }
        let length = try parseSignedInteger(arguments[index], option: "--read-length")
        guard length >= 0, length <= Int(UInt16.max) else {
          throw CLIError("--read-length must be between 0 and \(UInt16.max)")
        }
        options.readLength = length
      case "--read-delay":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--read-delay requires seconds")
        }
        guard let delay = TimeInterval(arguments[index]), delay >= 0 else {
          throw CLIError("--read-delay must be a non-negative number")
        }
        options.readDelay = delay
      default:
        throw CLIError("unknown camera-rm-send option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}

private func parsePayload(_ text: String) throws -> [UInt8] {
  let separators = CharacterSet(charactersIn: " ,:")
    .union(.whitespacesAndNewlines)
  return try text.components(separatedBy: separators)
    .filter { !$0.isEmpty }
    .map { try parseUInt8($0, option: "--payload") }
}
