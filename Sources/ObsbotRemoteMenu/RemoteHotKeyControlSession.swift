import Carbon
import Foundation
import ObsbotRemoteControl
import ObsbotRemoteCore

private struct RemoteHotKeySpec {
  var id: UInt32
  var button: String
  var keyCode: UInt32
  var modifiers: UInt32
}

enum RemoteHotKeyControlSessionError: Error, CustomStringConvertible {
  case alreadyRunning
  case handlerInstallFailed(OSStatus)
  case noHotKeysRegistered

  var description: String {
    switch self {
    case .alreadyRunning:
      return "remote control is already running"
    case .handlerInstallFailed(let status):
      return "failed to install remote shortcut handler: \(status)"
    case .noHotKeysRegistered:
      return "no enabled remote shortcuts could be registered"
    }
  }
}

final class RemoteHotKeyControlSession: @unchecked Sendable {
  fileprivate nonisolated(unsafe) static var activeSession: RemoteHotKeyControlSession?
  fileprivate static let hotKeySignature = fourCharacterCode("OBSR")
  private static let actionQueue = DispatchQueue(label: "OBSBOT Remote HotKey Actions")
  private static let repeatInitialDelay: TimeInterval = 0.25
  private static let repeatInterval: TimeInterval = 0.18

  private let buttonCaptureURL: URL
  private let log: @Sendable (String) -> Void

  private var controller: UVCController?
  private var buttonByID: [UInt32: String] = [:]
  private var hotKeyRefs: [EventHotKeyRef] = []
  private var repeatTimers: [UInt32: DispatchSourceTimer] = [:]
  private var handlerRef: EventHandlerRef?
  private var running = false

  init(buttonCaptureURL: URL, log: @escaping @Sendable (String) -> Void) {
    self.buttonCaptureURL = buttonCaptureURL
    self.log = log
  }

  func start() throws {
    guard !running else {
      throw RemoteHotKeyControlSessionError.alreadyRunning
    }
    guard Self.activeSession == nil else {
      throw RemoteHotKeyControlSessionError.alreadyRunning
    }

    let data = try Data(contentsOf: buttonCaptureURL)
    let capture = try JSONDecoder().decode(ButtonMapCapture.self, from: data)
    let specs = remoteHotKeySpecs(from: capture.buttons)

    let controller = UVCController()
    Self.activeSession = self
    self.controller = controller

    do {
      try installHandler()
      var failures: [(String, OSStatus)] = []
      for spec in specs {
        let status = register(spec)
        if status != noErr {
          failures.append((spec.button, status))
        }
      }

      guard !hotKeyRefs.isEmpty else {
        throw RemoteHotKeyControlSessionError.noHotKeysRegistered
      }

      running = true
      log("Remote control ready. \(hotKeyRefs.count) remote buttons active.")
      for failure in failures {
        log("\(failure.0): could not activate shortcut (\(failure.1)).")
      }
    } catch {
      stop()
      throw error
    }
  }

  func stop() {
    stopRepeatingAllHotKeys()

    for ref in hotKeyRefs {
      UnregisterEventHotKey(ref)
    }
    hotKeyRefs.removeAll()
    buttonByID.removeAll()

    if let handlerRef {
      RemoveEventHandler(handlerRef)
      self.handlerRef = nil
    }

    controller = nil
    if Self.activeSession === self {
      Self.activeSession = nil
    }

    if running {
      running = false
      log("Remote control stopped.")
    }
  }

