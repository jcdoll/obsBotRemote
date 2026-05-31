import ObsbotRemoteCore

extension CameraControlCoordinator {
  func resetCameraToFactoryDefaults(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      _ = try coordinator.controller.resetOBSBOTCameraToFactoryDefaults()
      return "Factory reset sent; camera is rebooting."
    }
  }
}
