public enum OBSBOTGestureAutoFrameMode: UInt8, CaseIterable, Equatable, Sendable,
  CustomStringConvertible
{
  case autoFrame = 0
  case closeUp = 1
  case halfBody = 2
  case fullBody = 3

  public var description: String {
    switch self {
    case .autoFrame:
      "autoFrame"
    case .closeUp:
      "closeUp"
    case .halfBody:
      "halfBody"
    case .fullBody:
      "fullBody"
    }
  }
}

public struct OBSBOTGestureSettingsSnapshot: Equatable, Sendable {
  public var autoFrameEnabled: Bool
  public var autoFrameMode: OBSBOTGestureAutoFrameMode
  public var zoomEnabled: Bool
  public var zoomRatio: Int

  public init(
    autoFrameEnabled: Bool = false,
    autoFrameMode: OBSBOTGestureAutoFrameMode = .autoFrame,
    zoomEnabled: Bool = false,
    zoomRatio: Int = OBSBOTRemoteProtocol.gestureZoomRatioRange.defaultValue
  ) {
    self.autoFrameEnabled = autoFrameEnabled
    self.autoFrameMode = autoFrameMode
    self.zoomEnabled = zoomEnabled
    self.zoomRatio = zoomRatio
  }

  public init(statusBytes bytes: [UInt8]) throws {
    guard bytes.count > 39 else {
      throw UVCRequestError.shortRead(
        operation: "GET_CUR OBSBOT gesture settings",
        expected: 40,
        actual: UInt32(bytes.count)
      )
    }
    let raw = UInt16(bytes[38]) | (UInt16(bytes[39]) << 8)
    autoFrameEnabled = (raw & 0x0001) != 0
    autoFrameMode =
      OBSBOTGestureAutoFrameMode(rawValue: UInt8((raw >> 1) & 0x0003)) ?? .autoFrame
    zoomEnabled = (raw & 0x0008) != 0
    zoomRatio = Int((raw >> 4) & 0x0FFF)
  }
}

public enum OBSBOTTinyGestureControl: CaseIterable, Equatable, Sendable, CustomStringConvertible {
  case targetSelection
  case zoom
  case dynamicZoom
  case dynamicZoomDirection
  case record

  var v3CommandID: UInt16 {
    switch self {
    case .targetSelection:
      0x0057
    case .zoom:
      0x0058
    case .dynamicZoom:
      0x005B
    case .dynamicZoomDirection:
      0x005C
    case .record:
      0x0059
    }
  }

  var parameter: OBSBOTTinyGestureParameter {
    switch self {
    case .targetSelection:
      .targetSelection
    case .zoom:
      .zoom
    case .dynamicZoom:
      .dynamicZoom
    case .dynamicZoomDirection:
      .mirror
    case .record:
      .record
    }
  }

  public var description: String {
    switch self {
    case .targetSelection:
      "targetSelection"
    case .zoom:
      "zoom"
    case .dynamicZoom:
      "dynamicZoom"
    case .dynamicZoomDirection:
      "dynamicZoomDirection"
    case .record:
      "record"
    }
  }
}

public enum OBSBOTTinyGestureParameter: UInt32, CaseIterable, Equatable, Sendable,
  CustomStringConvertible
{
  case master = 0
  case targetSelection = 1
  case zoom = 2
  case dynamicZoom = 3
  case record = 4
  case snapshot = 5
  case rolling = 6
  case mirror = 7

  static let allBooleanParameters: [OBSBOTTinyGestureParameter] = [
    .master,
    .targetSelection,
    .zoom,
    .dynamicZoom,
    .record,
    .snapshot,
    .rolling,
    .mirror,
  ]

  public var description: String {
    switch self {
    case .master:
      "master"
    case .targetSelection:
      "targetSelection"
    case .zoom:
      "zoom"
    case .dynamicZoom:
      "dynamicZoom"
    case .record:
      "record"
    case .snapshot:
      "snapshot"
    case .rolling:
      "rolling"
    case .mirror:
      "mirror"
    }
  }
}

public enum OBSBOTTinyGestureTrackParameter: UInt32, CaseIterable, Equatable, Sendable,
  CustomStringConvertible
{
  case panEnabled = 6
  case pitchEnabled = 7

  static let gimbalAxes: [OBSBOTTinyGestureTrackParameter] = [
    .panEnabled,
    .pitchEnabled,
  ]

  public var description: String {
    switch self {
    case .panEnabled:
      "panEnabled"
    case .pitchEnabled:
      "pitchEnabled"
    }
  }
}

extension OBSBOTRemoteProtocol {
  public static let gestureZoomRatioRange = UVCScalarRange(
    minimum: 100,
    maximum: 400,
    resolution: 1,
    defaultValue: 100
  )

  public static func clampedGestureZoomRatio(_ value: Int) -> Int {
    max(gestureZoomRatioRange.minimum, min(value, gestureZoomRatioRange.maximum))
  }

