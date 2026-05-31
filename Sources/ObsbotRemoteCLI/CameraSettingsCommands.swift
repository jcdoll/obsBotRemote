import Foundation
import ObsbotRemoteCore

extension CommandLineTool {
  func runCameraSettings(arguments: [String]) throws {
    let options = try CameraSettingsOptions.parse(arguments)
    let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

    if let hdr = options.hdr {
      try controller.setOBSBOTHDR(enabled: hdr)
      print("hdr set \(onOff(hdr))")
    }
    if let faceAE = options.faceAutoExposure {
      try controller.setOBSBOTFaceAutoExposure(enabled: faceAE)
      print("faceAE set \(onOff(faceAE))")
    }
    if let faceAF = options.faceAutoFocus {
      try controller.setOBSBOTFaceAutoFocus(enabled: faceAF)
      print("faceAutoFocus set \(onOff(faceAF))")
    }
    if let fieldOfView = options.fieldOfView {
      try controller.setOBSBOTFieldOfView(fieldOfView)
      print("fov set \(fieldOfView)")
    }

    printOBSBOTSettingsStatus(controller)
  }

  func printOBSBOTSettingsStatus(_ controller: UVCController) {
    do {
      let settings = try controller.readOBSBOTCameraSettings()
      print("hdr=\(onOff(settings.hdrEnabled))")
      print("faceAE=\(onOff(settings.faceAutoExposureEnabled))")
      print("faceAutoFocus=\(onOff(settings.faceAutoFocusEnabled))")
      print("autoFocus=\(onOff(settings.autoFocusEnabled))")
      print("fov=\(settings.fieldOfView)")
    } catch let error as UVCRequestError {
      print("settingsError=\(error.description)")
    } catch {
      print("settingsError=\(error)")
    }
  }
}

private func onOff(_ value: Bool) -> String {
  value ? "on" : "off"
}
