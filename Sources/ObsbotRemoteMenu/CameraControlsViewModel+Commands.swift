import OSLog

extension CameraControlsViewModel {
  func runCommand(
    refreshAfterSuccess: Bool = false,
    onSuccess: (@MainActor () -> Void)? = nil,
    onFailure: (@MainActor () -> Void)? = nil,
    onComplete: (@MainActor () -> Void)? = nil,
    _ command: (
      @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
    ) -> Void
  ) {
    command { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let message):
        cameraControlsLogger.notice("\(message, privacy: .public)")
        self.log(message)
        onSuccess?()
        if refreshAfterSuccess {
          self.loadInitialState()
        }
        onComplete?()
      case .failure(let message):
        cameraControlsLogger.error("Camera error: \(message, privacy: .public)")
        self.log("Camera error: \(message)")
        onFailure?()
        self.loadInitialState()
        onComplete?()
      }
    }
  }

  func invalidateReadback() {
    readbackGeneration += 1
  }
}
