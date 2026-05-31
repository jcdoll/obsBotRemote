import Foundation
import ObsbotRemoteCore

struct CameraSettingsOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var hdr: Bool?
  var faceAutoExposure: Bool?
  var faceAutoFocus: Bool?
  var fieldOfView: OBSBOTFieldOfView?

  static func parse(_ arguments: [String]) throws -> CameraSettingsOptions {
    var options = CameraSettingsOptions()
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
      case "--hdr":
        options.hdr = try parseBooleanArgument(arguments, &index, option: "--hdr")
      case "--face-ae":
        options.faceAutoExposure = try parseBooleanArgument(
          arguments, &index, option: "--face-ae")
      case "--face-af", "--face-focus":
        options.faceAutoFocus = try parseBooleanArgument(
          arguments, &index, option: arguments[index])
      case "--fov":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--fov requires wide, medium, or narrow")
        }
        options.fieldOfView = try parseFieldOfView(arguments[index])
      default:
        throw CLIError("unknown camera-settings option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }

  var hasMutations: Bool {
    hdr != nil || faceAutoExposure != nil || faceAutoFocus != nil || fieldOfView != nil
  }
}

private func parseBooleanArgument(
  _ arguments: [String],
  _ index: inout Int,
  option: String
) throws -> Bool {
  index += 1
  guard index < arguments.count else {
    throw CLIError("\(option) requires on or off")
  }
  return try parseOnOff(arguments[index], option: option) == 1
}

private func parseFieldOfView(_ text: String) throws -> OBSBOTFieldOfView {
  switch text.lowercased() {
  case "wide", "86", "86deg":
    return .wide
  case "medium", "normal", "78", "78deg":
    return .medium
  case "narrow", "65", "65deg":
    return .narrow
  default:
    throw CLIError("--fov requires wide, medium, or narrow")
  }
}