  private func installHandler() throws {
    var eventSpecs = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      ),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyReleased)
      ),
    ]
    var handler: EventHandlerRef?
    let status = eventSpecs.withUnsafeMutableBufferPointer { buffer in
      InstallEventHandler(
        GetApplicationEventTarget(),
        remoteHotKeyEventHandler,
        buffer.count,
        buffer.baseAddress,
        nil,
        &handler
      )
    }
    guard status == noErr, let handler else {
      throw RemoteHotKeyControlSessionError.handlerInstallFailed(status)
    }
    handlerRef = handler
  }

  private func register(_ spec: RemoteHotKeySpec) -> OSStatus {
    let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: spec.id)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      spec.keyCode,
      spec.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    if status == noErr, let ref {
      hotKeyRefs.append(ref)
      buttonByID[spec.id] = spec.button
    }
    return status
  }

  fileprivate func handleHotKeyPressed(id: UInt32) {
    guard let button = buttonByID[id] else {
      return
    }

    guard isRepeatableRemoteButton(button) else {
      Self.actionQueue.async { [weak self] in
        self?.runCameraAction(for: button)
      }
      return
    }

    guard repeatTimers[id] == nil else {
      return
    }

    Self.actionQueue.async { [weak self] in
      self?.runCameraAction(for: button)
    }
    startRepeatingHotKey(id: id, button: button)
  }

  fileprivate func handleHotKeyReleased(id: UInt32) {
    stopRepeatingHotKey(id: id)
  }

  private func startRepeatingHotKey(id: UInt32, button: String) {
    let timer = DispatchSource.makeTimerSource(queue: Self.actionQueue)
    timer.schedule(
      deadline: .now() + Self.repeatInitialDelay,
      repeating: Self.repeatInterval
    )
    timer.setEventHandler { [weak self] in
      self?.runCameraAction(for: button)
    }
    repeatTimers[id] = timer
    timer.resume()
  }

  private func stopRepeatingHotKey(id: UInt32) {
    guard let timer = repeatTimers.removeValue(forKey: id) else {
      return
    }
    timer.cancel()
  }

  private func stopRepeatingAllHotKeys() {
    for timer in repeatTimers.values {
      timer.cancel()
    }
    repeatTimers.removeAll()
  }

  private func runCameraAction(for button: String) {
    guard let controller else {
      return
    }

    do {
      let result = try remoteCameraActionDescription(for: button, controller: controller)
      log(userFacingActionLog(button: button, result: result))
    } catch let error as UVCRequestError {
      log("\(button): camera error: \(error.description)")
    } catch {
      log("\(button): error: \(error)")
    }
  }
}

private let remoteHotKeyEventHandler: EventHandlerUPP = { _, event, _ in
  guard let event else {
    return OSStatus(eventNotHandledErr)
  }

  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  guard status == noErr, hotKeyID.signature == RemoteHotKeyControlSession.hotKeySignature else {
    return OSStatus(eventNotHandledErr)
  }

  switch GetEventKind(event) {
  case UInt32(kEventHotKeyPressed):
    RemoteHotKeyControlSession.activeSession?.handleHotKeyPressed(id: hotKeyID.id)
  case UInt32(kEventHotKeyReleased):
    RemoteHotKeyControlSession.activeSession?.handleHotKeyReleased(id: hotKeyID.id)
  default:
    return OSStatus(eventNotHandledErr)
  }
  return noErr
}

private func remoteHotKeySpecs(from captures: [ButtonCapture]) -> [RemoteHotKeySpec] {
  var nextID: UInt32 = 1
  var specs: [RemoteHotKeySpec] = []

  for capture in captures where !capture.skipped && capture.enabled {
    guard let shortcut = remoteHotKeyShortcut(from: capture.events) else {
      continue
    }
    specs.append(
      RemoteHotKeySpec(
        id: nextID,
        button: capture.button,
        keyCode: shortcut.keyCode,
        modifiers: shortcut.modifiers
      )
    )
    nextID += 1
  }

  return specs
}

private func userFacingActionLog(button: String, result: String) -> String {
  switch button {
  case "On/Off":
    return "On/Off: \(powerActionDescription(from: result))"
  case "Gimbal Up":
    return "Gimbal Up: moved camera up."
  case "Gimbal Down":
    return "Gimbal Down: moved camera down."
  case "Gimbal Left":
    return "Gimbal Left: moved camera left."
  case "Gimbal Right":
    return "Gimbal Right: moved camera right."
  case "Gimbal Reset":
    return "Gimbal Reset: centered camera."
  case "Zoom In":
    return "Zoom In: zoomed in."
  case "Zoom Out":
    return "Zoom Out: zoomed out."
  case "Track":
    return "Track: \(aiModeActionDescription(label: "human tracking", result: result))"
  case "Close-up":
    return "Close-up: \(aiModeActionDescription(label: "close-up tracking", result: result))"
  case "Hand Track":
    return "Hand Track: \(aiModeActionDescription(label: "hand tracking", result: result))"
  case "Desk Mode":
    return "Desk Mode: \(aiModeActionDescription(label: "desk mode", result: result))"
  case "Choose Device 1", "Choose Device 2", "Choose Device 3", "Choose Device 4":
    return "\(button): no camera action assigned."
  default:
    if result == "ignored" {
      return "\(button): ignored."
    }
    if result == "unsupported" {
      return "\(button): unsupported."
    }
    return "\(button): \(result)"
  }
}

private func isRepeatableRemoteButton(_ button: String) -> Bool {
  switch button {
  case "Gimbal Up", "Gimbal Down", "Gimbal Left", "Gimbal Right", "Zoom In", "Zoom Out":
    return true
  default:
    return false
  }
}

private func powerActionDescription(from result: String) -> String {
  if result.contains("sleep -> run") {
    return "woke camera."
  }
  if result.contains("run -> sleep") {
    return "put camera to sleep."
  }
  return "toggled camera power."
}

