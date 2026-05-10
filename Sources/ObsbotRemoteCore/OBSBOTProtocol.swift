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

    var packet = [UInt8](repeating: 0, count: uvcPacketLength)
    packet[0] = 0xAA
    packet[1] = 0x25
    packet[2] = UInt8(sequence & 0xFF)
    packet[3] = UInt8((sequence >> 8) & 0xFF)
    packet[4] = 0x0C
    packet[5] = 0x00
    packet[8] = 0x0A
    packet[9] = 0x02
    packet[10] = 0xC2
    packet[11] = 0xA0
    packet[12] = 0x04
    packet[13] = 0x00
    packet[16] = UInt8(payloadValue & 0xFF)
    packet[17] = UInt8((payloadValue >> 8) & 0xFF)
    packet[18] = UInt8((payloadValue >> 16) & 0xFF)
    packet[19] = UInt8((payloadValue >> 24) & 0xFF)

    let headerCRC = crc16(Array(packet[0..<12]))
    packet[6] = UInt8(headerCRC & 0xFF)
    packet[7] = UInt8((headerCRC >> 8) & 0xFF)

    let bodyLength = Int(UInt16(packet[12]) | (UInt16(packet[13]) << 8))
    let bodyCRC = crc16(Array(packet[12..<(12 + bodyLength + 4)]))
    packet[14] = UInt8(bodyCRC & 0xFF)
    packet[15] = UInt8((bodyCRC >> 8) & 0xFF)

    return packet
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
