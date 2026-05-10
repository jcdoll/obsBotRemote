import SwiftUI

struct RepeatButton<Label: View>: View {
  var action: @MainActor @Sendable () -> Void
  var repeatAction: (@MainActor @Sendable () -> Void)?
  @ViewBuilder var label: () -> Label

  @State private var timer: Timer?
  @State private var isPressed = false

  var body: some View {
    Button(action: {}) {
      label()
    }
    .buttonStyle(.bordered)
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          startRepeatingIfNeeded()
        }
        .onEnded { _ in
          stopRepeating()
        }
    )
    .onDisappear {
      stopRepeating()
    }
  }

  private func startRepeatingIfNeeded() {
    guard !isPressed else {
      return
    }
    isPressed = true
    action()

    guard timer == nil, let repeatAction else {
      return
    }
    timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
      Task { @MainActor in
        repeatAction()
      }
    }
    timer?.fireDate = Date().addingTimeInterval(0.25)
  }

  private func stopRepeating() {
    isPressed = false
    timer?.invalidate()
    timer = nil
  }
}
