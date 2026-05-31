import Foundation
import ObsbotRemoteCore

extension CommandLineTool {
  func runCameraGesture(arguments: [String]) throws {
    let options = try CameraGestureOptions.parse(arguments)
    if options.dryRun {
      try printOBSBOTGestureDryRun(options)
      return
    }

    let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

    if let allTinyGestures = options.allTinyGestures {
      try controller.setOBSBOTHandGestureControls(enabled: allTinyGestures)
      print("handGesturesWrite=\(onOff(allTinyGestures))")
    }
    if let master = options.master {
      try controller.setOBSBOTTinyGestureMasterSwitch(enabled: master)
      print("gestureMaster set \(onOff(master))")
    }
    if let targetSelection = options.targetSelection {
      try controller.setOBSBOTTinyGestureFeature(.targetSelection, enabled: targetSelection)
      print("gestureTargetSelection set \(onOff(targetSelection))")
    }
    if let gestureZoom = options.gestureZoom {
      try controller.setOBSBOTTinyGestureFeature(.zoom, enabled: gestureZoom)
      print("gestureZoom set \(onOff(gestureZoom))")
    }
    if let dynamicZoom = options.dynamicZoom {
      try controller.setOBSBOTTinyGestureFeature(.dynamicZoom, enabled: dynamicZoom)
      print("gestureDynamicZoom set \(onOff(dynamicZoom))")
    }
    if let dynamicZoomDirection = options.dynamicZoomDirection {
      try controller.setOBSBOTTinyGestureFeature(
        .dynamicZoomDirection,
        enabled: dynamicZoomDirection)
      print("gestureDynamicZoomDirection set \(onOff(dynamicZoomDirection))")
    }
    if let record = options.record {
      try controller.setOBSBOTTinyGestureFeature(.record, enabled: record)
      print("gestureRecord set \(onOff(record))")
    }

    if options.hasSelector6Mutations {
      var settings = try controller.readOBSBOTGestureSettings()
      if let autoFrame = options.autoFrame {
        settings.autoFrameEnabled = autoFrame
      }
      if let autoFrameMode = options.autoFrameMode {
        settings.autoFrameMode = autoFrameMode
      }
      if let selector6Zoom = options.selector6Zoom {
        settings.zoomEnabled = selector6Zoom
      }
      if let zoomRatio = options.zoomRatio {
        settings.zoomRatio = zoomRatio
      }
      try controller.setOBSBOTGestureSettings(settings)
      print("selector6 gesture settings updated")
    }

    printOBSBOTGestureStatus(controller)
  }

  func printOBSBOTGestureDryRun(_ options: CameraGestureOptions) throws {
    let commands = tinyGestureCommands(for: options)
    guard !commands.isEmpty || options.hasSelector6Mutations else {
      throw CLIError("--dry-run requires one or more camera-gesture mutation options")
    }

    print("tinyGestureDryRun=selector2-sdk-v3-gesture-parameters")
    print("tinyGestureWriteCount=\(commands.count)")
    for (index, command) in commands.enumerated() {
      print(
        "write[\(index)] name=\(command.name) selector=\(command.selector) bytes=\(hexBytes(command.packet))"
      )
    }

    if options.hasSelector6Mutations {
      print("selector6DryRun=unavailable")
      print("selector6DryRunReason=selector-6 mutation requires a live status read before write")
    }
  }

