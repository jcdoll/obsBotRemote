import AppKit
import Foundation
import ObsbotRemoteControl
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
    private var keyEventMonitor: Any?

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

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            event.modifierFlags.contains(.command) ? event : nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runner.stop()
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
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

    private var session: RemoteControlSession?
    private var logWindow: NSWindow?
    private var logWindowDelegate: LogWindowDelegate?

    func start() {
        guard !isRunning else {
            appendSystemLog("remote control is already running")
            return
        }

        let configuration = RemoteControlSessionConfiguration(
            buttonCaptureURL: remoteButtonCaptureURL(),
            requireSeize: true
        )
        let session = RemoteControlSession(configuration: configuration) { [weak self] message in
            Task { @MainActor [weak self] in
                self?.appendControlLog(message)
            }
        }

        do {
            appendSystemLog("starting live remote control")
            try session.start()
            self.session = session
            isRunning = true
            status = "Running"
        } catch {
            status = "Start failed"
            appendSystemLog("failed to start remote control: \(error)")
        }
    }

    func stop() {
        guard let session else {
            isRunning = false
            status = "Stopped"
            return
        }

        status = "Stopping"
        appendSystemLog("stopping remote control")
        session.stop()
        self.session = nil
        isRunning = false
        status = "Stopped"
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

    private func appendSystemLog(_ message: String) {
        appendRawLog("[\(Self.timestampFormatter.string(from: Date()))] \(message)\n")
    }

    private func appendControlLog(_ message: String) {
        appendRawLog(message.hasSuffix("\n") ? message : message + "\n")
    }

    private func appendRawLog(_ text: String) {
        logText += text
        let maxCharacters = 40_000
        if logText.count > maxCharacters {
            let dropCount = logText.count - maxCharacters
            logText.removeFirst(dropCount)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func remoteButtonCaptureURL() -> URL {
        if let bundledURL = Bundle.main.url(forResource: "remote-button-capture", withExtension: "json") {
            return bundledURL
        }
        return defaultRemoteButtonCaptureURL
    }
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
