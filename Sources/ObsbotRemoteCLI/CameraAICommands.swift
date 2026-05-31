import Foundation
import ObsbotRemoteCore

extension CommandLineTool {
  func runCameraAI(arguments: [String]) throws {
    let options = try CameraAIOptions.parse(arguments)
    let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
    let previous = try controller.readOBSBOTAIMode()

    guard let target = options.mode else {
      print("aiMode=\(previous)")
      return
    }

    try controller.setOBSBOTAIMode(target)
    Thread.sleep(forTimeInterval: 0.5)
    let current = try controller.readOBSBOTAIMode()
    print("aiMode \(previous) -> \(current)")
  }
}
