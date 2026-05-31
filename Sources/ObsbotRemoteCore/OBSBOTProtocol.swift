public enum OBSBOTRunStatus: Equatable, Sendable, CustomStringConvertible {
  case run
  case sleep
  case privacy
  case unknown(UInt8)

  public init(rawValue: UInt8) {
    switch rawValue {
    case 1:
      self = .run
    case 3:
      self = .sleep
    case 4:
      self = .privacy
    default:
      self = .unknown(rawValue)
    }
  }

  public var rawValue: UInt8 {
    switch self {
    case .run:
      1
    case .sleep:
      3
    case .privacy:
      4
    case .unknown(let value):
      value
    }
  }

  public var description: String {
    switch self {
    case .run:
      "run"
    case .sleep:
      "sleep"
    case .privacy:
      "privacy"
    case .unknown(let value):
      "unknown(\(formatHex(UInt32(value), width: 2)))"
    }
  }
}

public enum OBSBOTAIMode: Equatable, Sendable, CustomStringConvertible {
  case off
  case humanNormal
  case humanUpperBody
  case humanCloseUp
  case hand
  case desk
  case switching
  case unknown(statusMode: UInt8, statusSubMode: UInt8)

  public init(statusMode: UInt8, statusSubMode: UInt8) {
    switch (statusMode, statusSubMode) {
    case (0, 0):
      self = .off
    case (2, 0):
      self = .humanNormal
    case (2, 1):
      self = .humanUpperBody
    case (2, 2):
      self = .humanCloseUp
    case (3, 0):
      self = .hand
    case (5, 0):
      self = .desk
    case (6, 0):
      self = .switching
    default:
      self = .unknown(statusMode: statusMode, statusSubMode: statusSubMode)
    }
  }

  public var description: String {
    switch self {
    case .off:
      "off"
    case .humanNormal:
      "humanNormal"
    case .humanUpperBody:
      "humanUpperBody"
    case .humanCloseUp:
      "humanCloseUp"
    case .hand:
      "hand"
    case .desk:
      "desk"
    case .switching:
      "switching"
    case .unknown(let mode, let subMode):
      "unknown(mode=\(formatHex(UInt32(mode), width: 2)), subMode=\(formatHex(UInt32(subMode), width: 2)))"
    }
  }

  var commandPair: (mode: UInt8, subMode: UInt8)? {
    switch self {
    case .off:
      (0, 0)
    case .humanNormal:
      (2, 0)
    case .humanUpperBody:
      (2, 1)
    case .humanCloseUp:
      (2, 2)
    case .hand:
      (3, 0)
    case .desk:
      (5, 0)
    case .switching, .unknown:
      nil
    }
  }
}

public enum OBSBOTRemoteProtocol {
  public static let extensionUnitID: UInt8 = 2
  public static let commandSelector: UInt8 = 2
  public static let statusSelector: UInt8 = 6
  public static let uvcPacketLength = 60

  public static func makeDevRunStatusPacket(
    _ status: OBSBOTRunStatus,
    sequence: UInt16
  ) throws -> [UInt8] {
    let payloadValue: UInt32
    switch status {
    case .run:
      payloadValue = 0
    case .sleep:
      payloadValue = 1
    case .privacy, .unknown:
      throw UVCRequestError.unsupportedControl("OBSBOT run-status target \(status)")
    }

    return makeRMCommandPacket(
      v3CommandID: 0x0283,
      payload: makeUInt32Payload(payloadValue),
      sequence: sequence
    )
  }

  public static func makeFaceAutoFocusPacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeRMCommandPacket(
      v3CommandID: 0x00D8,
      payload: makeUInt32Payload(enabled ? 1 : 0),
      sequence: sequence
    )
  }

  public static func makeRMCommandPacket(
    v3CommandSet: UInt8 = 0x02,
    v3CommandID: UInt16,
    payload: [UInt8],
    sequence: UInt16
  ) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x25,
      route: 0x02,
      v3CommandSet: v3CommandSet,
      v3CommandID: v3CommandID,
      payload: payload,
      sequence: sequence
    )
  }

  public static func makeGimbalStopPacket(sequence: UInt16) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x05,
      route: 0x04,
      v3CommandSet: 0x04,
      v3CommandID: 0x019C,
      payload: [],
      sequence: sequence
    )
  }

  public static func makeTiny3GimbalResetPacket(sequence: UInt16) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x25,
      route: 0x03,
      v3CommandSet: 0x03,
      v3CommandID: 0x0003,
      payload: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
      sequence: sequence
    )
  }

  public static func makeFactoryRestorePacket(sequence: UInt16) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x25,
      route: 0x02,
      v3CommandSet: 0x02,
      v3CommandID: 0x02A0,
      payload: [0x01],
      sequence: sequence
    )
  }

  public static func makeRebootPacket(sequence: UInt16) -> [UInt8] {
    // SDK cameraSetPowerCtrlActionR uses legacy 0x01/0x008B, which converts to
    // the same V3 command as run/sleep with payload value 2.
    makeRMCommandPacket(
      v3CommandID: 0x0283,
      payload: makeUInt32Payload(2),
      sequence: sequence
    )
  }

  static func makeV3CommandPacket(
    flag: UInt8,
    route: UInt8,
    v3CommandSet: UInt8,
    v3CommandID: UInt16,
    payload: [UInt8],
    sequence: UInt16
  ) -> [UInt8] {
    precondition(v3CommandSet <= 0x3F)
    precondition(payload.count <= uvcPacketLength - 16)

    var packet = [UInt8](repeating: 0, count: uvcPacketLength)
    packet[0] = 0xAA
    packet[1] = flag
    packet[2] = UInt8(sequence & 0xFF)
    packet[3] = UInt8((sequence >> 8) & 0xFF)
    packet[4] = 0x0C
    packet[5] = 0x00
    packet[8] = 0x0A
    packet[9] = route
    packet[10] = v3CommandSet | UInt8((v3CommandID & 0x0003) << 6)
    packet[11] = UInt8((v3CommandID >> 2) & 0x00FF)
    packet[12] = UInt8(payload.count & 0xFF)
    packet[13] = UInt8((payload.count >> 8) & 0xFF)
    packet.replaceSubrange(16..<(16 + payload.count), with: payload)

    let headerCRC = crc16(Array(packet[0..<12]))
    packet[6] = UInt8(headerCRC & 0xFF)
    packet[7] = UInt8((headerCRC >> 8) & 0xFF)

    let bodyLength = Int(UInt16(packet[12]) | (UInt16(packet[13]) << 8))
    let bodyCRC = crc16(Array(packet[12..<(12 + bodyLength + 4)]))
    packet[14] = UInt8(bodyCRC & 0xFF)
    packet[15] = UInt8((bodyCRC >> 8) & 0xFF)

    return packet
  }

  public static func makeSDKRMCommandPacket(
    commandSet: UInt8,
    commandID: UInt16,
    payload: [UInt8],
    sequence: UInt16
  ) -> [UInt8] {
    let wireCommand = sdkV3WireCommand(commandSet: commandSet, commandID: commandID)
    return makeV3CommandPacket(
      flag: payload.isEmpty ? 0x01 : 0x21,
      route: 0x04,
      v3CommandSet: wireCommand.set,
      v3CommandID: wireCommand.id,
      payload: payload,
      sequence: sequence
    )
  }

  static func sdkV3WireCommand(
    commandSet: UInt8,
    commandID: UInt16
  ) -> (set: UInt8, id: UInt16) {
    switch (commandSet, commandID) {
    case (0x01, 0x009A):
      (0x02, 0x02B2)
    case (0x01, 0x00A3):
      (0x02, 0x02BA)
    case (0x03, 0x0056):
      (0x04, 0x009B)
    case (0x03, 0x0013):
      (0x04, 0x0004)
    case (0x03, 0x0057):
      (0x04, 0x00C3)
    case (0x03, 0x0058):
      (0x04, 0x00C5)
    case (0x03, 0x0059):
      (0x04, 0x00C7)
    case (0x03, 0x005B):
      (0x04, 0x00CD)
    case (0x03, 0x005C):
      (0x04, 0x00CF)
    case (0x03, 0x0061):
      (0x04, 0x0009)
    case (0x03, 0x007A):
      (0x04, 0x0081)
    case (0x03, 0x007B):
      (0x04, 0x0082)
    case (0x03, 0x007C):
      (0x04, 0x00D1)
    case (0x03, 0x007D):
      (0x04, 0x00D2)
    default:
      preconditionFailure(
        "Unsupported SDK RM command \(formatHex(UInt32(commandSet), width: 2))/\(formatHex(UInt32(commandID), width: 4))"
      )
    }
  }

  static func makeUInt32Payload(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 24) & 0xFF),
    ]
  }

  public static func makeAIModePayload(_ mode: OBSBOTAIMode) throws -> [UInt8] {
    guard let pair = mode.commandPair else {
      throw UVCRequestError.unsupportedControl("OBSBOT AI mode target \(mode)")
    }

    var payload = [UInt8](repeating: 0, count: uvcPacketLength)
    payload[0] = 0x16
    payload[1] = 0x02
    payload[2] = pair.mode
    payload[3] = pair.subMode
    return payload
  }

  public static func crc16(_ bytes: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0xFFFF
    for byte in bytes {
      crc ^= UInt16(byte)
      for _ in 0..<8 {
        if (crc & 0x0001) == 0x0001 {
          crc = (crc >> 1) ^ 0xA001
        } else {
          crc >>= 1
        }
      }
    }
    return ~crc
  }
}
