import Darwin
import Foundation
import ObsbotRemoteCore

private func runMain() -> Int32 {
  ignoreRemoteTerminationSignals()
  do {
    try CommandLineTool(arguments: Array(CommandLine.arguments.dropFirst())).run()
    return 0
  } catch let error as CLIError {
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    return 2
  } catch let error as UVCRequestError {
    FileHandle.standardError.write(Data(("error: \(error.description)\n").utf8))
    return 1
  } catch {
    FileHandle.standardError.write(Data(("error: \(error)\n").utf8))
    return 1
  }
}

exit(runMain())
