import Foundation
import ObsbotRemoteCore

struct CameraAIOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var mode: OBSBOTAIMode?

  static func parse(_ arguments: [String]) throws -> CameraAIOptions {
    var options = CameraAIOptions()
    var modeWasSet = false
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
      case "--mode":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--mode requires off, track, upper, close-up, hand, or desk")
        }
        try setMode(parseAIMode(arguments[index], option: "--mode"), on: &options, &modeWasSet)
      case "status":
        break
      default:
        try setMode(parseAIMode(arguments[index], option: "camera-ai"), on: &options, &modeWasSet)
      }
      index += 1
    }
    return options
  }

  private static func setMode(
    _ mode: OBSBOTAIMode,
    on options: inout CameraAIOptions,
    _ modeWasSet: inout Bool
  ) throws {
    guard !modeWasSet else {
      throw CLIError("camera-ai accepts one mode")
    }
    options.mode = mode
    modeWasSet = true
  }
}

private func parseAIMode(_ text: String, option: String) throws -> OBSBOTAIMode {
  switch text.lowercased() {
  case "off", "none", "disable", "disabled":
    return .off
  case "track", "human", "human-normal", "normal":
    return .humanNormal
  case "upper", "upper-body", "body":
    return .humanUpperBody
  case "close", "close-up", "closeup":
    return .humanCloseUp
  case "hand", "hand-track":
    return .hand
  case "desk":
    return .desk
  default:
    throw CLIError("\(option) requires off, track, upper, close-up, hand, or desk")
  }
}
