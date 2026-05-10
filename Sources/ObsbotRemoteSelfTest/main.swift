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
  9, 2, 62, 0, 1, 1, 0, 0x80, 50,
  9, 4, 0, 0, 0, 0x0E, 0x01, 0, 0,
  18, 0x24, 0x02, 3, 0x01, 0x02, 0, 0,
  0, 0, 0, 0, 0, 0, 3, 0, 0x14, 0,
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

print("self-test passed")
