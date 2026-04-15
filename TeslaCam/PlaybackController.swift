import Foundation
import Combine
import AVFoundation
import QuartzCore

final class MultiCamPlaybackController: ObservableObject {
  @Published var isPlaying: Bool = false

  var onTimeUpdate: ((Double) -> Void)?
  var onFinished: (() -> Void)?

  private(set) var files: [Camera: URL] = [:]
  private(set) var cameraDurations: [Camera: Double] = [:]
  private(set) var currentDuration: Double = 0
  private var currentSecondsValue: Double = 0
  private var timer: Timer?
  private var lastTickHostTime: CFTimeInterval = 0

  func currentItemTime() -> CMTime {
    CMTime(seconds: currentSecondsValue, preferredTimescale: 600)
  }

  func load(set: ClipSet, startSeconds: Double = 0) {
    load(files: set.files, cameraDurations: set.cameraDurations, duration: max(0.1, set.duration), startSeconds: startSeconds)
  }

  func loadGap(duration: Double, startSeconds: Double = 0) {
    load(files: [:], cameraDurations: [:], duration: duration, startSeconds: startSeconds)
  }

  func load(
    files: [Camera: URL],
    cameraDurations: [Camera: Double] = [:],
    duration: Double,
    startSeconds: Double = 0
  ) {
    pause()
    self.files = files
    self.cameraDurations = cameraDurations
    currentDuration = max(0.1, duration)
    currentSecondsValue = min(max(0, startSeconds), currentDuration)
    onTimeUpdate?(currentSecondsValue)
  }

  func play() {
    guard currentDuration > 0, !isPlaying else { return }
    isPlaying = true
    lastTickHostTime = CACurrentMediaTime()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      self?.advancePlayback()
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func pause() {
    timer?.invalidate()
    timer = nil
    isPlaying = false
  }

  func stop() {
    pause()
    files.removeAll()
    cameraDurations.removeAll()
    currentDuration = 0
    currentSecondsValue = 0
  }

  func seek(to seconds: Double, exact: Bool = true) {
    let _ = exact
    currentSecondsValue = min(max(0, seconds), currentDuration)
    onTimeUpdate?(currentSecondsValue)
  }

  private func advancePlayback() {
    guard isPlaying else { return }
    let now = CACurrentMediaTime()
    let delta = max(0, now - lastTickHostTime)
    lastTickHostTime = now
    currentSecondsValue = min(currentDuration, currentSecondsValue + delta)
    onTimeUpdate?(currentSecondsValue)

    if currentSecondsValue >= currentDuration {
      pause()
      onFinished?()
    }
  }
}
