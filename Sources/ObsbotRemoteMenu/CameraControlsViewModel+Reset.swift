import Foundation

extension CameraControlsViewModel {
  func resetCameraToFactoryDefaults() {
    invalidateReadback()
    runStatus = nil
    aiModeText = "Unknown"

    runCommand(
      onSuccess: { [weak self] in
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 8_000_000_000)
          self?.loadInitialState()
        }
      },
      { completion in
        coordinator.resetCameraToFactoryDefaults(completion: completion)
      }
    )
  }
}
