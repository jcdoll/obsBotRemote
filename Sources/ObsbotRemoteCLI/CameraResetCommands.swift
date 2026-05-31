import ObsbotRemoteCore

extension CommandLineTool {
  func runCameraReset(arguments: [String]) throws {
    let options = try CameraResetOptions.parse(arguments)
    let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
    let result = try controller.resetOBSBOTCameraToFactoryDefaults(reboot: options.reboot)

    print("cameraReset=factoryRestore")
    print("gimbalStop=\(result.gimbalStopSent ? "sent" : "skipped")")
    print("gimbalReset=\(result.gimbalResetSent ? "sent" : "skipped")")
    print("factoryRestore=\(result.factoryRestoreSent ? "sent" : "skipped")")
    print("reboot=\(result.rebootRequested ? "sent" : "skipped")")
  }
}
