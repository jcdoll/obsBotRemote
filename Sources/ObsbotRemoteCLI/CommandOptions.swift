import Foundation
import ObsbotRemoteControl
import ObsbotRemoteCore

struct HIDSniffOptions {
  var vendorID: UInt32?
  var productID: UInt32?
  var seize: Bool = false

  static func parse(_ arguments: [String]) throws -> HIDSniffOptions {
    var options = HIDSniffOptions()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--vendor-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--vendor-id requires a value")
        }
        options.vendorID = try parseInteger(arguments[index])
      case "--product-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--product-id requires a value")
        }
        options.productID = try parseInteger(arguments[index])
      case "--seize":
        options.seize = true
      default:
        throw CLIError("unknown hid-sniff option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}

struct ButtonMapOptions {
  var vendorID: UInt32? = defaultRemoteVendorID
  var productID: UInt32? = defaultRemoteProductID
  var seize: Bool = false
  var output: URL = defaultRemoteButtonCaptureURL
  var captureSeconds: TimeInterval = 2.0
  var reset: Bool = false

  static func parse(_ arguments: [String]) throws -> ButtonMapOptions {
    var options = ButtonMapOptions()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--vendor-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--vendor-id requires a value")
        }
        options.vendorID = try parseInteger(arguments[index])
      case "--product-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--product-id requires a value")
        }
        options.productID = try parseInteger(arguments[index])
      case "--seize":
        options.seize = true
      case "--no-seize":
        options.seize = false
      case "--reset":
        options.reset = true
      case "--output":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--output requires a value")
        }
        options.output = URL(fileURLWithPath: arguments[index])
      case "--seconds":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--seconds requires a value")
        }
        guard let seconds = TimeInterval(arguments[index]), seconds > 0 else {
          throw CLIError("--seconds must be a positive number")
        }
        options.captureSeconds = seconds
      default:
        throw CLIError("unknown map-buttons option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}

struct ListenOptions {
  static func parse(_ arguments: [String]) throws -> ListenOptions {
    guard arguments.isEmpty else {
      throw CLIError("listen does not accept options")
    }
    return ListenOptions()
  }
}

struct CameraOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02

  static func parse(_ arguments: [String]) throws -> CameraOptions {
    var options = CameraOptions()
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
      default:
        throw CLIError("unknown camera option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}

struct CameraZoomOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var value: Int?
  var delta: Int?

  static func parse(_ arguments: [String]) throws -> CameraZoomOptions {
    var options = CameraZoomOptions()
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
      case "--value":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--value requires a value")
        }
        options.value = try parseSignedInteger(arguments[index], option: "--value")
      case "--delta":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--delta requires a value")
        }
        options.delta = try parseSignedInteger(arguments[index], option: "--delta")
      default:
        throw CLIError("unknown camera-zoom option: \(arguments[index])")
      }
      index += 1
    }
    if options.value != nil, options.delta != nil {
      throw CLIError("camera-zoom accepts either --value or --delta, not both")
    }
    return options
  }
}

struct CameraPanTiltOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var pan: Int32?
  var tilt: Int32?

  static func parse(_ arguments: [String]) throws -> CameraPanTiltOptions {
    var options = CameraPanTiltOptions()
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
      case "--pan":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--pan requires a value")
        }
        options.pan = try parseInt32(arguments[index], option: "--pan")
      case "--tilt":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--tilt requires a value")
        }
        options.tilt = try parseInt32(arguments[index], option: "--tilt")
      default:
        throw CLIError("unknown camera-pan-tilt option: \(arguments[index])")
      }
      index += 1
    }
    guard options.pan != nil else {
      throw CLIError("camera-pan-tilt requires --pan")
    }
    guard options.tilt != nil else {
      throw CLIError("camera-pan-tilt requires --tilt")
    }
    return options
  }
}

enum CameraPowerAction {
  case toggle
  case status
  case wake
  case sleep
}

struct CameraPowerOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var action: CameraPowerAction = .toggle

  static func parse(_ arguments: [String]) throws -> CameraPowerOptions {
    var options = CameraPowerOptions()
    var actionWasSet = false
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
      case "status":
        try setAction(.status, on: &options, actionWasSet: &actionWasSet)
      case "on", "wake", "run":
        try setAction(.wake, on: &options, actionWasSet: &actionWasSet)
      case "off", "sleep":
        try setAction(.sleep, on: &options, actionWasSet: &actionWasSet)
      default:
        throw CLIError("unknown camera-power option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }

  private static func setAction(
    _ action: CameraPowerAction,
    on options: inout CameraPowerOptions,
    actionWasSet: inout Bool
  ) throws {
    guard !actionWasSet else {
      throw CLIError("camera-power accepts one action")
    }
    options.action = action
    actionWasSet = true
  }
}

struct CameraXUGetOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var unitID: UInt8?
  var selector: UInt8?
  var length: Int?

  static func parse(_ arguments: [String]) throws -> CameraXUGetOptions {
    var options = CameraXUGetOptions()
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
      case "--unit":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--unit requires a value")
        }
        options.unitID = try parseUInt8(arguments[index], option: "--unit")
      case "--selector":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--selector requires a value")
        }
        options.selector = try parseUInt8(arguments[index], option: "--selector")
      case "--length":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--length requires a value")
        }
        let length = try parseSignedInteger(arguments[index], option: "--length")
        guard length > 0, length <= Int(UInt16.max) else {
          throw CLIError("--length must be between 1 and \(UInt16.max)")
        }
        options.length = length
      default:
        throw CLIError("unknown camera-xu-get option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}

struct CameraXUDumpOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var maxLength: Int = 128

  static func parse(_ arguments: [String]) throws -> CameraXUDumpOptions {
    var options = CameraXUDumpOptions()
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
      case "--max-length":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--max-length requires a value")
        }
        let maxLength = try parseSignedInteger(arguments[index], option: "--max-length")
        guard maxLength > 0 else {
          throw CLIError("--max-length must be positive")
        }
        options.maxLength = maxLength
      default:
        throw CLIError("unknown camera-xu-dump option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }
}

private func parseUInt8(_ text: String, option: String) throws -> UInt8 {
  let value = try parseInteger(text)
  guard let narrowed = UInt8(exactly: value) else {
    throw CLIError("\(option) must fit in 8 bits")
  }
  return narrowed
}

private func parseUInt16(_ text: String, option: String) throws -> UInt16 {
  let value = try parseInteger(text)
  guard let narrowed = UInt16(exactly: value) else {
    throw CLIError("\(option) must fit in 16 bits")
  }
  return narrowed
}

private func parseSignedInteger(_ text: String, option: String) throws -> Int {
  guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    throw CLIError("\(option) must be an integer")
  }
  return value
}

private func parseInt32(_ text: String, option: String) throws -> Int32 {
  let value = try parseSignedInteger(text, option: option)
  guard let narrowed = Int32(exactly: value) else {
    throw CLIError("\(option) must fit in 32 bits")
  }
  return narrowed
}
