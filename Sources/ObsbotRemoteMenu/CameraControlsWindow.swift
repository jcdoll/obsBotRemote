import SwiftUI

struct CameraControlsWindowView: View {
  @StateObject private var viewModel: CameraControlsViewModel

  init(runner: RemoteControlRunner, coordinator: CameraControlCoordinator) {
    _viewModel = StateObject(
      wrappedValue: CameraControlsViewModel(coordinator: coordinator) { [weak runner] message in
        runner?.appendCameraControlLog(message)
      }
    )
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
    }
    .padding(18)
    .frame(minWidth: 420, idealWidth: 440, minHeight: 430)
    .onAppear {
      viewModel.loadInitialState()
    }
  }

  private var header: some View {
    HStack(alignment: .top) {
      Text("Camera Controls")
        .font(.headline)
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(viewModel.panText)
        Text(viewModel.tiltText)
        Text(viewModel.zoomText)
      }
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(.secondary)
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
    }
    .buttonStyle(.bordered)
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
  }

  private var dPad: some View {
    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
      GridRow {
        Spacer()
          .frame(width: 42, height: 32)
        iconButton("arrow.up", help: "Move up") {
          viewModel.move(.up)
        } repeatAction: {
          viewModel.move(.up)
        }
        Spacer()
          .frame(width: 42, height: 32)
      }
      GridRow {
        iconButton("arrow.left", help: "Move left") {
          viewModel.move(.left)
        } repeatAction: {
          viewModel.move(.left)
        }
        iconButton("scope", help: "Center") {
          viewModel.center()
        }
        iconButton("arrow.right", help: "Move right") {
          viewModel.move(.right)
        } repeatAction: {
          viewModel.move(.right)
        }
      }
      GridRow {
        Spacer()
          .frame(width: 42, height: 32)
        iconButton("arrow.down", help: "Move down") {
          viewModel.move(.down)
        } repeatAction: {
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
        } repeatAction: {
          viewModel.zoomOut()
        }
        Slider(
          value: Binding(
            get: { viewModel.zoomValue },
            set: { viewModel.setDisplayedZoom($0) }
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
        } repeatAction: {
          viewModel.zoomIn()
        }
      }
    }
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
  }

  private func iconButton(
    _ symbol: String,
    help: String,
    action: @escaping @MainActor @Sendable () -> Void,
    repeatAction: (@MainActor @Sendable () -> Void)? = nil
  ) -> some View {
    RepeatButton(action: action, repeatAction: repeatAction) {
      Image(systemName: symbol)
        .frame(width: 28, height: 18)
    }
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
