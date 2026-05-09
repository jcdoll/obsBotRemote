import Darwin
import Foundation

func readPromptAnswer() -> String {
    if isatty(STDIN_FILENO) != 1 {
        return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    _ = readAvailableTerminalBytes()
    var answer = ""

    while true {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, true)
        for byte in readAvailableTerminalBytes() {
            switch byte {
            case 0x03, 0x04:
                print("^C")
                return "q"
            case 0x0A, 0x0D:
                print("")
                return answer.trimmingCharacters(in: .whitespacesAndNewlines)
            case 0x20...0x7E:
                let scalar = UnicodeScalar(byte)
                let character = Character(scalar)
                answer.append(character)
                print(String(character), terminator: "")
                fflush(stdout)
            default:
                continue
            }
        }
    }
}

struct TerminalRawMode {
    private let fd = STDIN_FILENO
    private var originalTermios = termios()
    private var originalFlags: Int32 = -1
    private var enabled = false

    mutating func enable() {
        guard isatty(fd) == 1 else {
            return
        }
        guard tcgetattr(fd, &originalTermios) == 0 else {
            return
        }
        originalFlags = fcntl(fd, F_GETFL, 0)

        var raw = originalTermios
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        tcsetattr(fd, TCSANOW, &raw)
        if originalFlags >= 0 {
            _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)
        }
        enabled = true
    }

    mutating func restore() {
        guard enabled else {
            return
        }
        _ = readAvailableTerminalBytes()
        tcsetattr(fd, TCSANOW, &originalTermios)
        if originalFlags >= 0 {
            _ = fcntl(fd, F_SETFL, originalFlags)
        }
        enabled = false
    }
}

func readAvailableTerminalBytes() -> [UInt8] {
    var out: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 128)
    let bufferCount = buffer.count
    while true {
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.read(STDIN_FILENO, rawBuffer.baseAddress, bufferCount)
        }
        if count > 0 {
            out.append(contentsOf: buffer.prefix(count))
        } else {
            return out
        }
    }
}

func escapedTerminalBytes(_ bytes: [UInt8]) -> String {
    bytes.map { byte in
        switch byte {
        case 0x1B:
            "\\e"
        case 0x0A:
            "\\n"
        case 0x0D:
            "\\r"
        case 0x09:
            "\\t"
        case 0x20...0x7E:
            String(UnicodeScalar(byte))
        default:
            "\\x" + String(byte, radix: 16, uppercase: true)
        }
    }.joined()
}
