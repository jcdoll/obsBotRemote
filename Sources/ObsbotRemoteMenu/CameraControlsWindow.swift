import SwiftUI

struct CameraControlsWindowView: View {
  @StateObject private var viewModel: CameraControlsViewModel
  @State private var showingResetConfirmation = false

  private enum Layout {
    static let windowWidth: CGFloat = 480
    static let contentPadding: CGFloat = 14
    static let contentWidth: CGFloat = windowWidth - (contentPadding * 2)
    static let sectionSpacing: CGFloat = 10
    static let controlSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 10
    static let iconButtonWidth: CGFloat = 42
    static let iconButtonHeight: CGFloat = 32
    static let topPowerWidth: CGFloat = 80
    static let topStatusWidth: CGFloat = 228
    static let topResetWidth: CGFloat = 128
    static let panStatusWidth: CGFloat = 72
    static let tiltStatusWidth: CGFloat = 72
    static let zoomStatusWidth: CGFloat = 68
    static let dPadWidth: CGFloat = 142
    static let stepColumnWidth: CGFloat = 292
    static let stepLabelWidth: CGFloat = 224
    static let aiModeWidth: CGFloat = contentWidth
    static let fieldOfViewWidth: CGFloat = contentWidth
    static let imageLabelWidth: CGFloat = 98
    static let imageValueWidth: CGFloat = 44
  }

  init(runner: RemoteControlRunner, coordinator: CameraControlCoordinator) {
    _viewModel = StateObject(
      wrappedValue: CameraControlsViewModel(coordinator: coordinator) { [weak runner] message in
        runner?.appendCameraControlLog(message)
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
      controlSection { topControls }
      Divider()
      controlSection { gimbalAndSteps }
      Divider()
      controlSection { zoomControls }
      Divider()
      controlSection { aiModeControls }
      Divider()
      controlSection { advancedSettingsControls }
      Divider()
      controlSection { imageControls }
    }
    .padding(Layout.contentPadding)
    .frame(width: Layout.windowWidth, alignment: .topLeading)
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
    HStack(alignment: .center, spacing: Layout.controlSpacing) {
      Button {
        viewModel.togglePower()
      } label: {
        Label(viewModel.powerButtonTitle, systemImage: viewModel.powerButtonSystemImage)
      }
      .buttonStyle(.bordered)
      .frame(width: Layout.topPowerWidth)

      HStack(spacing: Layout.controlSpacing) {
        statusText(viewModel.panText, width: Layout.panStatusWidth)
        statusText(viewModel.tiltText, width: Layout.tiltStatusWidth)
        statusText(viewModel.zoomText, width: Layout.zoomStatusWidth)
      }
      .frame(width: Layout.topStatusWidth, alignment: .leading)

      Button(role: .destructive) {
        showingResetConfirmation = true
      } label: {
        Label("Reset Camera", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.bordered)
      .frame(width: Layout.topResetWidth)
      .help("Factory reset and reboot camera")
    }
  }

  private var gimbalAndSteps: some View {
    HStack(alignment: .top, spacing: 18) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Gimbal")
          .font(.subheadline)
          .fontWeight(.semibold)
        dPad
      }
      .frame(width: Layout.dPadWidth, alignment: .leading)
      VStack(alignment: .leading, spacing: 12) {
        Text("Step Size")
          .font(.subheadline)
          .fontWeight(.semibold)
        Stepper(value: $viewModel.panTiltStep, in: 3_600...72_000, step: 3_600) {
          stepLabel(title: "Pan / tilt", value: "\(viewModel.panTiltStep)")
        }
        .frame(width: Layout.stepColumnWidth, alignment: .leading)
        Stepper(value: $viewModel.zoomStep, in: 1...25, step: 1) {
          stepLabel(title: "Zoom", value: "\(viewModel.zoomStep)")
        }
        .frame(width: Layout.stepColumnWidth, alignment: .leading)
      }
      .frame(width: Layout.stepColumnWidth, alignment: .leading)
    }
  }

  private var dPad: some View {
    Grid(horizontalSpacing: Layout.controlSpacing, verticalSpacing: Layout.controlSpacing) {
      GridRow {
        Spacer()
          .frame(width: Layout.iconButtonWidth, height: Layout.iconButtonHeight)
        iconButton("arrow.up", help: "Move up") {
          viewModel.move(.up)
        } repeatAction: {
          viewModel.move(.up)
        }
        Spacer()
          .frame(width: Layout.iconButtonWidth, height: Layout.iconButtonHeight)
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
          .frame(width: Layout.iconButtonWidth, height: Layout.iconButtonHeight)
        iconButton("arrow.down", help: "Move down") {
          viewModel.move(.down)
        } repeatAction: {
          viewModel.move(.down)
        }
        Spacer()
          .frame(width: Layout.iconButtonWidth, height: Layout.iconButtonHeight)
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
        statusText(viewModel.zoomText, width: Layout.zoomStatusWidth, alignment: .trailing)
      }
      HStack(spacing: Layout.rowSpacing) {
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
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("AI Mode")
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(viewModel.aiModeText)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
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
      .frame(width: Layout.aiModeWidth, alignment: .leading)
    }
  }

  private var advancedSettingsControls: some View {
    VStack(alignment: .leading, spacing: 6) {
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
      .disabled(viewModel.handGestureControlsApplying)
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
      .frame(width: Layout.fieldOfViewWidth, alignment: .leading)
    }
  }

  private var imageControls: some View {
    VStack(alignment: .leading, spacing: 6) {
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
      imageSlider(
        title: "White Balance",
        value: Binding(
          get: { viewModel.whiteBalanceValue },
          set: { viewModel.setDisplayedWhiteBalance($0) }),
        range: viewModel.whiteBalanceRange,
        available: viewModel.whiteBalanceAvailable && !viewModel.whiteBalanceAuto,
        commit: viewModel.setWhiteBalanceFromSlider
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
    .frame(width: Layout.iconButtonWidth, height: Layout.iconButtonHeight)
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
    .frame(width: Layout.stepLabelWidth)
  }

  private func imageSlider(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    available: Bool,
    commit: @escaping () -> Void
  ) -> some View {
    HStack(spacing: Layout.rowSpacing) {
      Text(title)
        .frame(width: Layout.imageLabelWidth, alignment: .leading)
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
        .frame(width: Layout.imageValueWidth, alignment: .trailing)
    }
  }

  private func controlSection<Content: View>(
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    content()
      .frame(width: Layout.contentWidth, alignment: .leading)
  }

  private func statusText(
    _ text: String,
    width: CGFloat,
    alignment: Alignment = .leading
  ) -> some View {
    Text(text)
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.85)
      .frame(width: width, alignment: alignment)
  }

}
