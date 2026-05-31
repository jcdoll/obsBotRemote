import Foundation
import ObsbotRemoteControl
import ObsbotRemoteCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    FileHandle.standardError.write(Data(("self-test failed: \(message)\n").utf8))
    exit(1)
  }
}

func expectNoThrow<T>(_ message: String, _ operation: () throws -> T) -> T {
  do {
    return try operation()
  } catch {
    FileHandle.standardError.write(Data(("self-test failed: \(message): \(error)\n").utf8))
    exit(1)
  }
}

let reducer = CameraActionReducer()
let moved = reducer.applying(.move(panDelta: 3600, tiltDelta: -1800), to: CameraState())
expect(moved == CameraState(pan: 3600, tilt: -1800, zoom: 100), "move action")

let zoomed = reducer.applying(.zoom(delta: -200), to: CameraState(zoom: 100))
expect(zoomed.zoom == 0, "zoom floor")
expect(
  UVCZoomRange(minimum: 10, maximum: 50, resolution: 1, defaultValue: 10).clamp(80) == 50,
  "UVC zoom range clamp")

let presetReducer = CameraActionReducer(
  presets: ["1": CameraPreset(pan: 10, tilt: 20, zoom: 30)]
)
let recalled = presetReducer.applying(.recallPreset("1"), to: CameraState())
expect(recalled == CameraState(pan: 10, tilt: 20, zoom: 30), "preset recall")

expect(expectNoThrow("parse decimal") { try parseInteger("1234") } == 1234, "parse decimal")
expect(expectNoThrow("parse hex") { try parseInteger("0x1A2B") } == 0x1A2B, "parse hex")
expect(formatHex(0x2A) == "0x002A", "hex formatting")

let disabledButton = ButtonCapture(
  button: "Disabled",
  events: [
    HIDEventRecord(
      usagePage: 7,
      usage: 40,
      value: 1,
      state: "down",
      name: "keyboard.return",
      timestamp: 0
    )
  ],
  terminalBytes: nil,
  terminalEscaped: nil,
  skipped: false,
  enabled: false
)
let disabledMatcher = RemoteButtonMatcher(captures: [disabledButton])
let disabledInput = InputCapture(hidEvents: disabledButton.events, terminalBytes: [])
if case .unknown = disabledMatcher.match(disabledInput) {
  // expected
} else {
  expect(false, "disabled button capture does not match")
}

let uvcDescriptor = Data([
  9, 2, 74, 0, 1, 1, 0, 0x80, 50,
  9, 4, 0, 0, 0, 0x0E, 0x01, 0, 0,
  18, 0x24, 0x02, 3, 0x01, 0x02, 0, 0,
  0, 0, 0, 0, 0, 0, 3, 0, 0x14, 0,
  12, 0x24, 0x05, 5, 3, 0, 0, 3, 0x42, 0x40, 0x01, 0,
  26, 0x24, 0x06, 4,
  0x91, 0x72, 0x1E, 0x9A, 0x43, 0x68, 0x83, 0x46,
  0x6D, 0x92, 0x39, 0xBC, 0x79, 0x06, 0xEE, 0x49,
  7, 1, 3, 1, 0x07, 0,
])
let uvcProbe = UVCDescriptorParser.parseConfiguration(uvcDescriptor)
expect(uvcProbe.videoControlInterfaces.count == 1, "UVC video control interface parse")
expect(uvcProbe.cameraTerminals.count == 1, "UVC camera terminal parse")
expect(uvcProbe.cameraTerminals[0].terminalID == 3, "UVC camera terminal id")
expect(uvcProbe.cameraTerminals[0].supports(.zoomAbsolute), "UVC zoom support bit")
expect(uvcProbe.cameraTerminals[0].supports(.panTiltAbsolute), "UVC pan tilt support bit")
expect(uvcProbe.processingUnits.count == 1, "UVC processing unit parse")
expect(uvcProbe.processingUnits[0].unitID == 5, "UVC processing unit id")
expect(uvcProbe.processingUnits[0].supports(.brightness), "UVC brightness support bit")
expect(uvcProbe.processingUnits[0].supports(.saturation), "UVC saturation support bit")
expect(
  uvcProbe.processingUnits[0].supports(.whiteBalanceTemperatureAuto),
  "UVC white balance auto support bit")