  public static func makeGestureControlPayload(
    autoFrameEnabled: Bool,
    autoFrameMode: OBSBOTGestureAutoFrameMode,
    zoomEnabled: Bool,
    zoomRatio: Int
  ) -> [UInt8] {
    let clampedRatio = clampedGestureZoomRatio(zoomRatio)
    var payload = [UInt8](repeating: 0, count: uvcPacketLength)
    payload[0] = 0x20
    payload[1] = 0x05
    payload[2] = autoFrameEnabled ? 1 : 0
    payload[3] = autoFrameMode.rawValue
    payload[4] = zoomEnabled ? 1 : 0
    payload[5] = UInt8(clampedRatio & 0xFF)
    payload[6] = UInt8((clampedRatio >> 8) & 0xFF)
    return payload
  }

  public static func makeTinyGestureControlPacket(
    _ control: OBSBOTTinyGestureControl,
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: control.v3CommandID,
      payload: [enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeTinyGestureParameterPacket(
    _ parameter: OBSBOTTinyGestureParameter,
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: 0x007C,
      payload: makeUInt32Payload(parameter.rawValue) + [enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeTinyGestureTrackParameterPacket(
    _ parameter: OBSBOTTinyGestureTrackParameter,
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: 0x007A,
      payload: makeUInt32Payload(parameter.rawValue) + [enabled ? 1 : 0],
      sequence: sequence
    )
  }

  public static func makeTinyHandTrackGimbalPacket(
    enabled: Bool,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: 0x0056,
      payload: [enabled ? 1 : 0],
      sequence: sequence
    )
  }
}

extension UVCController {
  public func readOBSBOTGestureSettings() throws -> OBSBOTGestureSettingsSnapshot {
    let bytes = try readExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      length: OBSBOTRemoteProtocol.uvcPacketLength
    )
    return try OBSBOTGestureSettingsSnapshot(statusBytes: bytes)
  }

  public func setOBSBOTGestureSettings(_ settings: OBSBOTGestureSettingsSnapshot) throws {
    try setOBSBOTGestureSettings(
      autoFrameEnabled: settings.autoFrameEnabled,
      autoFrameMode: settings.autoFrameMode,
      zoomEnabled: settings.zoomEnabled,
      zoomRatio: settings.zoomRatio)
  }

  public func setOBSBOTGestureSettings(
    autoFrameEnabled: Bool,
    autoFrameMode: OBSBOTGestureAutoFrameMode,
    zoomEnabled: Bool,
    zoomRatio: Int
  ) throws {
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      payload: OBSBOTRemoteProtocol.makeGestureControlPayload(
        autoFrameEnabled: autoFrameEnabled,
        autoFrameMode: autoFrameMode,
        zoomEnabled: zoomEnabled,
        zoomRatio: zoomRatio)
    )
  }

  public func setOBSBOTTinyGestureMasterSwitch(enabled: Bool) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.parameter(
        .master,
        enabled: enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTTinyGestureControl(
    _ control: OBSBOTTinyGestureControl,
    enabled: Bool
  ) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.control(
        control,
        enabled: enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTTinyGestureParameter(
    _ parameter: OBSBOTTinyGestureParameter,
    enabled: Bool
  ) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.parameter(
        parameter,
        enabled: enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTTinyGestureTrackParameter(
    _ parameter: OBSBOTTinyGestureTrackParameter,
    enabled: Bool
  ) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.trackParameter(
        parameter,
        enabled: enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTTinyHandTrackGimbal(enabled: Bool) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.handTrackGimbal(
        enabled: enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTVirtualTrackGestures(enabled: Bool) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.virtualTrackGestures(
        enabled: enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTAIEnabled(_ enabled: Bool) throws {
    try executeTinyGestureCommand(
      OBSBOTTinyGestureCommandPlan.aiEnabled(
        enabled,
        sequence: makeTinyGestureSequence()))
  }

  public func setOBSBOTTinyGestureFeature(
    _ control: OBSBOTTinyGestureControl,
    enabled: Bool
  ) throws {
    for command in OBSBOTTinyGestureCommandPlan.feature(
      control,
      enabled: enabled,
      nextSequence: makeTinyGestureSequence)
    {
      try executeTinyGestureCommand(command)
    }
  }

  public func setOBSBOTHandGestureControls(enabled: Bool) throws {
    let commands = OBSBOTTinyGestureCommandPlan.all(
      enabled: enabled,
      nextSequence: makeTinyGestureSequence)
    for command in commands {
      try executeTinyGestureCommand(command)
    }
    if !enabled {
      try setOBSBOTAIMode(.off)
    }
  }

  private func executeTinyGestureCommand(_ command: OBSBOTTinyGestureCommand) throws {
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: command.selector,
      payload: command.packet
    )
  }

  private func makeTinyGestureSequence() -> UInt16 {
    UInt16.random(in: 1...UInt16.max)
  }
}
