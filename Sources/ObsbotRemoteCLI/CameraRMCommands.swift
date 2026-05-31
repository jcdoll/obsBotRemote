import Foundation
import ObsbotRemoteCore

extension CommandLineTool {
  func runCameraRMSend(arguments: [String]) throws {
    let options = try CameraRMOptions.parse(arguments)
    guard let commandSet = options.commandSet else {
      throw CLIError("camera-rm-send requires --command-set")
    }
    guard let commandID = options.commandID else {
      throw CLIError("camera-rm-send requires --command-id")
    }

    let packet = OBSBOTRemoteProtocol.makeRMCommandPacket(
      v3CommandSet: commandSet,
      v3CommandID: commandID,
      payload: options.payload,
      sequence: options.sequence
    )
    print("requestCommandSet=\(formatHex(UInt32(commandSet), width: 2))")
    print("requestCommandID=\(formatHex(UInt32(commandID), width: 4))")
    print("requestPayload=\(rmHexBytes(options.payload))")
    print("requestPacket=\(rmHexBytes(packet))")

    let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
    try controller.setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
    print("write=ok")

    guard options.readLength > 0 else {
      return
    }
    if options.readDelay > 0 {
      Thread.sleep(forTimeInterval: options.readDelay)
    }
    let response = try controller.readExtensionUnitCurrentAllowingShortRead(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      length: options.readLength
    )
    print("responseBytesRead=\(response.count)")
    print("response=\(rmHexBytes(response))")
  }
}

private func rmHexBytes(_ bytes: [UInt8]) -> String {
  bytes.map(rmFormatByte).joined(separator: " ")
}

private func rmFormatByte(_ byte: UInt8) -> String {
  let raw = String(byte, radix: 16, uppercase: true)
  return "0x" + String(repeating: "0", count: max(0, 2 - raw.count)) + raw
}
