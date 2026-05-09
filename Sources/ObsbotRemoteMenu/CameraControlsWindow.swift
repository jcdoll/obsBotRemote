import ObsbotRemoteCore
import SwiftUI

@MainActor
final class CameraControlsViewModel: ObservableObject {
  @Published var isBusy = false
  @Published var actionText = "Ready."
  @Published var runStatusText = "Unknown"
  @Published var panTiltText = "Pan 0, tilt 0"
  @Published var zoomText = "Zoom 0"
  @Published var aiModeText = "Unknown"
  @Published var zoomValue = 0.0
  @Published var zoomRange = 0.0...100.0
  @Published var aiModeChoice = CameraAIModeChoice.off
  @Published var panTiltStep: Int {
    didSet {
      coordinator.updatePanTiltStep(Int32(panTiltStep))
    }
  }
  @Published var zoomStep: Int {
    didSet {
      coordinator.updateZoomStep(zoomStep)
    }
  }

  private let coordinator: CameraControlCoordinator
  private var pendingOperationCount = 0

  init(coordinator: CameraControlCoordinator) {
    self.coordinator = coordinator
    let settings = coordinator.currentSettings()
    panTiltStep = Int(settings.panTiltStep)
    zoomStep = settings.zoomStep
  }

  func refresh(showBusy: Bool = true, completion: (@MainActor () -> Void)? = nil) {
    if showBusy {
      beginBusy()
    }

    coordinator.refresh { [weak self] result in
      guard let self else {
        return
      }

      switch result {
      case .success(let snapshot):
        self.apply(snapshot)
        if self.actionText == "Ready." {
          self.actionText = "Camera ready."
        }
      case .failure(let message):
        self.actionText = "Camera error: \(message)"
      }

      if showBusy {
        self.finishBusy()
      }
      completion?()
    }
  }

  func wake() {
    runCommand(coordinator.wake)
  }

  func sleep() {
    runCommand(coordinator.sleep)
  }

  func center() {
    runCommand(coordinator.center)
  }

  func move(_ direction: CameraControlDirection) {
    runCommand { completion in
      coordinator.move(direction, completion: completion)
    }
  }

  func zoomIn() {
    runCommand(coordinator.zoomIn)
  }

  func zoomOut() {
    runCommand(coordinator.zoomOut)
  }

  func setZoomFromSlider() {
    let target = Int(zoomValue.rounded())
    runCommand { completion in
      coordinator.setZoom(target, completion: completion)
    }
  }

  func setAIMode(_ choice: CameraAIModeChoice) {
    runCommand { completion in
      coordinator.setAIMode(choice.mode, completion: completion)
    }
  }

  private func runCommand(
    _ command: (
      @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
    ) -> Void
  ) {
    beginBusy()
    command { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let message):
        self.actionText = message
        self.refresh(showBusy: false) {
          self.finishBusy()
        }
      case .failure(let message):
        self.actionText = "Camera error: \(message)"
        self.refresh(showBusy: false) {
          self.finishBusy()
        }
      }
    }
  }

  private func apply(_ snapshot: CameraControlSnapshot) {
    runStatusText = snapshot.runStatus.userFacingName
    panTiltText = "Pan \(snapshot.panTilt.pan), tilt \(snapshot.panTilt.tilt)"
    zoomText = "Zoom \(snapshot.zoom)"
    zoomValue = Double(snapshot.zoom)
    zoomRange = Double(snapshot.zoomRange.minimum)...Double(snapshot.zoomRange.maximum)
    aiModeText = snapshot.aiMode.userFacingName
    if let choice = CameraAIModeChoice(mode: snapshot.aiMode) {
      aiModeChoice = choice
    }
  }

  private func beginBusy() {
    pendingOperationCount += 1
    isBusy = true
  }

  private func finishBusy() {
    pendingOperationCount = max(0, pendingOperationCount - 1)
    isBusy = pendingOperationCount > 0
  }
}

struct CameraControlsWindowView: View {
  @ObservedObject var runner: RemoteControlRunner
  @StateObject private var viewModel: CameraControlsViewModel

