import Foundation
import ObsbotRemoteUSBBridge

public struct UVCProbe: Equatable, Sendable {
    public var configurationLength: Int
    public var videoControlInterfaces: [UVCVideoControlInterface]
    public var cameraTerminals: [UVCCameraTerminal]

    public init(
        configurationLength: Int,
        videoControlInterfaces: [UVCVideoControlInterface],
        cameraTerminals: [UVCCameraTerminal]
    ) {
        self.configurationLength = configurationLength
        self.videoControlInterfaces = videoControlInterfaces
        self.cameraTerminals = cameraTerminals
    }

    public var primaryCameraTerminal: UVCCameraTerminal? {
        cameraTerminals.first { terminal in
            terminal.supports(.zoomAbsolute) || terminal.supports(.panTiltAbsolute)
        } ?? cameraTerminals.first
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

public enum UVCRequestError: Error, CustomStringConvertible, Equatable, Sendable {
    case deviceRequestFailed(operation: String, code: Int32, transferred: UInt32)
    case descriptorReadFailed(code: Int32)
    case descriptorTooLarge(required: Int)
    case missingCameraTerminal
    case unsupportedControl(String)
    case shortRead(operation: String, expected: Int, actual: UInt32)

    public var description: String {
        switch self {
        case let .deviceRequestFailed(operation, code, transferred):
            "\(operation) failed: \(formatIOReturn(code)) transferred=\(transferred)"
        case let .descriptorReadFailed(code):
            "failed to read USB configuration descriptor: \(formatIOReturn(code))"
        case let .descriptorTooLarge(required):
            "USB configuration descriptor is too large for the probe buffer: \(required) byte(s)"
        case .missingCameraTerminal:
            "no UVC camera terminal was found in the camera configuration descriptor"
        case let .unsupportedControl(control):
            "camera terminal does not advertise \(control)"
        case let .shortRead(operation, expected, actual):
            "\(operation) returned \(actual) byte(s), expected \(expected)"
        }
    }
}

public final class UVCController {
    public var vendorID: UInt16
    public var productID: UInt16

    public init(vendorID: UInt16 = 0x3564, productID: UInt16 = 0xFF02) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public func probe() throws -> UVCProbe {
        try UVCDescriptorParser.parseConfiguration(readConfigurationDescriptor())
    }

    public func readZoom() throws -> Int {
        let terminal = try cameraTerminal(requiring: .zoomAbsolute)
        var payload = [UInt8](repeating: 0, count: 2)
        try deviceRequest(
            operation: "GET_CUR zoom-abs",
            requestType: 0xA1,
            request: 0x81,
            value: UInt16(UVCCameraTerminalControl.zoomAbsolute.rawValue) << 8,
            index: controlIndex(for: terminal),
            payload: &payload,
            expectedLength: payload.count
        )
        return Int(UInt16(payload[0]) | (UInt16(payload[1]) << 8))
    }

    public func setZoom(_ value: Int) throws {
        let terminal = try cameraTerminal(requiring: .zoomAbsolute)
        let clamped = max(0, min(value, Int(UInt16.max)))
        var payload = [
            UInt8(clamped & 0xFF),
            UInt8((clamped >> 8) & 0xFF),
        ]
        try deviceRequest(
            operation: "SET_CUR zoom-abs",
            requestType: 0x21,
            request: 0x01,
            value: UInt16(UVCCameraTerminalControl.zoomAbsolute.rawValue) << 8,
            index: controlIndex(for: terminal),
            payload: &payload,
            expectedLength: payload.count
        )
    }

    public func readPanTilt() throws -> (pan: Int32, tilt: Int32) {
        let terminal = try cameraTerminal(requiring: .panTiltAbsolute)
        var payload = [UInt8](repeating: 0, count: 8)
        try deviceRequest(
            operation: "GET_CUR pan-tilt-abs",
            requestType: 0xA1,
            request: 0x81,
            value: UInt16(UVCCameraTerminalControl.panTiltAbsolute.rawValue) << 8,
            index: controlIndex(for: terminal),
            payload: &payload,
            expectedLength: payload.count
        )
        return (
            pan: Int32(littleEndianBytes: payload[0..<4]),
            tilt: Int32(littleEndianBytes: payload[4..<8])
        )
    }

    public func setPanTilt(pan: Int32, tilt: Int32) throws {
        let terminal = try cameraTerminal(requiring: .panTiltAbsolute)
        var payload: [UInt8] = []
        payload.appendLittleEndian(pan)
        payload.appendLittleEndian(tilt)
        try deviceRequest(
            operation: "SET_CUR pan-tilt-abs",
            requestType: 0x21,
            request: 0x01,
            value: UInt16(UVCCameraTerminalControl.panTiltAbsolute.rawValue) << 8,
            index: controlIndex(for: terminal),
            payload: &payload,
            expectedLength: payload.count
        )
    }

    private func cameraTerminal(requiring control: UVCCameraTerminalControl) throws -> UVCCameraTerminal {
        guard let terminal = try probe().primaryCameraTerminal else {
            throw UVCRequestError.missingCameraTerminal
        }
        guard terminal.supports(control) else {
            throw UVCRequestError.unsupportedControl(control.displayName)
        }
        return terminal
    }

    private func controlIndex(for terminal: UVCCameraTerminal) -> UInt16 {
        (UInt16(terminal.terminalID) << 8) | UInt16(terminal.interfaceNumber)
    }

    private func readConfigurationDescriptor() throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 65_535)
        let capacity = buffer.count
        var length = 0
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            ORUSBGetConfigurationDescriptor(
                vendorID,
                productID,
                0,
                pointer.baseAddress,
                capacity,
                &length
            )
        }
        guard result == 0 else {
            if result == -536_870_194 {
                throw UVCRequestError.descriptorTooLarge(required: length)
            }
            throw UVCRequestError.descriptorReadFailed(code: result)
        }
        return Data(buffer.prefix(length))
    }

    private func deviceRequest(
        operation: String,
        requestType: UInt8,
        request: UInt8,
        value: UInt16,
        index: UInt16,
        payload: inout [UInt8],
        expectedLength: Int
    ) throws {
        var transferred: UInt32 = 0
        let payloadLength = UInt16(payload.count)
        let result = payload.withUnsafeMutableBufferPointer { pointer in
            ORUSBDeviceRequest(
                vendorID,
                productID,
                requestType,
                request,
                value,
                index,
                pointer.baseAddress,
                payloadLength,
                &transferred
            )
        }
        guard result == 0 else {
            throw UVCRequestError.deviceRequestFailed(
                operation: operation,
                code: result,
                transferred: transferred
            )
        }
        guard transferred == UInt32(expectedLength) else {
            throw UVCRequestError.shortRead(
                operation: operation,
                expected: expectedLength,
                actual: transferred
            )
        }
    }
}

