public struct OBSBOTTinyGestureCommand: Equatable, Sendable {
  public var name: String
  public var selector: UInt8
  public var packet: [UInt8]

  public init(name: String, selector: UInt8, packet: [UInt8]) {
    self.name = name
    self.selector = selector
    self.packet = packet
  }
}

public enum OBSBOTTinyGestureCommandPlan {
  public static func aiEnabled(
    _ enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.aiEnabled=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyAIEnabledPacket(
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func legacyAIEnabled(
    _ enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.legacyAIEnabled=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyLegacyAIEnabledPacket(
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func legacyGestureControl(
    enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.legacyGestureControl=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyLegacyGestureControlPacket(
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func virtualTrackEnabled(
    _ enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "camera.virtualTrackEnabled=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeVirtualTrackEnabledPacket(
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func virtualTrackGestures(
    enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "camera.virtualTrackGestures=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeVirtualTrackGesturePacket(
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func control(
    _ control: OBSBOTTinyGestureControl,
    enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.control.\(control)=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyGestureControlPacket(
        control,
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func parameter(
    _ parameter: OBSBOTTinyGestureParameter,
    enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.parameter.\(parameter)=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyGestureParameterPacket(
        parameter,
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func trackParameter(
    _ parameter: OBSBOTTinyGestureTrackParameter,
    enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.track.\(parameter)=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyGestureTrackParameterPacket(
        parameter,
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func handTrackGimbal(
    enabled: Bool,
    sequence: UInt16
  ) -> OBSBOTTinyGestureCommand {
    OBSBOTTinyGestureCommand(
      name: "tiny.handTrackGimbal=\(onOff(enabled))",
      selector: OBSBOTRemoteProtocol.commandSelector,
      packet: OBSBOTRemoteProtocol.makeTinyHandTrackGimbalPacket(
        enabled: enabled,
        sequence: sequence)
    )
  }

  public static func feature(
    _ control: OBSBOTTinyGestureControl,
    enabled: Bool,
    nextSequence: () -> UInt16
  ) -> [OBSBOTTinyGestureCommand] {
    if enabled {
      return [
        parameter(.master, enabled: true, sequence: nextSequence()),
        parameter(control.parameter, enabled: true, sequence: nextSequence()),
        self.control(control, enabled: true, sequence: nextSequence()),
      ]
    }
    return [
      self.control(control, enabled: false, sequence: nextSequence()),
      parameter(control.parameter, enabled: false, sequence: nextSequence()),
    ]
  }

  public static func all(
    enabled: Bool,
    startingSequence: UInt16
  ) -> [OBSBOTTinyGestureCommand] {
    var generator = OBSBOTTinyGestureSequenceGenerator(startingAt: startingSequence)
    return all(enabled: enabled, nextSequence: { generator.next() })
  }

  public static func all(
    enabled: Bool,
    nextSequence: () -> UInt16
  ) -> [OBSBOTTinyGestureCommand] {
    var commands: [OBSBOTTinyGestureCommand] = []
    if enabled {
      commands.append(parameter(.master, enabled: true, sequence: nextSequence()))
      commands.append(handTrackGimbal(enabled: true, sequence: nextSequence()))
      for axis in OBSBOTTinyGestureTrackParameter.gimbalAxes {
        commands.append(trackParameter(axis, enabled: true, sequence: nextSequence()))
      }
      for parameter in OBSBOTTinyGestureParameter.allBooleanParameters where parameter != .master {
        commands.append(self.parameter(parameter, enabled: true, sequence: nextSequence()))
      }
      for control in OBSBOTTinyGestureControl.allCases {
        commands.append(self.control(control, enabled: true, sequence: nextSequence()))
      }
    } else {
      for control in OBSBOTTinyGestureControl.allCases {
        commands.append(self.control(control, enabled: false, sequence: nextSequence()))
      }
      for parameter in OBSBOTTinyGestureParameter.allBooleanParameters where parameter != .master {
        commands.append(self.parameter(parameter, enabled: false, sequence: nextSequence()))
      }
      for axis in OBSBOTTinyGestureTrackParameter.gimbalAxes {
        commands.append(trackParameter(axis, enabled: false, sequence: nextSequence()))
      }
      commands.append(handTrackGimbal(enabled: false, sequence: nextSequence()))
      commands.append(parameter(.master, enabled: false, sequence: nextSequence()))
    }
    return commands
  }

  private static func onOff(_ value: Bool) -> String {
    value ? "on" : "off"
  }
}

extension OBSBOTRemoteProtocol {
  public static func makeTinyLegacyGestureControlPacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeRMCommandPacket(
      v3CommandSet: 0x03,
      v3CommandID: 0x000D,
      payload: [0x05, enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeTinyAIEnabledPacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: 0x0061,
      payload: [enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeTinyLegacyAIEnabledPacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeRMCommandPacket(
      v3CommandSet: 0x03,
      v3CommandID: 0x000D,
      payload: [0x00, enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeVirtualTrackEnabledPacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x01,
      commandID: 0x00A3,
      payload: [enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeVirtualTrackGesturePacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    let value = makeUInt32Payload(enabled ? 1 : 0)
    return makeSDKRMCommandPacket(
      commandSet: 0x01,
      commandID: 0x009A,
      payload: value + value + value,
      sequence: sequence
    )
  }
}

private struct OBSBOTTinyGestureSequenceGenerator {
  var sequence: UInt16

  init(startingAt sequence: UInt16) {
    self.sequence = sequence
  }

  mutating func next() -> UInt16 {
    let current = sequence
    sequence = sequence == UInt16.max ? 1 : sequence + 1
    return current
  }
}
