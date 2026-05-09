import Foundation

public struct UVCProbe: Equatable, Sendable {
    public var configurationLength: Int
    public var videoControlInterfaces: [UVCVideoControlInterface]
    public var cameraTerminals: [UVCCameraTerminal]
    public var extensionUnits: [UVCExtensionUnit]

    public init(
        configurationLength: Int,
        videoControlInterfaces: [UVCVideoControlInterface],
        cameraTerminals: [UVCCameraTerminal],
        extensionUnits: [UVCExtensionUnit] = []
    ) {
        self.configurationLength = configurationLength
        self.videoControlInterfaces = videoControlInterfaces
        self.cameraTerminals = cameraTerminals
        self.extensionUnits = extensionUnits
    }

    public var primaryCameraTerminal: UVCCameraTerminal? {
        cameraTerminals.first { terminal in
            terminal.supports(.zoomAbsolute) || terminal.supports(.panTiltAbsolute)
        } ?? cameraTerminals.first
    }
}

public struct UVCExtensionUnit: Equatable, Sendable {
    public var interfaceNumber: UInt8
    public var unitID: UInt8
    public var guid: [UInt8]
    public var numControls: UInt8
    public var sourceIDs: [UInt8]
    public var controls: [UInt8]
    public var extensionStringIndex: UInt8

    public init(
        interfaceNumber: UInt8,
        unitID: UInt8,
        guid: [UInt8],
        numControls: UInt8,
        sourceIDs: [UInt8],
        controls: [UInt8],
        extensionStringIndex: UInt8
    ) {
        self.interfaceNumber = interfaceNumber
        self.unitID = unitID
        self.guid = guid
        self.numControls = numControls
        self.sourceIDs = sourceIDs
        self.controls = controls
        self.extensionStringIndex = extensionStringIndex
    }

    public var guidString: String {
        guard guid.count == 16 else {
            return guid.map { String(format: "%02X", $0) }.joined()
        }
        let groups = [
            Array(guid[0..<4].reversed()),
            Array(guid[4..<6].reversed()),
            Array(guid[6..<8].reversed()),
            Array(guid[8..<10]),
            Array(guid[10..<16]),
        ]
        return groups
            .map { $0.map { String(format: "%02X", $0) }.joined() }
            .joined(separator: "-")
            .lowercased()
    }

    public var advertisedSelectors: [UInt8] {
        (1...max(Int(numControls), controls.count * 8))
            .compactMap { UInt8(exactly: $0) }
            .filter { supports(selector: $0) }
    }

    public func supports(selector: UInt8) -> Bool {
        guard selector > 0 else {
            return false
        }
        let bitIndex = Int(selector) - 1
        let byteIndex = bitIndex / 8
        guard byteIndex < controls.count else {
            return false
        }
        return (controls[byteIndex] & UInt8(1 << UInt8(bitIndex % 8))) != 0
    }
}

public struct UVCVideoControlInterface: Equatable, Sendable {
    public var number: UInt8
    public var alternateSetting: UInt8
    public var protocolNumber: UInt8

    public init(number: UInt8, alternateSetting: UInt8, protocolNumber: UInt8) {
        self.number = number
        self.alternateSetting = alternateSetting
        self.protocolNumber = protocolNumber
    }
}

public struct UVCCameraTerminal: Equatable, Sendable {
    public var interfaceNumber: UInt8
    public var terminalID: UInt8
    public var terminalType: UInt16
    public var controls: [UInt8]

    public init(interfaceNumber: UInt8, terminalID: UInt8, terminalType: UInt16, controls: [UInt8]) {
        self.interfaceNumber = interfaceNumber
        self.terminalID = terminalID
        self.terminalType = terminalType
        self.controls = controls
    }

    public func supports(_ control: UVCCameraTerminalControl) -> Bool {
        let bitIndex = Int(control.rawValue) - 1
        let byteIndex = bitIndex / 8
        guard byteIndex >= 0, byteIndex < controls.count else {
            return false
        }
        return (controls[byteIndex] & UInt8(1 << UInt8(bitIndex % 8))) != 0
    }
}

