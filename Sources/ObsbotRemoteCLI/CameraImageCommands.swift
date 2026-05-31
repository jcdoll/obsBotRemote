import Foundation
import ObsbotRemoteCore

extension CommandLineTool {
  func runCameraImage(arguments: [String]) throws {
    let options = try CameraImageOptions.parse(arguments)
    let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

    if options.reset {
      try controller.resetCameraImageSettings()
      print("image reset to neutral")
    }

    for adjustment in OBSBOTImageAdjustment.allCases {
      guard let value = options.adjustments[adjustment] else {
        continue
      }
      let clamped = OBSBOTRemoteProtocol.clampedImageAdjustmentValue(value)
      try controller.setCameraImageAdjustment(adjustment, value: value)
      print("\(adjustment) set \(clamped)")
    }

    if let kelvin = options.whiteBalanceKelvin, options.whiteBalanceAuto != true {
      let clamped = OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)
      try controller.setCameraWhiteBalance(mode: .manual, kelvin: kelvin)
      print("whiteBalance set manual \(clamped)K")
    }

    if let whiteBalanceAuto = options.whiteBalanceAuto {
      if whiteBalanceAuto {
        try controller.setCameraWhiteBalance(mode: .auto)
        print("whiteBalance set auto")
      } else if options.whiteBalanceKelvin == nil {
        let kelvin =
          options.whiteBalanceKelvin ?? OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue
        let clamped = OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)
        try controller.setCameraWhiteBalance(mode: .manual, kelvin: kelvin)
        print("whiteBalance set manual \(clamped)K")
      }
    }

    printImageControlSupport(controller)
  }

  func printImageControlSupport(_ controller: UVCController) {
    let imageRange = OBSBOTRemoteProtocol.imageAdjustmentRange
    for adjustment in OBSBOTImageAdjustment.allCases {
      print(
        "\(adjustment)SupportedRange=(min=\(imageRange.minimum) max=\(imageRange.maximum) default=\(imageRange.defaultValue))"
      )
    }
    let wbRange = OBSBOTRemoteProtocol.whiteBalanceKelvinRange
    print("whiteBalanceDefault=auto")
    print(
      "whiteBalanceManualRange=(min=\(wbRange.minimum) max=\(wbRange.maximum) default=\(wbRange.defaultValue))"
    )
    if let readback = controller.readCameraImageControls() {
      print("imageReadback=uvc-processing-unit")
      if let brightness = readback.brightness {
        print("uvcBrightness=\(brightness)")
      }
      if let contrast = readback.contrast {
        print("uvcContrast=\(contrast)")
      }
      if let saturation = readback.saturation {
        print("uvcSaturation=\(saturation)")
      }
      if let whiteBalanceAuto = readback.whiteBalanceAuto {
        print("uvcWhiteBalanceAuto=\(whiteBalanceAuto ? "on" : "off")")
      }
      if let whiteBalanceKelvin = readback.whiteBalanceKelvin {
        print("uvcWhiteBalanceKelvin=\(whiteBalanceKelvin)")
      }
    } else {
      print("imageReadback=unsupported")
    }
  }
}
