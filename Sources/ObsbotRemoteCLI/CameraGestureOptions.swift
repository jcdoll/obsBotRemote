import Foundation
import ObsbotRemoteCore

struct CameraGestureOptions {
  var vendorID: UInt16 = 0x3564
  var productID: UInt16 = 0xFF02
  var allTinyGestures: Bool?
  var master: Bool?
  var targetSelection: Bool?
  var gestureZoom: Bool?
  var dynamicZoom: Bool?
  var dynamicZoomDirection: Bool?
  var record: Bool?
  var autoFrame: Bool?
  var autoFrameMode: OBSBOTGestureAutoFrameMode?
  var selector6Zoom: Bool?
  var zoomRatio: Int?
  var dryRun = false

  static func parse(_ arguments: [String]) throws -> CameraGestureOptions {
    var options = CameraGestureOptions()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--vendor-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--vendor-id requires a value")
        }
        options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
      case "--product-id":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--product-id requires a value")
        }
        options.productID = try parseUInt16(arguments[index], option: "--product-id")
      case "--gesture-auto-frame", "--auto-frame":
        options.autoFrame = try parseBooleanArgument(arguments, &index, option: arguments[index])
      case "--gesture-all", "--all":
        options.allTinyGestures = try parseBooleanArgument(
          arguments, &index, option: arguments[index])
      case "--gesture-master", "--hand-gestures":
        options.master = try parseBooleanArgument(arguments, &index, option: arguments[index])
      case "--gesture-target", "--gesture-target-selection":
        options.targetSelection = try parseBooleanArgument(
          arguments, &index, option: arguments[index])
      case "--gesture-dynamic-zoom":
        options.dynamicZoom = try parseBooleanArgument(arguments, &index, option: arguments[index])
      case "--gesture-dynamic-zoom-direction":
        options.dynamicZoomDirection = try parseBooleanArgument(
          arguments, &index, option: arguments[index])
      case "--gesture-record":
        options.record = try parseBooleanArgument(arguments, &index, option: "--gesture-record")
      case "--gesture-mode", "--auto-frame-mode":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--gesture-mode requires auto-frame, close-up, half-body, or full-body")
        }
        options.autoFrameMode = try parseGestureAutoFrameMode(arguments[index])
      case "--gesture-zoom":
        options.gestureZoom = try parseBooleanArgument(arguments, &index, option: "--gesture-zoom")
      case "--selector6-gesture-zoom":
        options.selector6Zoom = try parseBooleanArgument(
          arguments, &index, option: "--selector6-gesture-zoom")
      case "--gesture-zoom-ratio":
        index += 1
        guard index < arguments.count else {
          throw CLIError("--gesture-zoom-ratio requires a value")
        }
        let range = OBSBOTRemoteProtocol.gestureZoomRatioRange
        options.zoomRatio = try parseBoundedInteger(
          arguments[index],
          option: "--gesture-zoom-ratio",
          minimum: range.minimum,
          maximum: range.maximum)
      case "--dry-run", "--print-packets":
        options.dryRun = true
      default:
        throw CLIError("unknown camera-gesture option: \(arguments[index])")
      }
      index += 1
    }
    return options
  }

  var hasMutations: Bool {
    allTinyGestures != nil || master != nil || targetSelection != nil || gestureZoom != nil
      || dynamicZoom != nil || dynamicZoomDirection != nil || record != nil || autoFrame != nil
      || autoFrameMode != nil || selector6Zoom != nil || zoomRatio != nil
  }

  var hasSelector6Mutations: Bool {
    autoFrame != nil || autoFrameMode != nil || selector6Zoom != nil || zoomRatio != nil
  }
}

private func parseBooleanArgument(
  _ arguments: [String],
  _ index: inout Int,
  option: String
) throws -> Bool {
  index += 1
  guard index < arguments.count else {
    throw CLIError("\(option) requires on or off")
  }
  return try parseOnOff(arguments[index], option: option) == 1
}

private func parseGestureAutoFrameMode(_ text: String) throws -> OBSBOTGestureAutoFrameMode {
  switch text.lowercased() {
  case "auto-frame", "autoframe", "auto", "frame":
    return .autoFrame
  case "close-up", "closeup", "close":
    return .closeUp
  case "half-body", "halfbody", "half":
    return .halfBody
  case "full-body", "fullbody", "full":
    return .fullBody
  default:
    throw CLIError("--gesture-mode requires auto-frame, close-up, half-body, or full-body")
  }
}