public enum UVCCameraTerminalControl: UInt8, Sendable {
    case zoomAbsolute = 0x0B
    case panTiltAbsolute = 0x0D

    public var displayName: String {
        switch self {
        case .zoomAbsolute:
            "zoom-abs"
        case .panTiltAbsolute:
            "pan-tilt-abs"
        }
    }
}

public enum UVCDescriptorParser {
    public static func parseConfiguration(_ data: Data) -> UVCProbe {
        var videoControlInterfaces: [UVCVideoControlInterface] = []
        var cameraTerminals: [UVCCameraTerminal] = []
        var extensionUnits: [UVCExtensionUnit] = []

        var currentInterfaceNumber: UInt8?
        var currentInterfaceClass: UInt8?
        var currentInterfaceSubClass: UInt8?

        var offset = 0
        while offset + 2 <= data.count {
            let length = Int(data[offset])
            let descriptorType = data[offset + 1]
            guard length >= 2, offset + length <= data.count else {
                break
            }

            if descriptorType == 0x04, length >= 9 {
                currentInterfaceNumber = data[offset + 2]
                let alternateSetting = data[offset + 3]
                currentInterfaceClass = data[offset + 5]
                currentInterfaceSubClass = data[offset + 6]
                let protocolNumber = data[offset + 7]
                if currentInterfaceClass == 0x0E, currentInterfaceSubClass == 0x01 {
                    videoControlInterfaces.append(
                        UVCVideoControlInterface(
                            number: data[offset + 2],
                            alternateSetting: alternateSetting,
                            protocolNumber: protocolNumber
                        )
                    )
                }
            } else if descriptorType == 0x24,
                      currentInterfaceClass == 0x0E,
                      currentInterfaceSubClass == 0x01,
                      length >= 3 {
                let descriptorSubType = data[offset + 2]
                if descriptorSubType == 0x02,
                   length >= 15,
                   let interfaceNumber = currentInterfaceNumber {
                    let terminalType = littleEndianUInt16(data, offset + 4)
                    let controlSize = Int(data[offset + 14])
                    let controlsStart = offset + 15
                    let controlsEnd = min(controlsStart + controlSize, offset + length)
                    if terminalType == 0x0201, controlsStart <= controlsEnd {
                        cameraTerminals.append(
                            UVCCameraTerminal(
                                interfaceNumber: interfaceNumber,
                                terminalID: data[offset + 3],
                                terminalType: terminalType,
                                controls: Array(data[controlsStart..<controlsEnd])
                            )
                        )
                    }
                } else if descriptorSubType == 0x06,
                          length >= 24,
                          let interfaceNumber = currentInterfaceNumber {
                    let numPins = Int(data[offset + 21])
                    let sourcesStart = offset + 22
                    let sourcesEnd = sourcesStart + numPins
                    guard sourcesEnd < offset + length else {
                        offset += length
                        continue
                    }
                    let controlSize = Int(data[sourcesEnd])
                    let controlsStart = sourcesEnd + 1
                    let controlsEnd = controlsStart + controlSize
                    guard controlsEnd <= offset + length else {
                        offset += length
                        continue
                    }

                    let extensionStringIndex = controlsEnd < offset + length
                        ? data[controlsEnd]
                        : 0
                    extensionUnits.append(
                        UVCExtensionUnit(
                            interfaceNumber: interfaceNumber,
                            unitID: data[offset + 3],
                            guid: Array(data[(offset + 4)..<(offset + 20)]),
                            numControls: data[offset + 20],
                            sourceIDs: Array(data[sourcesStart..<sourcesEnd]),
                            controls: Array(data[controlsStart..<controlsEnd]),
                            extensionStringIndex: extensionStringIndex
                        )
                    )
                }
            }

            offset += length
        }

        return UVCProbe(
            configurationLength: data.count,
            videoControlInterfaces: videoControlInterfaces,
            cameraTerminals: cameraTerminals,
            extensionUnits: extensionUnits
        )
    }
}

private func littleEndianUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}
