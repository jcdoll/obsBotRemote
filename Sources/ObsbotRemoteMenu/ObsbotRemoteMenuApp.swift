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
private final class MenuAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let runner = RemoteControlRunner()
  private var statusItem: NSStatusItem?
  private var titleMenuItem: NSMenuItem?
  private var statusMenuItem: NSMenuItem?
  private var startStopMenuItem: NSMenuItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.statusItem = statusItem

    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "video.fill", accessibilityDescription: "OBSBOT Remote")
    }

    statusItem.menu = makeStatusMenu()

    runner.start()
    updateMenuItems()
  }

  func applicationWillTerminate(_ notification: Notification) {
    runner.stop()
  }

  func menuWillOpen(_ menu: NSMenu) {
    updateMenuItems()
  }

  private func makeStatusMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self

    let titleItem = NSMenuItem(title: "OBSBOT Remote", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    titleMenuItem = titleItem
    menu.addItem(titleItem)

    let statusItem = NSMenuItem(title: runner.status, action: nil, keyEquivalent: "")
    statusItem.isEnabled = false
    statusMenuItem = statusItem
    menu.addItem(statusItem)

    menu.addItem(.separator())

    let startStopItem = NSMenuItem(
      title: "Start", action: #selector(toggleRemoteControl(_:)), keyEquivalent: "")
    startStopItem.target = self
    startStopMenuItem = startStopItem
    menu.addItem(startStopItem)

    let controlsItem = NSMenuItem(
      title: "Camera Controls...", action: #selector(showCameraControls(_:)), keyEquivalent: "")
    controlsItem.target = self
    menu.addItem(controlsItem)

    let logItem = NSMenuItem(title: "Log...", action: #selector(showLog(_:)), keyEquivalent: "")
    logItem.target = self
    menu.addItem(logItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit OBSBOT Remote", action: #selector(quit(_:)), keyEquivalent: "")
    quitItem.target = self
    menu.addItem(quitItem)

    return menu
  }

  private func updateMenuItems() {
    titleMenuItem?.title = "OBSBOT Remote"
    statusMenuItem?.title = runner.status
    startStopMenuItem?.title = runner.isRunning ? "Stop" : "Start"
  }

  @objc private func toggleRemoteControl(_ sender: NSMenuItem) {
    runner.isRunning ? runner.stop() : runner.start()
    updateMenuItems()
  }

  @objc private func showLog(_ sender: NSMenuItem) {
    runner.showLogWindow()
  }

  @objc private func showCameraControls(_ sender: NSMenuItem) {
    runner.showCameraControlsWindow()
  }

  @objc private func quit(_ sender: NSMenuItem) {
    runner.quit()
  }
}

@MainActor
final class RemoteControlRunner: ObservableObject {
  @Published private(set) var status = "Stopped"
  @Published private(set) var isRunning = false
  @Published private(set) var logText = ""

  private let coordinator = CameraControlCoordinator()
  private var session: RemoteHotKeyControlSession?
  private var logWindow: NSWindow?
  private var logWindowDelegate: WindowCloseDelegate?
  private var controlsWindow: NSWindow?
  private var controlsWindowDelegate: WindowCloseDelegate?

  func start() {
    guard !isRunning else {
      appendSystemLog("remote control is already running")
      return
    }

    let session = RemoteHotKeyControlSession(
      buttonCaptureURL: remoteButtonCaptureURL(),
      coordinator: coordinator
    ) { [weak self] message in
      Task { @MainActor [weak self] in
        self?.appendControlLog(message)
      }
    }

    do {
      appendSystemLog("Starting remote control.")
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
    appendSystemLog("Stopping remote control.")
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
    let delegate = WindowCloseDelegate { [weak self] in
      self?.logWindow = nil
      self?.logWindowDelegate = nil
    }
    logWindowDelegate = delegate
    window.delegate = delegate
    logWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func showCameraControlsWindow() {
    if let controlsWindow {
      controlsWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let controller = NSHostingController(
      rootView: CameraControlsWindowView(runner: self, coordinator: coordinator)
    )
    let window = NSWindow(contentViewController: controller)
    window.title = "OBSBOT Remote Camera Controls"
    window.setContentSize(NSSize(width: 440, height: 440))
    window.minSize = NSSize(width: 420, height: 420)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.isReleasedWhenClosed = false
    let delegate = WindowCloseDelegate { [weak self] in
      self?.controlsWindow = nil
      self?.controlsWindowDelegate = nil
    }
    controlsWindowDelegate = delegate
    window.delegate = delegate
    controlsWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func quit() {
    stop()
    NSApp.terminate(nil)
  }

  func appendCameraControlLog(_ message: String) {
    appendControlLog("Camera Controls: \(message)")
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
    if let bundledURL = Bundle.main.url(forResource: "remote-button-capture", withExtension: "json")
    {
      return bundledURL
    }
    return defaultRemoteButtonCaptureURL
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

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }
}