expect(uvcProbe.processingUnits[0].supports(.contrastAuto), "UVC contrast auto support bit")
expect(uvcProbe.extensionUnits.count == 1, "UVC extension unit parse")
expect(uvcProbe.extensionUnits[0].unitID == 4, "UVC extension unit id")
expect(
  uvcProbe.extensionUnits[0].guidString == "9a1e7291-6843-4683-6d92-39bc7906ee49",
  "UVC extension unit guid")
expect(uvcProbe.extensionUnits[0].advertisedSelectors == [1, 2, 3], "UVC extension selectors")

expect(OBSBOTRunStatus(rawValue: 1) == .run, "OBSBOT run status parse")
expect(OBSBOTRunStatus(rawValue: 3) == .sleep, "OBSBOT sleep status parse")
expect(OBSBOTRunStatus(rawValue: 4) == .privacy, "OBSBOT privacy status parse")
expect(
  String(describing: OBSBOTRunStatus(rawValue: 9)) == "unknown(0x09)",
  "OBSBOT unknown status description")
expect(OBSBOTAIMode(statusMode: 0, statusSubMode: 0) == .off, "OBSBOT AI off status parse")
expect(
  OBSBOTAIMode(statusMode: 2, statusSubMode: 0) == .humanNormal, "OBSBOT AI human status parse")
expect(
  OBSBOTAIMode(statusMode: 2, statusSubMode: 1) == .humanUpperBody,
  "OBSBOT AI upper-body status parse")
expect(
  OBSBOTAIMode(statusMode: 2, statusSubMode: 2) == .humanCloseUp, "OBSBOT AI close-up status parse")
expect(OBSBOTAIMode(statusMode: 3, statusSubMode: 0) == .hand, "OBSBOT AI hand status parse")
expect(OBSBOTAIMode(statusMode: 5, statusSubMode: 0) == .desk, "OBSBOT AI desk status parse")
expect(
  OBSBOTAIMode(statusMode: 6, statusSubMode: 0) == .switching, "OBSBOT AI switching status parse")

let knownTiny2Header = [
  0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0x00, 0x00,
  0x0A, 0x02, 0x82, 0x29,
].map(UInt8.init)
let knownTiny2Body = [
  0x05, 0x00, 0x00, 0x00, 0x02, 0x04, 0x00, 0x00, 0x00,
].map(UInt8.init)
expect(OBSBOTRemoteProtocol.crc16(knownTiny2Header) == 0x9158, "OBSBOT V3 header CRC")
expect(OBSBOTRemoteProtocol.crc16(knownTiny2Body) == 0xAFB2, "OBSBOT V3 body CRC")