  init(runner: RemoteControlRunner, coordinator: CameraControlCoordinator) {
    self.runner = runner
    _viewModel = StateObject(wrappedValue: CameraControlsViewModel(coordinator: coordinator))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      Divider()
      powerControls
      Divider()
      gimbalAndSteps
      Divider()
      zoomControls
      Divider()
      aiModeControls
      Divider()
      footer
    }
    .padding(18)
    .frame(minWidth: 420, idealWidth: 440, minHeight: 500)
    .onAppear {
      viewModel.refresh()
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Camera Controls")
          .font(.headline)
        Text("Remote \(runner.status.lowercased())")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 3) {
        HStack(spacing: 6) {
          if viewModel.isBusy {
            ProgressView()
              .scaleEffect(0.55)
          }
          Text(viewModel.runStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(viewModel.panTiltText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var powerControls: some View {
    HStack(spacing: 10) {
      Button {
        viewModel.wake()
      } label: {
        Label("Wake", systemImage: "power")
      }
      Button {
        viewModel.sleep()
      } label: {
        Label("Sleep", systemImage: "moon")
      }
      Spacer()
      Button {
        viewModel.refresh()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
    }
    .buttonStyle(.bordered)
    .disabled(viewModel.isBusy)
  }

  private var gimbalAndSteps: some View {
    HStack(alignment: .top, spacing: 24) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Gimbal")
          .font(.subheadline)
          .fontWeight(.semibold)
        dPad
      }
      VStack(alignment: .leading, spacing: 12) {
        Text("Step Size")
          .font(.subheadline)
          .fontWeight(.semibold)
        Stepper(value: $viewModel.panTiltStep, in: 3_600...72_000, step: 3_600) {
          stepLabel(title: "Pan / tilt", value: "\(viewModel.panTiltStep)")
        }
        Stepper(value: $viewModel.zoomStep, in: 1...25, step: 1) {
          stepLabel(title: "Zoom", value: "\(viewModel.zoomStep)")
        }
      }
      Spacer(minLength: 0)
    }
    .disabled(viewModel.isBusy)
  }

  private var dPad: some View {
    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
      GridRow {
        Spacer()
          .frame(width: 42, height: 32)
        iconButton("arrow.up", help: "Move up") {
          viewModel.move(.up)
        }
        Spacer()
          .frame(width: 42, height: 32)
      }
      GridRow {
        iconButton("arrow.left", help: "Move left") {
          viewModel.move(.left)
        }
        iconButton("scope", help: "Center") {
          viewModel.center()
        }
        iconButton("arrow.right", help: "Move right") {
          viewModel.move(.right)
        }
      }
      GridRow {
        Spacer()
          .frame(width: 42, height: 32)
        iconButton("arrow.down", help: "Move down") {
          viewModel.move(.down)
        }
        Spacer()
          .frame(width: 42, height: 32)
      }
    }
  }

  private var zoomControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Zoom")
          .font(.subheadline)
          .fontWeight(.semibold)
        Spacer()
        Text(viewModel.zoomText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 10) {
        iconButton("minus", help: "Zoom out") {
          viewModel.zoomOut()
        }
        Slider(
          value: Binding(
            get: { viewModel.zoomValue },
            set: { viewModel.zoomValue = $0 }
          ),
          in: viewModel.zoomRange,
          step: 1,
          onEditingChanged: { editing in
            if !editing {
              viewModel.setZoomFromSlider()
            }
          }
        )
        iconButton("plus", help: "Zoom in") {
          viewModel.zoomIn()
        }
      }
    }
    .disabled(viewModel.isBusy)
  }

  private var aiModeControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("AI Mode")
          .font(.subheadline)
          .fontWeight(.semibold)
        Spacer()
        Text(viewModel.aiModeText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Picker(
        "AI Mode",
        selection: Binding(
          get: { viewModel.aiModeChoice },
          set: { viewModel.setAIMode($0) }
        )
      ) {
        ForEach(CameraAIModeChoice.allCases) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .disabled(viewModel.isBusy)
  }

  private var footer: some View {
    HStack {
      Text(viewModel.actionText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer()
    }
    .frame(minHeight: 32, alignment: .topLeading)
  }

  private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 28, height: 18)
    }
    .buttonStyle(.bordered)
    .help(help)
  }

  private func stepLabel(title: String, value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .frame(width: 170)
  }
}

enum CameraAIModeChoice: String, CaseIterable, Identifiable {
  case off
  case track
  case closeUp
  case hand
  case desk

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off:
      "Off"
    case .track:
      "Track"
    case .closeUp:
      "Close-up"
    case .hand:
      "Hand"
    case .desk:
      "Desk"
    }
  }

  var mode: OBSBOTAIMode {
    switch self {
    case .off:
      .off
    case .track:
      .humanNormal
    case .closeUp:
      .humanCloseUp
    case .hand:
      .hand
    case .desk:
      .desk
    }
  }

  init?(mode: OBSBOTAIMode) {
    switch mode {
    case .off:
      self = .off
    case .humanNormal:
      self = .track
    case .humanCloseUp:
      self = .closeUp
    case .hand:
      self = .hand
    case .desk:
      self = .desk
    case .unknown:
      return nil
    }
  }
}

extension OBSBOTRunStatus {
  fileprivate var userFacingName: String {
    switch self {
    case .run:
      "Awake"
    case .sleep:
      "Asleep"
    case .privacy:
      "Privacy"
    case .unknown:
      description
    }
  }
}
