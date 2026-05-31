import SwiftUI

struct CameraControlsWindowView: View {
  @StateObject private var viewModel: CameraControlsViewModel
  @State private var showingResetConfirmation = false

  init(runner: RemoteControlRunner, coordinator: CameraControlCoordinator) {
    _viewModel = StateObject(
      wrappedValue: CameraControlsViewModel(coordinator: coordinator) { [weak runner] message in
        runner?.appendCameraControlLog(message)
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      topControls
      Divider()
      gimbalAndSteps
      Divider()
      zoomControls
      Divider()
      aiModeControls
      Divider()
      advancedSettingsControls
      Divider()
      imageControls
    }
    .padding(18)
    .frame(minWidth: 560, idealWidth: 620, minHeight: 800, idealHeight: 900)
    .onAppear {
      viewModel.loadInitialState()
    }
    .alert("Reset camera?", isPresented: $showingResetConfirmation) {
      Button("Reset Camera", role: .destructive) {
        viewModel.resetCameraToFactoryDefaults()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This restores factory settings, recenters the gimbal, and reboots the camera.")
    }
  }

  private var topControls: some View {
    HStack(alignment: .center, spacing: 14) {
      Button {
        viewModel.togglePower()
      } label: {
        Label(viewModel.powerButtonTitle, systemImage: viewModel.powerButtonSystemImage)
      }
      .buttonStyle(.bordered)

      Spacer()

      HStack(spacing: 12) {
        Text(viewModel.panText)
        Text(viewModel.tiltText)
        Text(viewModel.zoomText)
      }
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(.secondary)

      Button(role: .destructive) {
        showingResetConfirmation = true
      } label: {
        Label("Reset Camera", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)
      .help("Factory reset and reboot camera")
    }
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

  private var advancedSettingsControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Advanced")
        .font(.subheadline)
        .fontWeight(.semibold)
      Toggle(
        "HDR",
        isOn: Binding(get: { viewModel.hdrEnabled }, set: { viewModel.setHDR($0) })
      )
      Toggle(
        "Face-based Auto Exposure",
        isOn: Binding(
          get: { viewModel.faceAutoExposureEnabled },
          set: { viewModel.setFaceAutoExposure($0) })
      )
      Toggle(
        "Face-based Auto Focus",
        isOn: Binding(
          get: { viewModel.faceAutoFocusEnabled },
          set: { viewModel.setFaceAutoFocus($0) })
      )
      Toggle(
        "Hand Gestures",
        isOn: Binding(
          get: { viewModel.handGesturesEnabled },
          set: { viewModel.setHandGestureControls($0) })
      )
      Picker(
        "Field of View",
        selection: Binding(
          get: { viewModel.fieldOfViewChoice },
          set: { viewModel.setFieldOfView($0) })
      ) {
        ForEach(CameraFieldOfViewChoice.allCases) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  private var imageControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Image")
        .font(.subheadline)
        .fontWeight(.semibold)
      imageSlider(
        title: "Brightness",
        value: Binding(
          get: { viewModel.brightnessValue },
          set: { viewModel.setDisplayedBrightness($0) }),
        range: viewModel.brightnessRange,
        available: viewModel.brightnessAvailable,
        commit: viewModel.setBrightnessFromSlider
      )
      imageSlider(
        title: "Contrast",
        value: Binding(
          get: { viewModel.contrastValue },
          set: { viewModel.setDisplayedContrast($0) }),
        range: viewModel.contrastRange,
        available: viewModel.contrastAvailable,
        commit: viewModel.setContrastFromSlider
      )
      imageSlider(
        title: "Saturation",
        value: Binding(
          get: { viewModel.saturationValue },
          set: { viewModel.setDisplayedSaturation($0) }),
        range: viewModel.saturationRange,
        available: viewModel.saturationAvailable,
        commit: viewModel.setSaturationFromSlider
      )
      HStack {
        Toggle(
          "Auto White Balance",
          isOn: Binding(
            get: { viewModel.whiteBalanceAuto },
            set: { viewModel.setWhiteBalanceAuto($0) })
        )
        .disabled(!viewModel.whiteBalanceAutoAvailable)
        Spacer()
        Button {
          viewModel.resetImageControls()
        } label: {
          Label("Reset Image", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
      }
      imageSlider(
        title: "White Balance",
        value: Binding(
          get: { viewModel.whiteBalanceValue },
          set: { viewModel.setDisplayedWhiteBalance($0) }),
        range: viewModel.whiteBalanceRange,
        available: viewModel.whiteBalanceAvailable && !viewModel.whiteBalanceAuto,
        commit: viewModel.setWhiteBalanceFromSlider
      )
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

  private func imageSlider(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    available: Bool,
    commit: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 10) {
      Text(title)
        .frame(width: 105, alignment: .leading)
      Slider(
        value: value,
        in: range,
        onEditingChanged: { editing in
          if !editing {
            commit()
          }
        }
      )
      .disabled(!available)
      Text("\(Int(value.wrappedValue.rounded()))")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 48, alignment: .trailing)
    }
  }

}
