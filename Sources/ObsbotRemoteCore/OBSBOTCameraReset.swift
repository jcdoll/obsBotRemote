import Foundation

public struct OBSBOTCameraResetResult: Equatable, Sendable {
  public var gimbalStopSent: Bool
  public var gimbalResetSent: Bool
  public var factoryRestoreSent: Bool
  public var rebootRequested: Bool

  public init(
    gimbalStopSent: Bool,
    gimbalResetSent: Bool,
    factoryRestoreSent: Bool,
    rebootRequested: Bool
  ) {
    self.gimbalStopSent = gimbalStopSent
    self.gimbalResetSent = gimbalResetSent
    self.factoryRestoreSent = factoryRestoreSent
    self.rebootRequested = rebootRequested
  }
}

extension UVCController {
  public func resetOBSBOTCameraToFactoryDefaults(
    reboot: Bool = true
  ) throws -> OBSBOTCameraResetResult {
    var sequence = UInt16.random(in: 1...UInt16.max)
    func nextSequence() -> UInt16 {
      let current = sequence
      sequence &+= 1
      if sequence == 0 {
        sequence = 1
      }
      return current
    }

    try sendOBSBOTCommandPacket(OBSBOTRemoteProtocol.makeGimbalStopPacket(sequence: nextSequence()))
    Thread.sleep(forTimeInterval: 0.25)

    try sendOBSBOTCommandPacket(
      OBSBOTRemoteProtocol.makeTiny3GimbalResetPacket(sequence: nextSequence()))
    Thread.sleep(forTimeInterval: 0.25)

    try sendOBSBOTCommandPacket(
      OBSBOTRemoteProtocol.makeFactoryRestorePacket(sequence: nextSequence()))

    if reboot {
      Thread.sleep(forTimeInterval: 1.0)
      try sendOBSBOTCommandPacket(OBSBOTRemoteProtocol.makeRebootPacket(sequence: nextSequence()))
    }

    return OBSBOTCameraResetResult(
      gimbalStopSent: true,
      gimbalResetSent: true,
      factoryRestoreSent: true,
      rebootRequested: reboot
    )
  }

  private func sendOBSBOTCommandPacket(_ packet: [UInt8]) throws {
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
  }
}