private func aiModeActionDescription(label: String, result: String) -> String {
  if result.hasSuffix(" -> off") {
    return "turned \(label) off."
  }
  return "turned \(label) on."
}

private func remoteHotKeyShortcut(from events: [HIDEventRecord]) -> (
  keyCode: UInt32, modifiers: UInt32
)? {
  var keyCode: UInt32?
  var modifiers: UInt32 = 0

  for event in events where event.usagePage == 7 && event.state == "down" {
    switch event.usage {
    case 0xE0, 0xE4:
      modifiers |= UInt32(controlKey)
    case 0xE1, 0xE5:
      modifiers |= UInt32(shiftKey)
    case 0xE2, 0xE6:
      modifiers |= UInt32(optionKey)
    case 0xE3, 0xE7:
      modifiers |= UInt32(cmdKey)
    case 0x01:
      continue
    default:
      guard keyCode == nil, let mappedKeyCode = carbonKeyCode(forHIDUsage: event.usage) else {
        return nil
      }
      keyCode = mappedKeyCode
    }
  }

  guard let keyCode else {
    return nil
  }
  return (keyCode, modifiers)
}

private func carbonKeyCode(forHIDUsage usage: UInt32) -> UInt32? {
  switch usage {
  case 0x04: UInt32(kVK_ANSI_A)
  case 0x05: UInt32(kVK_ANSI_B)
  case 0x06: UInt32(kVK_ANSI_C)
  case 0x07: UInt32(kVK_ANSI_D)
  case 0x08: UInt32(kVK_ANSI_E)
  case 0x09: UInt32(kVK_ANSI_F)
  case 0x0A: UInt32(kVK_ANSI_G)
  case 0x0B: UInt32(kVK_ANSI_H)
  case 0x0C: UInt32(kVK_ANSI_I)
  case 0x0D: UInt32(kVK_ANSI_J)
  case 0x0E: UInt32(kVK_ANSI_K)
  case 0x0F: UInt32(kVK_ANSI_L)
  case 0x10: UInt32(kVK_ANSI_M)
  case 0x11: UInt32(kVK_ANSI_N)
  case 0x12: UInt32(kVK_ANSI_O)
  case 0x13: UInt32(kVK_ANSI_P)
  case 0x14: UInt32(kVK_ANSI_Q)
  case 0x15: UInt32(kVK_ANSI_R)
  case 0x16: UInt32(kVK_ANSI_S)
  case 0x17: UInt32(kVK_ANSI_T)
  case 0x18: UInt32(kVK_ANSI_U)
  case 0x19: UInt32(kVK_ANSI_V)
  case 0x1A: UInt32(kVK_ANSI_W)
  case 0x1B: UInt32(kVK_ANSI_X)
  case 0x1C: UInt32(kVK_ANSI_Y)
  case 0x1D: UInt32(kVK_ANSI_Z)
  case 0x1E: UInt32(kVK_ANSI_1)
  case 0x1F: UInt32(kVK_ANSI_2)
  case 0x20: UInt32(kVK_ANSI_3)
  case 0x21: UInt32(kVK_ANSI_4)
  case 0x22: UInt32(kVK_ANSI_5)
  case 0x23: UInt32(kVK_ANSI_6)
  case 0x24: UInt32(kVK_ANSI_7)
  case 0x25: UInt32(kVK_ANSI_8)
  case 0x26: UInt32(kVK_ANSI_9)
  case 0x27: UInt32(kVK_ANSI_0)
  case 0x2D: UInt32(kVK_ANSI_Minus)
  case 0x2E: UInt32(kVK_ANSI_Equal)
  case 0x2F: UInt32(kVK_ANSI_LeftBracket)
  case 0x30: UInt32(kVK_ANSI_RightBracket)
  case 0x31: UInt32(kVK_ANSI_Backslash)
  case 0x33: UInt32(kVK_ANSI_Semicolon)
  case 0x36: UInt32(kVK_ANSI_Comma)
  case 0x37: UInt32(kVK_ANSI_Period)
  case 0x38: UInt32(kVK_ANSI_Slash)
  case 0x4F: UInt32(kVK_RightArrow)
  case 0x50: UInt32(kVK_LeftArrow)
  case 0x51: UInt32(kVK_DownArrow)
  case 0x52: UInt32(kVK_UpArrow)
  default: nil
  }
}

private func fourCharacterCode(_ string: StaticString) -> OSType {
  let bytes = Array(
    string.utf8Start.withMemoryRebound(to: UInt8.self, capacity: string.utf8CodeUnitCount) {
      UnsafeBufferPointer(start: $0, count: string.utf8CodeUnitCount)
    })
  precondition(bytes.count == 4)
  return bytes.reduce(0) { result, byte in
    (result << 8) | OSType(byte)
  }
}
