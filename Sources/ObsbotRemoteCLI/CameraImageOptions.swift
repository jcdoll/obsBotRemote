import Foundation
import ObsbotRemoteCore

struct CameraImageOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var reset = false
  var adjustments: [OBSBOTImageAdjustment: Int] = [:]
  var whiteBalanceAuto: Bool?
  var whiteBalanceKelvin: Int?

  static func parse(_ arguments: [String]) throws -> CameraImageOptions {
    var options = CameraImageOptions()
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
      case "--reset":
        options.reset = true
      case "--brightness":
        try parseAdjustmentValue(.brightness, arguments, &index, &options)
      case "--contrast":
        try parseAdjustmentValue(.contrast, arguments, &index, &options)
      case "--saturation":
        try parseAdjustmentValue(.saturation, arguments, &index, &options)
      case "--white-balance":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--white-balance requires a Kelvin value")
        }
        let range = OBSBOTRemoteProtocol.whiteBalanceKelvinRange
        options.whiteBalanceKelvin = try parseBoundedInteger(
          arguments[index],
          option: "--white-balance",
          minimum: range.minimum,
          maximum: range.maximum)
      case "--white-balance-auto":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--white-balance-auto requires on or off")
        }
        options.whiteBalanceAuto =
          try parseOnOff(arguments[index], option: "--white-balance-auto") == 1
      default:
        throw CLIError("unknown camera-image option: \(arguments[index])")
      }
      index += 1
    }
    try options.validate()
    return options
  }

  var hasMutations: Bool {
    reset || !adjustments.isEmpty || whiteBalanceAuto != nil || whiteBalanceKelvin != nil
  }

  private func validate() throws {
    if reset && (!adjustments.isEmpty || whiteBalanceAuto != nil || whiteBalanceKelvin != nil) {
      throw CLIError("--reset cannot be combined with other camera-image writes")
    }
    if whiteBalanceAuto == true && whiteBalanceKelvin != nil {
      throw CLIError("--white-balance cannot be combined with --white-balance-auto on")
    }
  }
}

private func parseAdjustmentValue(
  _ adjustment: OBSBOTImageAdjustment,
  _ arguments: [String],
  _ index: inout Int,
  _ options: inout CameraImageOptions
) throws {
  index += 1
  guard index < arguments.count else {
    throw CLIError("--\(adjustment.description) requires a 0-100 value")
  }
  let range = OBSBOTRemoteProtocol.imageAdjustmentRange
  options.adjustments[adjustment] = try parseBoundedInteger(
    arguments[index],
    option: "--\(adjustment.description)",
    minimum: range.minimum,
    maximum: range.maximum)
}

func parseOnOff(_ text: String, option: String) throws -> Int {
  switch text.lowercased() {
  case "on", "true", "yes", "1":
    return 1
  case "off", "false", "no", "0":
    return 0
  default:
    throw CLIError("\(option) must be on or off")
  }
}
