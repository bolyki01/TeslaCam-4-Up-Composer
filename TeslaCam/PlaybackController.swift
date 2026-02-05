import Foundation
import Combine
import AVFoundation

final class MultiCamPlaybackController: ObservableObject {
  @Published var isPlaying: Bool = false

  var onTimeUpdate: ((Double) -> Void)?
  var onFinished: (() -> Void)?

  private(set) var outputs: [Camera: AVPlayerItemVideoOutput] = [:]
  private var players: [Camera: AVPlayer] = [:]
  private var masterPlayer: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?

  private let outputAttributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferMetalCompatibilityKey as String: true
  ]

  func output(for camera: Camera) -> AVPlayerItemVideoOutput? {
    return outputs[camera]
  }

  func load(set: ClipSet, startSeconds: Double = 0) {
    cleanup()

    var newOutputs: [Camera: AVPlayerItemVideoOutput] = [:]
    var newPlayers: [Camera: AVPlayer] = [:]

    for camera in Camera.allCases {
      guard let url = set.file(for: camera) else { continue }
      let asset = AVURLAsset(url: url)
      let item = AVPlayerItem(asset: asset)
      let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputAttributes)
      item.add(output)
      item.preferredForwardBufferDuration = 0
      let player = AVPlayer(playerItem: item)
      player.actionAtItemEnd = .pause
      player.automaticallyWaitsToMinimizeStalling = false
      newOutputs[camera] = output
      newPlayers[camera] = player
    }

    outputs = newOutputs
    players = newPlayers
    masterPlayer = newPlayers[.front] ?? newPlayers[.back] ?? newPlayers.values.first

    seekAll(to: CMTime(seconds: max(0, startSeconds), preferredTimescale: 600), tolerance: .zero)

    if let masterItem = masterPlayer?.currentItem {
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: masterItem,
        queue: .main
      ) { [weak self] _ in
        self?.isPlaying = false
        self?.onFinished?()
      }
    }

    if let master = masterPlayer {
      let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
      timeObserver = master.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
        self?.onTimeUpdate?(max(0, time.seconds))
      }
    }
  }

  func play() {
    guard masterPlayer != nil else { return }
    isPlaying = true
    for player in players.values { player.play() }
  }

  func pause() {
    isPlaying = false
    for player in players.values { player.pause() }
  }

  func seek(to seconds: Double, exact: Bool = true) {
    let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.12, preferredTimescale: 600)
    seekAll(to: time, tolerance: tolerance)
  }

  private func seekAll(to time: CMTime, tolerance: CMTime) {
    for player in players.values {
      player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }
  }

  private func cleanup() {
    if let master = masterPlayer, let observer = timeObserver {
      master.removeTimeObserver(observer)
    }
    timeObserver = nil
    if let endObserver = endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = nil
    outputs.removeAll()
    players.removeAll()
    masterPlayer = nil
  }
}