  func printOBSBOTGestureStatus(_ controller: UVCController, includeTinyReadback: Bool = true) {
    print("tinyGestureControlPath=selector2-sdk-v3-gesture-parameters")
    guard includeTinyReadback else {
      print("tinyGestureReadback=skipped-after-write")
      print("tinyGestureAIStatusReadback=skipped-after-write")
      printOBSBOTSelector6GestureStatus(controller)
      return
    }

    do {
      let state = try controller.readOBSBOTTinyGestureParameterState()
      print("tinyGestureReadback=sdk-gesture-parameters")
      print("gestureMaster=\(onOff(state.master))")
      print("gestureTargetSelection=\(onOff(state.targetSelection))")
      print("gestureZoom=\(onOff(state.zoom))")
      print("gestureDynamicZoom=\(onOff(state.dynamicZoom))")
      print("gestureDynamicZoomDirection=\(onOff(state.mirror))")
    } catch let error as UVCRequestError {
      print("tinyGestureReadback=unavailable")
      print("tinyGestureReadbackError=\(error.description)")
    } catch {
      print("tinyGestureReadback=unavailable")
      print("tinyGestureReadbackError=\(error)")
    }

    do {
      let state = try controller.readOBSBOTTinyAIStatusGestureState()
      print("tinyGestureAIStatusReadback=available")
      print("aiStatusGestureMaster=\(onOff(state.master))")
      print("aiStatusGestureTargetSelection=\(onOff(state.targetSelection))")
      print("aiStatusGestureZoom=\(onOff(state.zoom))")
      print("aiStatusGestureDynamicZoom=\(onOff(state.dynamicZoom))")
      print("aiStatusGestureDynamicZoomDirection=\(onOff(state.mirror))")
    } catch let error as UVCRequestError {
      print("tinyGestureAIStatusReadback=unavailable")
      print("tinyGestureAIStatusReadbackError=\(error.description)")
    } catch {
      print("tinyGestureAIStatusReadback=unavailable")
      print("tinyGestureAIStatusReadbackError=\(error)")
    }

    printOBSBOTSelector6GestureStatus(controller)
  }

  func printOBSBOTSelector6GestureStatus(_ controller: UVCController) {
    do {
      let settings = try controller.readOBSBOTGestureSettings()
      print("selector6GestureAutoFrame=\(onOff(settings.autoFrameEnabled))")
      print("selector6GestureAutoFrameMode=\(settings.autoFrameMode)")
      print("selector6GestureZoom=\(onOff(settings.zoomEnabled))")
      print("selector6GestureZoomRatio=\(settings.zoomRatio)")
    } catch let error as UVCRequestError {
      print("gestureSettingsError=\(error.description)")
    } catch {
      print("gestureSettingsError=\(error)")
    }
    if let aiMode = try? controller.readOBSBOTAIMode() {
      print("aiMode=\(aiMode)")
    }
  }
}

private func onOff(_ value: Bool) -> String {
  value ? "on" : "off"
}

private func tinyGestureCommands(for options: CameraGestureOptions) -> [OBSBOTTinyGestureCommand] {
  var commands: [OBSBOTTinyGestureCommand] = []
  var sequence: UInt16 = 0x0016

  func nextSequence() -> UInt16 {
    let current = sequence
    sequence = sequence == UInt16.max ? 1 : sequence + 1
    return current
  }

  if let allTinyGestures = options.allTinyGestures {
    commands.append(
      contentsOf: OBSBOTTinyGestureCommandPlan.all(
        enabled: allTinyGestures,
        nextSequence: nextSequence))
  }
  if let master = options.master {
    commands.append(
      OBSBOTTinyGestureCommandPlan.parameter(
        .master,
        enabled: master,
        sequence: nextSequence()))
  }
  if let targetSelection = options.targetSelection {
    commands.append(
      contentsOf: OBSBOTTinyGestureCommandPlan.feature(
        .targetSelection,
        enabled: targetSelection,
        nextSequence: nextSequence))
  }
  if let gestureZoom = options.gestureZoom {
    commands.append(
      contentsOf: OBSBOTTinyGestureCommandPlan.feature(
        .zoom,
        enabled: gestureZoom,
        nextSequence: nextSequence))
  }
  if let dynamicZoom = options.dynamicZoom {
    commands.append(
      contentsOf: OBSBOTTinyGestureCommandPlan.feature(
        .dynamicZoom,
        enabled: dynamicZoom,
        nextSequence: nextSequence))
  }
  if let dynamicZoomDirection = options.dynamicZoomDirection {
    commands.append(
      contentsOf: OBSBOTTinyGestureCommandPlan.feature(
        .dynamicZoomDirection,
        enabled: dynamicZoomDirection,
        nextSequence: nextSequence))
  }
  if let record = options.record {
    commands.append(
      contentsOf: OBSBOTTinyGestureCommandPlan.feature(
        .record,
        enabled: record,
        nextSequence: nextSequence))
  }
  return commands
}

private func hexBytes(_ bytes: [UInt8]) -> String {
  bytes.map(formatByte).joined(separator: " ")
}

private func formatByte(_ byte: UInt8) -> String {
  let raw = String(byte, radix: 16, uppercase: true)
  return "0x" + String(repeating: "0", count: max(0, 2 - raw.count)) + raw
}
