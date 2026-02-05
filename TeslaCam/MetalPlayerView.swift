import SwiftUI
import MetalKit

struct MetalPlayerView: NSViewRepresentable {
  @ObservedObject var playback: MultiCamPlaybackController
  var cameraOrder: [Camera]

  func makeNSView(context: Context) -> MTKView {
    let view = MTKView()
    view.enableSetNeedsDisplay = false
    view.isPaused = false
    view.preferredFramesPerSecond = 60
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    if let renderer = MetalRenderer(mtkView: view) {
      renderer.cameraOrder = cameraOrder
      renderer.outputsProvider = { playback.outputs }
      view.delegate = renderer
      context.coordinator.renderer = renderer
    }
    return view
  }

  func updateNSView(_ nsView: MTKView, context: Context) {
    context.coordinator.renderer?.cameraOrder = cameraOrder
    context.coordinator.renderer?.outputsProvider = { playback.outputs }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator {
    var renderer: MetalRenderer?
  }
}