public enum UVCDescriptorParser {
    public static func parseConfiguration(_ data: Data) -> UVCProbe {
        var videoControlInterfaces: [UVCVideoControlInterface] = []
        var cameraTerminals: [UVCCameraTerminal] = []

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
                }
            }

            offset += length
        }

        return UVCProbe(
            configurationLength: data.count,
            videoControlInterfaces: videoControlInterfaces,
            cameraTerminals: cameraTerminals
        )
    }
}

private func littleEndianUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private extension Array where Element == UInt8 {
    mutating func appendLittleEndian(_ value: Int32) {
        let raw = UInt32(bitPattern: value)
        append(UInt8(raw & 0xFF))
        append(UInt8((raw >> 8) & 0xFF))
        append(UInt8((raw >> 16) & 0xFF))
        append(UInt8((raw >> 24) & 0xFF))
    }
}

private extension Int32 {
    init(littleEndianBytes bytes: ArraySlice<UInt8>) {
        let raw = bytes.enumerated().reduce(UInt32(0)) { partial, element in
            partial | (UInt32(element.element) << UInt32(element.offset * 8))
        }
        self = Int32(bitPattern: raw)
    }
}

private func formatIOReturn(_ code: Int32) -> String {
    let unsigned = UInt32(bitPattern: code)
    return "0x" + String(unsigned, radix: 16, uppercase: true)
}