let sleepPacket = expectNoThrow("build OBSBOT sleep packet") {
  try OBSBOTRemoteProtocol.makeDevRunStatusPacket(.sleep, sequence: 0x0016)
}
expect(sleepPacket.count == 60, "OBSBOT packet length")
expect(
  Array(sleepPacket.prefix(20))
    == [
      0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0xA8, 0xF7,
      0x0A, 0x02, 0xC2, 0xA0, 0x04, 0x00, 0xBF, 0xFB,
      0x01, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT sleep packet bytes"
)
expect(sleepPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT packet padding")

let runPacket = expectNoThrow("build OBSBOT run packet") {
  try OBSBOTRemoteProtocol.makeDevRunStatusPacket(.run, sequence: 0x0016)
}
expect(runPacket.count == 60, "OBSBOT run packet length")
expect(
  Array(runPacket.prefix(20))
    == [
      0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0xA8, 0xF7,
      0x0A, 0x02, 0xC2, 0xA0, 0x04, 0x00, 0xBE, 0x07,
      0x00, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT run packet bytes"
)
expect(runPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT run packet padding")

let gimbalStopPacket = OBSBOTRemoteProtocol.makeGimbalStopPacket(sequence: 0x1234)
expect(gimbalStopPacket.count == 60, "OBSBOT gimbal stop packet length")
expect(
  Array(gimbalStopPacket.prefix(16))
    == [
      0xAA, 0x05, 0x34, 0x12, 0x0C, 0x00, 0x85, 0x04,
      0x0A, 0x04, 0x04, 0x67, 0x00, 0x00, 0xFF, 0xDB,
    ].map(UInt8.init),
  "OBSBOT gimbal stop packet bytes"
)
expect(gimbalStopPacket.dropFirst(16).allSatisfy { $0 == 0 }, "OBSBOT gimbal stop padding")

let tiny3GimbalResetPacket = OBSBOTRemoteProtocol.makeTiny3GimbalResetPacket(sequence: 0x1234)
expect(tiny3GimbalResetPacket.count == 60, "OBSBOT Tiny 3 gimbal reset packet length")
expect(
  Array(tiny3GimbalResetPacket.prefix(22))
    == [
      0xAA, 0x25, 0x34, 0x12, 0x0C, 0x00, 0x8C, 0xDF,
      0x0A, 0x03, 0xC3, 0x00, 0x06, 0x00, 0x6F, 0xE7,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT Tiny 3 gimbal reset packet bytes"
)
expect(
  tiny3GimbalResetPacket.dropFirst(22).allSatisfy { $0 == 0 },
  "OBSBOT Tiny 3 gimbal reset padding")

let factoryRestorePacket = OBSBOTRemoteProtocol.makeFactoryRestorePacket(sequence: 0x1234)
expect(factoryRestorePacket.count == 60, "OBSBOT factory restore packet length")
expect(
  Array(factoryRestorePacket.prefix(17))
    == [
      0xAA, 0x25, 0x34, 0x12, 0x0C, 0x00, 0x8D, 0x31,
      0x0A, 0x02, 0x02, 0xA8, 0x01, 0x00, 0x27, 0xFF,
      0x01,
    ].map(UInt8.init),
  "OBSBOT factory restore packet bytes"
)
expect(
  factoryRestorePacket.dropFirst(17).allSatisfy { $0 == 0 },
  "OBSBOT factory restore padding")

let rebootPacket = OBSBOTRemoteProtocol.makeRebootPacket(sequence: 0x1234)
expect(rebootPacket.count == 60, "OBSBOT reboot packet length")
expect(
  Array(rebootPacket.prefix(20))
    == [
      0xAA, 0x25, 0x34, 0x12, 0x0C, 0x00, 0xDC, 0xF7,
      0x0A, 0x02, 0xC2, 0xA0, 0x04, 0x00, 0xBF, 0xBF,
      0x02, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT reboot packet bytes"
)
expect(rebootPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT reboot packet padding")

let faceAFPacket = OBSBOTRemoteProtocol.makeFaceAutoFocusPacket(enabled: true, sequence: 0x0016)
expect(faceAFPacket.count == 60, "OBSBOT face AF packet length")
expect(
  Array(faceAFPacket.prefix(20))
    == [
      0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0x78, 0x99,
      0x0A, 0x02, 0x02, 0x36, 0x04, 0x00, 0xBF, 0xFB,
      0x01, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT face AF packet bytes"
)
expect(faceAFPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT face AF packet padding")

let brightnessPacket = OBSBOTRemoteProtocol.makeImageAdjustmentPacket(
  .brightness,
  value: 50,
  sequence: 0x0016
)
expect(brightnessPacket.count == 60, "OBSBOT brightness packet length")
expect(
  Array(brightnessPacket.prefix(20))
    == [
      0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0x69, 0x51,
      0x0A, 0x02, 0xC2, 0x29, 0x04, 0x00, 0xB0, 0xBF,
      0x32, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT brightness packet bytes"
)
let contrastPacket = OBSBOTRemoteProtocol.makeImageAdjustmentPacket(
  .contrast,
  value: 50,
  sequence: 0x0016
)
expect(contrastPacket.count == 60, "OBSBOT contrast packet length")
expect(
  Array(contrastPacket.prefix(20))
    == [
      0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0xC8, 0x92,
      0x0A, 0x02, 0x42, 0x2C, 0x04, 0x00, 0xB0, 0xBF,
      0x32, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT contrast packet bytes"
)
expect(contrastPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT contrast packet padding")
let saturationPacket = OBSBOTRemoteProtocol.makeImageAdjustmentPacket(
  .saturation,
  value: 50,
  sequence: 0x0016
)
expect(saturationPacket.count == 60, "OBSBOT saturation packet length")
expect(
  Array(saturationPacket.prefix(20))
    == [
      0xAA, 0x25, 0x16, 0x00, 0x0C, 0x00, 0x09, 0x52,
      0x0A, 0x02, 0x42, 0x2D, 0x04, 0x00, 0xB0, 0xBF,
      0x32, 0x00, 0x00, 0x00,
    ].map(UInt8.init),
  "OBSBOT saturation packet bytes"
)
expect(saturationPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT saturation packet padding")
expect(
  OBSBOTRemoteProtocol.clampedImageAdjustmentValue(150) == 100,
  "OBSBOT image adjustment clamp"
)
let uvcImageRange = UVCScalarRange(minimum: 0, maximum: 255, resolution: 1, defaultValue: 128)
expect(
  OBSBOTRemoteProtocol.imageAdjustmentRawValue(50, range: uvcImageRange) == 128,
  "OBSBOT image percent maps neutral to UVC default"
)
expect(
  OBSBOTRemoteProtocol.imageAdjustmentRawValue(100, range: uvcImageRange) == 255,
  "OBSBOT image percent maps max to UVC max"
)
let wideRawImageRange = UVCScalarRange(
  minimum: 0,
  maximum: 11_824,
  resolution: 1,
  defaultValue: 5_912
)
expect(
  OBSBOTRemoteProtocol.imageAdjustmentPercent(rawValue: 5_912, range: wideRawImageRange) == 50,
  "OBSBOT image raw default maps to neutral percent"
)
expect(brightnessPacket.dropFirst(20).allSatisfy { $0 == 0 }, "OBSBOT brightness packet padding")

let humanNormalPayload = expectNoThrow("build OBSBOT human normal AI payload") {
  try OBSBOTRemoteProtocol.makeAIModePayload(.humanNormal)
}
expect(
  Array(humanNormalPayload.prefix(4)) == [0x16, 0x02, 0x02, 0x00],
  "OBSBOT human normal AI payload bytes"
)

let humanUpperBodyPayload = expectNoThrow("build OBSBOT human upper-body AI payload") {
  try OBSBOTRemoteProtocol.makeAIModePayload(.humanUpperBody)
}
expect(
  Array(humanUpperBodyPayload.prefix(4)) == [0x16, 0x02, 0x02, 0x01],
  "OBSBOT human upper-body AI payload bytes"
)

let humanCloseUpPayload = expectNoThrow("build OBSBOT human close-up AI payload") {
  try OBSBOTRemoteProtocol.makeAIModePayload(.humanCloseUp)
}
expect(
  Array(humanCloseUpPayload.prefix(4)) == [0x16, 0x02, 0x02, 0x02],
  "OBSBOT human close-up AI payload bytes"
)

let handPayload = expectNoThrow("build OBSBOT hand AI payload") {
  try OBSBOTRemoteProtocol.makeAIModePayload(.hand)
}
expect(handPayload.count == 60, "OBSBOT AI payload length")
expect(Array(handPayload.prefix(4)) == [0x16, 0x02, 0x03, 0x00], "OBSBOT hand AI payload bytes")
expect(handPayload.dropFirst(4).allSatisfy { $0 == 0 }, "OBSBOT AI payload padding")

let deskPayload = expectNoThrow("build OBSBOT desk AI payload") {
  try OBSBOTRemoteProtocol.makeAIModePayload(.desk)
}
expect(Array(deskPayload.prefix(4)) == [0x16, 0x02, 0x05, 0x00], "OBSBOT desk AI payload bytes")

let hdrPayload = OBSBOTRemoteProtocol.makeHDRPayload(enabled: true)
expect(Array(hdrPayload.prefix(3)) == [0x01, 0x01, 0x01], "OBSBOT HDR payload bytes")
let faceAEPayload = OBSBOTRemoteProtocol.makeFaceAEPayload(enabled: false)
expect(Array(faceAEPayload.prefix(3)) == [0x03, 0x01, 0x00], "OBSBOT face AE payload bytes")
let fovPayload = expectNoThrow("build OBSBOT fov payload") {
  try OBSBOTRemoteProtocol.makeFieldOfViewPayload(.medium)
}
expect(Array(fovPayload.prefix(3)) == [0x04, 0x01, 0x01], "OBSBOT FOV payload bytes")
let gesturePayload = OBSBOTRemoteProtocol.makeGestureControlPayload(
  autoFrameEnabled: true,
  autoFrameMode: .halfBody,
  zoomEnabled: true,
  zoomRatio: 200
)
expect(
  Array(gesturePayload.prefix(7)) == [0x20, 0x05, 0x01, 0x02, 0x01, 0xC8, 0x00],
  "OBSBOT gesture payload bytes")
expect(gesturePayload.dropFirst(7).allSatisfy { $0 == 0 }, "OBSBOT gesture payload padding")
let gestureTargetPacket = OBSBOTRemoteProtocol.makeTinyGestureControlPacket(
  .targetSelection,
  enabled: false,
  sequence: 0x0016
)
expect(gestureTargetPacket.count == 60, "OBSBOT gesture target packet length")
expect(gestureTargetPacket[8] == 0x0A, "OBSBOT gesture target device byte")
expect(gestureTargetPacket[9] == 0x04, "OBSBOT gesture target route byte")
expect(gestureTargetPacket[10] == 0xC4, "OBSBOT gesture target command set/id low byte")
expect(gestureTargetPacket[11] == 0x30, "OBSBOT gesture target command id high byte")
expect(gestureTargetPacket[12] == 0x01, "OBSBOT gesture target payload length")
expect(gestureTargetPacket[16] == 0x00, "OBSBOT gesture target disabled payload")
expect(
  gestureTargetPacket.dropFirst(17).allSatisfy { $0 == 0 },
  "OBSBOT gesture target packet padding")
let gestureZoomPacket = OBSBOTRemoteProtocol.makeTinyGestureControlPacket(
  .zoom,
  enabled: false,
  sequence: 0x0016
)
expect(gestureZoomPacket[10] == 0x44, "OBSBOT gesture zoom command set/id low byte")
expect(gestureZoomPacket[11] == 0x31, "OBSBOT gesture zoom command id high byte")
let gestureDynamicPacket = OBSBOTRemoteProtocol.makeTinyGestureControlPacket(
  .dynamicZoom,
  enabled: false,
  sequence: 0x0016
)
expect(gestureDynamicPacket[10] == 0x44, "OBSBOT gesture dynamic command set/id low byte")
expect(gestureDynamicPacket[11] == 0x33, "OBSBOT gesture dynamic command id high byte")
let gestureDirectionPacket = OBSBOTRemoteProtocol.makeTinyGestureControlPacket(
  .dynamicZoomDirection,
  enabled: false,
  sequence: 0x0016
)
expect(gestureDirectionPacket[10] == 0xC4, "OBSBOT gesture direction command set/id low byte")
expect(gestureDirectionPacket[11] == 0x33, "OBSBOT gesture direction command id high byte")
let gestureRecordPacket = OBSBOTRemoteProtocol.makeTinyGestureControlPacket(
  .record,
  enabled: false,
  sequence: 0x0016
)
expect(gestureRecordPacket[10] == 0xC4, "OBSBOT gesture record command set/id low byte")
expect(gestureRecordPacket[11] == 0x31, "OBSBOT gesture record command id high byte")
let gestureMasterPacket = OBSBOTRemoteProtocol.makeTinyGestureParameterPacket(
  .master,
  enabled: false,
  sequence: 0x0016
)
expect(gestureMasterPacket.count == 60, "OBSBOT gesture master packet length")
expect(gestureMasterPacket[10] == 0x44, "OBSBOT gesture master command set/id low byte")
expect(gestureMasterPacket[11] == 0x34, "OBSBOT gesture master command id high byte")
expect(gestureMasterPacket[12] == 0x05, "OBSBOT gesture master payload length")
expect(
  Array(gestureMasterPacket[16..<21]) == [0x00, 0x00, 0x00, 0x00, 0x00],
  "OBSBOT gesture master disabled payload")
expect(
  gestureMasterPacket.dropFirst(21).allSatisfy { $0 == 0 },
  "OBSBOT gesture master packet padding")
let virtualTrackGesturePacket = OBSBOTRemoteProtocol.makeVirtualTrackGesturePacket(
  enabled: false,
  sequence: 0x0016
)
expect(virtualTrackGesturePacket.count == 60, "OBSBOT virtual-track gesture packet length")
expect(virtualTrackGesturePacket[10] == 0x82, "OBSBOT virtual-track gesture command low byte")
expect(virtualTrackGesturePacket[11] == 0xAC, "OBSBOT virtual-track gesture command high byte")
expect(virtualTrackGesturePacket[12] == 0x0C, "OBSBOT virtual-track gesture payload length")
expect(
  Array(virtualTrackGesturePacket[16..<28]) == Array(repeating: UInt8(0), count: 12),
  "OBSBOT virtual-track gesture disabled payload")
let virtualTrackEnabledPacket = OBSBOTRemoteProtocol.makeVirtualTrackEnabledPacket(
  enabled: false,
  sequence: 0x0016
)
expect(virtualTrackEnabledPacket.count == 60, "OBSBOT virtual-track enabled packet length")
expect(virtualTrackEnabledPacket[10] == 0x82, "OBSBOT virtual-track enabled command low byte")
expect(virtualTrackEnabledPacket[11] == 0xAE, "OBSBOT virtual-track enabled command high byte")
expect(virtualTrackEnabledPacket[12] == 0x01, "OBSBOT virtual-track enabled payload length")
expect(virtualTrackEnabledPacket[16] == 0x00, "OBSBOT virtual-track enabled disabled payload")
let legacyGestureControlPacket = OBSBOTRemoteProtocol.makeTinyLegacyGestureControlPacket(
  enabled: false,
  sequence: 0x0016
)
expect(legacyGestureControlPacket.count == 60, "OBSBOT legacy gesture control packet length")
expect(legacyGestureControlPacket[10] == 0x43, "OBSBOT legacy gesture control command low byte")
expect(legacyGestureControlPacket[11] == 0x03, "OBSBOT legacy gesture control command high byte")
expect(legacyGestureControlPacket[12] == 0x02, "OBSBOT legacy gesture control payload length")
expect(
  Array(legacyGestureControlPacket[16..<18]) == [0x05, 0x00],
  "OBSBOT legacy gesture control disabled payload")
let legacyAIEnabledPacket = OBSBOTRemoteProtocol.makeTinyLegacyAIEnabledPacket(
  enabled: false,
  sequence: 0x0016
)
expect(legacyAIEnabledPacket.count == 60, "OBSBOT legacy AI enabled packet length")
expect(legacyAIEnabledPacket[10] == 0x43, "OBSBOT legacy AI enabled command low byte")
expect(legacyAIEnabledPacket[11] == 0x03, "OBSBOT legacy AI enabled command high byte")
expect(legacyAIEnabledPacket[12] == 0x02, "OBSBOT legacy AI enabled payload length")
expect(
  Array(legacyAIEnabledPacket[16..<18]) == [0x00, 0x00],
  "OBSBOT legacy AI enabled disabled payload")
let aiEnabledPacket = OBSBOTRemoteProtocol.makeTinyAIEnabledPacket(
  enabled: false,
  sequence: 0x0016
)
expect(aiEnabledPacket.count == 60, "OBSBOT AI enabled packet length")
expect(aiEnabledPacket[10] == 0x44, "OBSBOT AI enabled command set/id low byte")
expect(aiEnabledPacket[11] == 0x02, "OBSBOT AI enabled command id high byte")
expect(aiEnabledPacket[12] == 0x01, "OBSBOT AI enabled payload length")
expect(aiEnabledPacket[16] == 0x00, "OBSBOT AI enabled disabled payload")
let gestureDisableAllPlan = OBSBOTTinyGestureCommandPlan.all(
  enabled: false,
  startingSequence: 0x0016
)
expect(gestureDisableAllPlan.count == 16, "OBSBOT gesture disable-all write count")
expect(
  gestureDisableAllPlan.first?.name == "tiny.control.targetSelection=off",
  "OBSBOT gesture disable-all starts with individual gesture controls")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.control.record=off" },
  "OBSBOT gesture disable-all includes individual record control")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.parameter.snapshot=off" },
  "OBSBOT gesture disable-all includes snapshot parameter")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.parameter.rolling=off" },
  "OBSBOT gesture disable-all includes rolling parameter")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.track.panEnabled=off" },
  "OBSBOT gesture disable-all includes pan tracking")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.track.pitchEnabled=off" },
  "OBSBOT gesture disable-all includes pitch tracking")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.handTrackGimbal=off" },
  "OBSBOT gesture disable-all includes hand-track gimbal")
expect(
  gestureDisableAllPlan.contains { $0.name == "tiny.parameter.master=off" },
  "OBSBOT gesture disable-all includes master parameter")
expect(
  !gestureDisableAllPlan.contains { $0.name.contains("AI") || $0.name.contains("legacy") },
  "OBSBOT gesture disable-all avoids global AI and legacy commands")
let gestureEnableAllPlan = OBSBOTTinyGestureCommandPlan.all(
  enabled: true,
  startingSequence: 0x0016
)
expect(gestureEnableAllPlan.count == 16, "OBSBOT gesture enable-all write count")
expect(
  gestureEnableAllPlan.first?.name == "tiny.control.targetSelection=on",
  "OBSBOT gesture enable-all starts with individual gesture controls")
expect(
  gestureEnableAllPlan[5].name == "tiny.handTrackGimbal=on"
    && gestureEnableAllPlan[6].name == "tiny.track.panEnabled=on"
    && gestureEnableAllPlan[7].name == "tiny.track.pitchEnabled=on",
  "OBSBOT gesture enable-all enables hand tracking")
expect(
  gestureEnableAllPlan.last?.name == "tiny.parameter.master=on",
  "OBSBOT gesture enable-all ends with gesture master")
expect(
  gestureEnableAllPlan.contains { $0.name == "tiny.parameter.targetSelection=on" }
    && gestureEnableAllPlan.contains { $0.name == "tiny.control.targetSelection=on" },
  "OBSBOT gesture enable-all uses SDK gesture parameters and individual controls")
expect(
  gestureEnableAllPlan.contains { $0.name == "tiny.parameter.snapshot=on" },
  "OBSBOT gesture enable-all includes snapshot parameter")
expect(
  gestureEnableAllPlan.contains { $0.name == "tiny.parameter.rolling=on" },
  "OBSBOT gesture enable-all includes rolling parameter")
expect(
  gestureEnableAllPlan.contains { $0.name == "tiny.parameter.record=on" }
    && gestureEnableAllPlan.contains { $0.name == "tiny.control.record=on" },
  "OBSBOT gesture enable-all includes record parameter and control")
let gestureTrackPacket = OBSBOTRemoteProtocol.makeTinyGestureTrackParameterPacket(
  .panEnabled,
  enabled: false,
  sequence: 0x0016
)
expect(gestureTrackPacket[10] == 0x44, "OBSBOT gesture track command set/id low byte")
expect(gestureTrackPacket[11] == 0x20, "OBSBOT gesture track command id high byte")
expect(gestureTrackPacket[12] == 0x05, "OBSBOT gesture track payload length")
expect(
  Array(gestureTrackPacket[16..<21]) == [0x06, 0x00, 0x00, 0x00, 0x00],
  "OBSBOT gesture track disabled payload")
let handTrackGimbalPacket = OBSBOTRemoteProtocol.makeTinyHandTrackGimbalPacket(
  enabled: false,
  sequence: 0x0016
)
expect(handTrackGimbalPacket[10] == 0xC4, "OBSBOT hand-track gimbal command set/id low byte")
expect(handTrackGimbalPacket[11] == 0x26, "OBSBOT hand-track gimbal command id high byte")
expect(handTrackGimbalPacket[12] == 0x01, "OBSBOT hand-track gimbal payload length")
expect(handTrackGimbalPacket[16] == 0x00, "OBSBOT hand-track gimbal disabled payload")
let aiStatusGetPacket = OBSBOTRemoteProtocol.makeTinyAIStatusGetPacket(sequence: 0x0016)
expect(aiStatusGetPacket.count == 60, "OBSBOT AI status get packet length")
expect(aiStatusGetPacket[10] == 0x04, "OBSBOT AI status get command set/id low byte")
expect(aiStatusGetPacket[11] == 0x01, "OBSBOT AI status get command id high byte")
expect(aiStatusGetPacket[12] == 0x00, "OBSBOT AI status get payload length")
let gestureZoomGetPacket = OBSBOTRemoteProtocol.makeTinyGestureParameterGetPacket(
  .zoom,
  sequence: 0x0016
)
expect(gestureZoomGetPacket.count == 60, "OBSBOT gesture get packet length")
expect(gestureZoomGetPacket[10] == 0x84, "OBSBOT gesture get command set/id low byte")
expect(gestureZoomGetPacket[11] == 0x34, "OBSBOT gesture get command id high byte")
expect(gestureZoomGetPacket[12] == 0x04, "OBSBOT gesture get payload length")
expect(
  Array(gestureZoomGetPacket[16..<20]) == [0x02, 0x00, 0x00, 0x00],
  "OBSBOT gesture get payload")
var gestureZoomResponse = [UInt8](repeating: 0, count: 60)
gestureZoomResponse[0] = 0xAA
gestureZoomResponse[1] = 0x21
gestureZoomResponse[2] = 0x16
gestureZoomResponse[10] = 0x84
gestureZoomResponse[11] = 0x34
gestureZoomResponse[12] = 0x01
gestureZoomResponse[16] = 0x01
let gestureZoomValue = expectNoThrow("parse OBSBOT gesture readback response") {
  try OBSBOTRemoteProtocol.tinyGestureParameterValue(
    fromResponse: gestureZoomResponse,
    parameter: .zoom,
    matchingSequence: 0x0016)
}
expect(gestureZoomValue, "OBSBOT gesture readback value")
var aiStatusResponse = [UInt8](repeating: 0, count: 60)
aiStatusResponse[0] = 0xAA
aiStatusResponse[1] = 0x21
aiStatusResponse[2] = 0x16
aiStatusResponse[10] = 0x04
aiStatusResponse[11] = 0x01
aiStatusResponse[12] = 0x08
aiStatusResponse[19] = 0x45
let aiStatusGestureState = expectNoThrow("parse OBSBOT AI status gesture response") {
  try OBSBOTRemoteProtocol.tinyGestureState(
    fromAIStatusResponse: aiStatusResponse,
    matchingSequence: 0x0016)
}
expect(aiStatusGestureState.master, "OBSBOT AI status gesture master")
expect(aiStatusGestureState.targetSelection, "OBSBOT AI status gesture target")
expect(!aiStatusGestureState.zoom, "OBSBOT AI status gesture zoom")
expect(aiStatusGestureState.dynamicZoom, "OBSBOT AI status gesture dynamic zoom")
expect(aiStatusGestureState.mirror, "OBSBOT AI status gesture direction")
do {
  _ = try OBSBOTRemoteProtocol.tinyGestureParameterValue(
    fromResponse: [UInt8](repeating: 0, count: 60),
    parameter: .zoom,
    matchingSequence: 0x0016)
  expect(false, "OBSBOT gesture readback rejects non-frame response")
} catch {
  // expected
}
do {
  _ = try OBSBOTRemoteProtocol.tinyGestureParameterValue(
    fromResponse: [0x01],
    parameter: .zoom,
    matchingSequence: 0x0016)
  expect(false, "OBSBOT gesture readback rejects one-byte ACK response")
} catch {
  // expected
}
var statusBytes = [UInt8](repeating: 0, count: 60)
statusBytes[6] = 1
statusBytes[7] = 1
statusBytes[13] = 1
statusBytes[14] = 1
statusBytes[17] = 2
statusBytes[38] = 0x8D
statusBytes[39] = 0x0C
let settingsSnapshot = expectNoThrow("parse OBSBOT camera settings") {
  try OBSBOTCameraSettingsSnapshot(statusBytes: statusBytes)
}
expect(settingsSnapshot.hdrEnabled, "OBSBOT HDR status parse")
expect(settingsSnapshot.faceAutoExposureEnabled, "OBSBOT face AE status parse")
expect(settingsSnapshot.faceAutoFocusEnabled, "OBSBOT face focus status parse")
expect(settingsSnapshot.autoFocusEnabled, "OBSBOT auto focus status parse")
expect(settingsSnapshot.fieldOfView == .narrow, "OBSBOT FOV status parse")
let gestureSnapshot = expectNoThrow("parse OBSBOT gesture settings") {
  try OBSBOTGestureSettingsSnapshot(statusBytes: statusBytes)
}
expect(gestureSnapshot.autoFrameEnabled, "OBSBOT gesture auto-frame status parse")
expect(gestureSnapshot.autoFrameMode == .halfBody, "OBSBOT gesture mode status parse")
expect(gestureSnapshot.zoomEnabled, "OBSBOT gesture zoom status parse")
expect(gestureSnapshot.zoomRatio == 200, "OBSBOT gesture zoom ratio status parse")

print("self-test passed")
