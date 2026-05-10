import Carbon
import Foundation
import ObsbotRemoteControl
import ObsbotRemoteCore

struct RemoteHotKeySpec {
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
  private static let repeatInitialDelay: TimeInterval = 0.25
  private static let repeatInterval: TimeInterval = 0.18

  private let buttonCaptureURL: URL
  private let coordinator: CameraControlCoordinator
  private let log: @Sendable (String) -> Void

  private var buttonByID: [UInt32: String] = [:]
  private var hotKeyRefs: [EventHotKeyRef] = []
  private var repeatTimers: [UInt32: DispatchSourceTimer] = [:]
  private var handlerRef: EventHandlerRef?
  private let stateLock = NSLock()
  private var actionGeneration: UInt64 = 0
  private var acceptingActions = false
  private var running = false

  init(
    buttonCaptureURL: URL,
    coordinator: CameraControlCoordinator,
    log: @escaping @Sendable (String) -> Void
  ) {
    self.buttonCaptureURL = buttonCaptureURL
    self.coordinator = coordinator
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

    Self.activeSession = self

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
      beginAcceptingActions()
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
    invalidatePendingActions()
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
      let generation = currentActionGeneration()
      coordinator.commandQueue.async { [weak self] in
        self?.runCameraAction(for: button, generation: generation)
      }
      return
    }

    guard repeatTimers[id] == nil else {
      return
    }

    let generation = currentActionGeneration()
    coordinator.commandQueue.async { [weak self] in
      self?.runCameraAction(for: button, generation: generation)
    }
    startRepeatingHotKey(id: id, button: button, generation: generation)
  }

  fileprivate func handleHotKeyReleased(id: UInt32) {
    stopRepeatingHotKey(id: id)
  }

  private func startRepeatingHotKey(id: UInt32, button: String, generation: UInt64) {
    let timer = DispatchSource.makeTimerSource(queue: coordinator.commandQueue)
    timer.schedule(
      deadline: .now() + Self.repeatInitialDelay,
      repeating: Self.repeatInterval
    )
    timer.setEventHandler { [weak self] in
      self?.runCameraAction(for: button, generation: generation)
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

  private func runCameraAction(for button: String, generation: UInt64) {
    guard isCurrentActionGeneration(generation) else {
      return
    }

    do {
      let result = try coordinator.performRemoteButtonOnCommandQueue(button)
      log(userFacingActionLog(button: button, result: result))
    } catch let error as UVCRequestError {
      log("\(button): camera error: \(error.description)")
    } catch {
      log("\(button): error: \(error)")
    }
  }

  private func invalidatePendingActions() {
    stateLock.lock()
    acceptingActions = false
    actionGeneration &+= 1
    stateLock.unlock()
  }

  private func beginAcceptingActions() {
    stateLock.lock()
    acceptingActions = true
    actionGeneration &+= 1
    stateLock.unlock()
  }

  private func currentActionGeneration() -> UInt64 {
    stateLock.lock()
    defer { stateLock.unlock() }
    return actionGeneration
  }

  private func isCurrentActionGeneration(_ generation: UInt64) -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return acceptingActions && generation == actionGeneration
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
