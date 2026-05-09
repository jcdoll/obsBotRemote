import AppKit
import Darwin
import Foundation
import SwiftUI

@main
enum ObsbotRemoteMenuApp {
    @MainActor private static var appDelegate: MenuAppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MenuAppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
private final class MenuAppDelegate: NSObject, NSApplicationDelegate {
    private let runner = RemoteControlRunner()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "OBSBOT Remote")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(rootView: RemotePopoverView(runner: runner))
    }

    func applicationWillTerminate(_ notification: Notification) {
        runner.stop()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@MainActor
private final class RemoteControlRunner: ObservableObject {
    @Published private(set) var status = "Stopped"
    @Published private(set) var isRunning = false
    @Published private(set) var logText = ""

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var standardInput: FileHandle?
    private var logWindow: NSWindow?
    private var logWindowDelegate: LogWindowDelegate?
    private var forceStopWorkItem: DispatchWorkItem?

    func start() {
        guard !isRunning else {
            appendSystemLog("remote control is already running")
            return
        }
        guard let launch = resolveControlLaunch() else {
            status = "Cannot find obsbot-remote"
            appendSystemLog("could not find obsbot-remote; run swift build or install the CLI on PATH")
            return
        }

        let process = Process()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardInput = standardInput

        attach(pipe: stdoutPipe)
        attach(pipe: stderrPipe)

        process.terminationHandler = { [weak self] finishedProcess in
            Task { @MainActor in
                self?.processDidExit(finishedProcess)
            }
        }

        do {
            appendSystemLog("starting \(launch.description)")
            try process.run()
            self.process = process
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            self.standardInput = standardInput
            isRunning = true
            status = "Running"
        } catch {
            detachPipes()
            status = "Failed to start"
            appendSystemLog("failed to start remote control: \(error)")
        }
    }

    func stop() {
        forceStopWorkItem?.cancel()
        forceStopWorkItem = nil

        guard let process, process.isRunning else {
            processDidExit(process)
            return
        }

        status = "Stopping"
        appendSystemLog("stopping remote control")
        kill(process.processIdentifier, SIGINT)

        let workItem = DispatchWorkItem { [weak self, weak process] in
            guard let process, process.isRunning else {
                return
            }
            Task { @MainActor in
                self?.appendSystemLog("forcing remote control to stop")
            }
            kill(process.processIdentifier, SIGKILL)
        }
        forceStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func showLogWindow() {
        if let logWindow {
            logWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: LogWindowView(runner: self))
        let window = NSWindow(contentViewController: controller)
        window.title = "OBSBOT Remote Log"
        window.setContentSize(NSSize(width: 760, height: 460))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        let delegate = LogWindowDelegate { [weak self] in
            self?.logWindow = nil
            self?.logWindowDelegate = nil
        }
        logWindowDelegate = delegate
        window.delegate = delegate
        logWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func quit() {
        stop()
        NSApp.terminate(nil)
    }

    private func processDidExit(_ finishedProcess: Process?) {
        forceStopWorkItem?.cancel()
        forceStopWorkItem = nil
        detachPipes()

        if let finishedProcess {
            appendSystemLog("remote control exited with status \(finishedProcess.terminationStatus)")
        }

        if finishedProcess == nil || finishedProcess === process {
            process = nil
            stdoutPipe = nil
            stderrPipe = nil
            standardInput = nil
            isRunning = false
            status = "Stopped"
        }
    }

    private func attach(pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendRawLog(text)
            }
        }
    }

    private func detachPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func appendSystemLog(_ message: String) {
        appendRawLog("[\(Self.timestampFormatter.string(from: Date()))] \(message)\n")
    }

    private func appendRawLog(_ text: String) {
        logText += text
        let maxCharacters = 40_000
        if logText.count > maxCharacters {
            let dropCount = logText.count - maxCharacters
            logText.removeFirst(dropCount)
        }
    }

    private func resolveControlLaunch() -> ControlLaunch? {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let executableDirectory = executableURL.deletingLastPathComponent()
        let sibling = executableDirectory.appendingPathComponent("obsbot-remote")

        if isExecutableFile(sibling.path) {
            return ControlLaunch(
                executableURL: sibling,
                arguments: ["control"],
                currentDirectoryURL: nil,
                description: "\(sibling.path) control"
            )
        }

        if let pathExecutable = findExecutableOnPath(named: "obsbot-remote") {
            return ControlLaunch(
                executableURL: pathExecutable,
                arguments: ["control"],
                currentDirectoryURL: nil,
                description: "\(pathExecutable.path) control"
            )
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let packageManifest = currentDirectory.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageManifest.path) {
            return ControlLaunch(
                executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                arguments: ["run", "obsbot-remote", "control"],
                currentDirectoryURL: currentDirectory,
                description: "swift run obsbot-remote control"
            )
        }

        return nil
    }

    private func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private func findExecutableOnPath(named name: String) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if isExecutableFile(candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct ControlLaunch {
    var executableURL: URL
    var arguments: [String]
    var currentDirectoryURL: URL?
    var description: String
}

private struct RemotePopoverView: View {
    @ObservedObject var runner: RemoteControlRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: runner.isRunning ? "dot.radiowaves.left.and.right" : "video")
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OBSBOT Remote")
                        .font(.headline)
                    Text(runner.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(runner.isRunning ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 9, height: 9)
            }

            HStack(spacing: 8) {
                Button {
                    runner.isRunning ? runner.stop() : runner.start()
                } label: {
                    Label(runner.isRunning ? "Stop" : "Start", systemImage: runner.isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    runner.showLogWindow()
                } label: {
                    Label("Log", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()

            ScrollView {
                Text(runner.logText.isEmpty ? "No log yet." : runner.logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 250)

            Divider()

            HStack {
                Spacer()
                Button("Quit") {
                    runner.quit()
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 360, height: 420)
    }
}

private struct LogWindowView: View {
    @ObservedObject var runner: RemoteControlRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OBSBOT Remote Log")
                    .font(.headline)
                Spacer()
                Text(runner.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(runner.logText.isEmpty ? "No log yet." : runner.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .border(Color.secondary.opacity(0.25))
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 360)
    }
}

private final class LogWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
