struct CameraResetOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var reboot: Bool = true

  static func parse(_ arguments: [String]) throws -> CameraResetOptions {
    var options = CameraResetOptions()
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
      case "--no-reboot":
        options.reboot = false
      default:
        throw CLIError("unknown camera-reset option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}
