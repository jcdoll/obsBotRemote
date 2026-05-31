public enum UVCRequestError: Error, CustomStringConvertible, Equatable, Sendable {
  case deviceRequestFailed(operation: String, code: Int32, transferred: UInt32)
  case descriptorReadFailed(code: Int32)
  case descriptorTooLarge(required: Int)
  case missingExtensionUnit(UInt8)
  case missingCameraTerminal
  case missingProcessingUnit
  case unsupportedControl(String)
  case shortRead(operation: String, expected: Int, actual: UInt32)
  case invalidResponse(operation: String, reason: String)

  public var description: String {
    switch self {
    case .deviceRequestFailed(let operation, let code, let transferred):
      "\(operation) failed: \(formatIOReturn(code)) transferred=\(transferred)"
    case .descriptorReadFailed(let code):
      "failed to read USB configuration descriptor: \(formatIOReturn(code))"
    case .descriptorTooLarge(let required):
      "USB configuration descriptor is too large for the probe buffer: \(required) byte(s)"
    case .missingExtensionUnit(let unitID):
      "no UVC extension unit with id \(unitID) was found in the camera configuration descriptor"
    case .missingCameraTerminal:
      "no UVC camera terminal was found in the camera configuration descriptor"
    case .missingProcessingUnit:
      "no UVC processing unit was found in the camera configuration descriptor"
    case .unsupportedControl(let control):
      "camera does not advertise \(control)"
    case .shortRead(let operation, let expected, let actual):
      "\(operation) returned \(actual) byte(s), expected \(expected)"
    case .invalidResponse(let operation, let reason):
      "\(operation) returned an invalid response: \(reason)"
    }
  }
}

public struct UVCZoomRange: Equatable, Sendable {
  public var minimum: Int
  public var maximum: Int
  public var resolution: Int
  public var defaultValue: Int

  public init(minimum: Int, maximum: Int, resolution: Int, defaultValue: Int) {
    self.minimum = minimum
    self.maximum = maximum
    self.resolution = resolution
    self.defaultValue = defaultValue
  }

  public func clamp(_ value: Int) -> Int {
    let lower = min(minimum, maximum)
    let upper = max(minimum, maximum)
    return max(lower, min(value, upper))
  }
}

public struct UVCPanTiltValue: Equatable, Sendable {
  public var pan: Int32
  public var tilt: Int32
}

public struct UVCPanTiltRange: Equatable, Sendable {
  public var minimum: UVCPanTiltValue
  public var maximum: UVCPanTiltValue
  public var resolution: UVCPanTiltValue
  public var defaultValue: UVCPanTiltValue
}

public struct UVCScalarRange: Equatable, Sendable {
  public var minimum: Int
  public var maximum: Int
  public var resolution: Int
  public var defaultValue: Int

  public init(minimum: Int, maximum: Int, resolution: Int, defaultValue: Int) {
    self.minimum = minimum
    self.maximum = maximum
    self.resolution = resolution
    self.defaultValue = defaultValue
  }
}

func formatIOReturn(_ code: Int32) -> String {
  let unsigned = UInt32(bitPattern: code)
  return "0x" + String(unsigned, radix: 16, uppercase: true)
}
