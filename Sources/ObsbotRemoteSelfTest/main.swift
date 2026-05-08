import ObsbotRemoteCore
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data(("self-test failed: \(message)\n").utf8))
        exit(1)
    }
}

func expectNoThrow<T>(_ message: String, _ operation: () throws -> T) -> T {
    do {
        return try operation()
    } catch {
        FileHandle.standardError.write(Data(("self-test failed: \(message): \(error)\n").utf8))
        exit(1)
    }
}

let reducer = CameraActionReducer()
let moved = reducer.applying(.move(panDelta: 3600, tiltDelta: -1800), to: CameraState())
expect(moved == CameraState(pan: 3600, tilt: -1800, zoom: 100), "move action")

let zoomed = reducer.applying(.zoom(delta: -200), to: CameraState(zoom: 100))
expect(zoomed.zoom == 0, "zoom floor")

let presetReducer = CameraActionReducer(
    presets: ["1": CameraPreset(pan: 10, tilt: 20, zoom: 30)]
)
let recalled = presetReducer.applying(.recallPreset("1"), to: CameraState())
expect(recalled == CameraState(pan: 10, tilt: 20, zoom: 30), "preset recall")

expect(expectNoThrow("parse decimal") { try parseInteger("1234") } == 1234, "parse decimal")
expect(expectNoThrow("parse hex") { try parseInteger("0x1A2B") } == 0x1A2B, "parse hex")
expect(formatHex(0x2A) == "0x002A", "hex formatting")

print("self-test passed")
