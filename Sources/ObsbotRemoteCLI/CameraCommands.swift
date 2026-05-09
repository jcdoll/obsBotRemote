import Foundation
import ObsbotRemoteCore

extension CommandLineTool {
    func runCameraProbe(arguments: [String]) throws {
        let options = try CameraOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        let probe = try controller.probe()

        print("camera \(formatHex(UInt32(options.vendorID))):\(formatHex(UInt32(options.productID)))")
        print("configurationDescriptorLength=\(probe.configurationLength)")
        if probe.videoControlInterfaces.isEmpty {
            print("videoControlInterfaces=none")
        } else {
            for interface in probe.videoControlInterfaces {
                print(
                    "videoControlInterface number=\(interface.number) alternate=\(interface.alternateSetting) protocol=\(interface.protocolNumber)"
                )
            }
        }

        if probe.cameraTerminals.isEmpty {
            print("cameraTerminals=none")
        } else {
            for terminal in probe.cameraTerminals {
                let controls = [
                    UVCCameraTerminalControl.zoomAbsolute,
                    UVCCameraTerminalControl.panTiltAbsolute,
                ].filter { terminal.supports($0) }
                    .map(\.displayName)
                    .joined(separator: ", ")
                print(
                    "cameraTerminal id=\(terminal.terminalID) interface=\(terminal.interfaceNumber) type=\(formatHex(UInt32(terminal.terminalType))) controls=\(controls.isEmpty ? "none" : controls)"
                )
            }
        }

        if probe.extensionUnits.isEmpty {
            print("extensionUnits=none")
        } else {
            for unit in probe.extensionUnits {
                let selectors = unit.advertisedSelectors.map(String.init).joined(separator: ",")
                print(
                    "extensionUnit id=\(unit.unitID) interface=\(unit.interfaceNumber) guid=\(unit.guidString) controls=\(unit.numControls) selectors=\(selectors.isEmpty ? "none" : selectors)"
                )
            }
        }

        if let zoom = try? controller.readZoom() {
            print("zoomCurrent=\(zoom)")
        }
        if let panTilt = try? controller.readPanTilt() {
            print("panTiltCurrent pan=\(panTilt.pan) tilt=\(panTilt.tilt)")
        }
    }

    func runCameraZoom(arguments: [String]) throws {
        let options = try CameraZoomOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

        if let delta = options.delta {
            let current = try controller.readZoom()
            let next = max(0, current + delta)
            try controller.setZoom(next)
            print("zoom \(current) -> \(next)")
            return
        }

        if let value = options.value {
            try controller.setZoom(value)
            print("zoom set \(value)")
            return
        }

        let current = try controller.readZoom()
        print("zoomCurrent=\(current)")
    }

    func runCameraPanTilt(arguments: [String]) throws {
        let options = try CameraPanTiltOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        guard let pan = options.pan, let tilt = options.tilt else {
            throw CLIError("camera-pan-tilt requires --pan and --tilt")
        }
        try controller.setPanTilt(pan: pan, tilt: tilt)
        print("panTilt set pan=\(pan) tilt=\(tilt)")
    }

    func runCameraPower(arguments: [String]) throws {
        let options = try CameraPowerOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

        switch options.action {
        case .status:
            let status = try controller.readOBSBOTRunStatus()
            print("powerStatus=\(status)")
        case .toggle:
            let result = try controller.toggleOBSBOTRunStatus()
            print("power \(result.previous) -> \(result.next)")
        case .wake:
            let previous = try controller.readOBSBOTRunStatus()
            try controller.setOBSBOTRunStatus(.run)
            print("power \(previous) -> run")
        case .sleep:
            let previous = try controller.readOBSBOTRunStatus()
            try controller.setOBSBOTRunStatus(.sleep)
            print("power \(previous) -> sleep")
        }
    }

    func runCameraXUGet(arguments: [String]) throws {
        let options = try CameraXUGetOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        guard let unitID = options.unitID else {
            throw CLIError("camera-xu-get requires --unit")
        }
        guard let selector = options.selector else {
            throw CLIError("camera-xu-get requires --selector")
        }

        if let info = try? controller.readExtensionUnitInfo(unitID: unitID, selector: selector) {
            print("info=\(formatByte(info)) \(extensionInfoDescription(info))")
        }
        if options.length == nil, let length = try? controller.readExtensionUnitLength(unitID: unitID, selector: selector) {
            print("length=\(length)")
        }

        let bytes = try controller.readExtensionUnitCurrent(
            unitID: unitID,
            selector: selector,
            length: options.length
        )
        print("value=\(hexBytes(bytes))")
    }

    func runCameraXUDump(arguments: [String]) throws {
        let options = try CameraXUDumpOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        let probe = try controller.probe()

        for unit in probe.extensionUnits {
            print(
                "extensionUnit id=\(unit.unitID) interface=\(unit.interfaceNumber) guid=\(unit.guidString)"
            )
            for selector in unit.advertisedSelectors {
                let infoText: String
                if let info = try? controller.readExtensionUnitInfo(unitID: unit.unitID, selector: selector) {
                    infoText = "\(formatByte(info)) \(extensionInfoDescription(info))"
                } else {
                    infoText = "unreadable"
                }

                let length = try? controller.readExtensionUnitLength(unitID: unit.unitID, selector: selector)
                let lengthText = length.map(String.init) ?? "unknown"
                let valueText: String
                if let length, length <= options.maxLength,
                   let value = try? controller.readExtensionUnitCurrent(
                    unitID: unit.unitID,
                    selector: selector,
                    length: length
                   ) {
                    valueText = hexBytes(value)
                } else {
                    valueText = "not-read"
                }
                print("  selector=\(selector) info=\(infoText) length=\(lengthText) value=\(valueText)")
            }
        }
    }

    func printUVCControlsStatus() {
        print(
            """
            native UVC control transfer support is implemented directly through IOUSBLib.

            lab commands:
              - camera-probe
              - camera-zoom [--value <raw>|--delta <raw>]
              - camera-pan-tilt --pan <raw> --tilt <raw>
              - camera-power [status|on|off]
            """
        )
    }
}

private func hexBytes(_ bytes: [UInt8]) -> String {
    bytes.map(formatByte).joined(separator: " ")
}

private func formatByte(_ byte: UInt8) -> String {
    let raw = String(byte, radix: 16, uppercase: true)
    return "0x" + String(repeating: "0", count: max(0, 2 - raw.count)) + raw
}

private func extensionInfoDescription(_ info: UInt8) -> String {
    var flags: [String] = []
    if (info & 0x01) != 0 {
        flags.append("GET")
    }
    if (info & 0x02) != 0 {
        flags.append("SET")
    }
    if (info & 0x04) != 0 {
        flags.append("disabled")
    }
    if (info & 0x08) != 0 {
        flags.append("autoupdate")
    }
    return flags.isEmpty ? "(no flags)" : "(\(flags.joined(separator: ",")))"
}
