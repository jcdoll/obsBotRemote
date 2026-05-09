import Darwin
import Foundation

final class CLIError: Error {
    let message: String

    init(_ message: String) {
        self.message = "error: \(message)"
    }
}

func swiftVersionHint() -> String {
    #if swift(>=6.0)
        "6.x"
    #else
        "5.x"
    #endif
}

func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func ignoreRemoteTerminationSignals() {
    signal(SIGTERM, SIG_IGN)
    signal(SIGQUIT, SIG_IGN)
    signal(SIGINFO, SIG_IGN)
}
