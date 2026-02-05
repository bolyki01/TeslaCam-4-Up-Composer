import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

final class AppState: ObservableObject {
  @Published var rootURL: URL?
  @Published var clipSets: [ClipSet] = []
  @Published var isIndexing: Bool = false
  @Published var indexStatus: String = ""
  @Published var minDate: Date?
  @Published var maxDate: Date?
  @Published var selectedStart: Date = Date()
  @Published var selectedEnd: Date = Date()
  @Published var currentIndex: Int = 0
  @Published var currentSeconds: Double = 0
  @Published var totalDuration: Double = 0
  @Published var overlayText: String = ""
  @Published var telemetryText: String = ""
  @Published var errorMessage: String = ""
  @Published var showError: Bool = false
  @Published var camerasDetected: [Camera] = []

  let playback = MultiCamPlaybackController()
  let exporter = ExportController()

  private var startOffsets: [Double] = []
  private var isUserSeeking = false
  private var wasPlayingBeforeSeek = false
  private var seekWorkItem: DispatchWorkItem?
  private var telemetryTimeline: TelemetryTimeline?
  private var telemetryURL: URL?

  private let overlayFormatter: DateFormatter = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone.current
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  func onAppear() {
    chooseFolder()
  }

  func chooseFolder() {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = "Select TeslaCam Folder"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"

    if panel.runModal() == .OK, let url = panel.url {
      indexFolder(url)
    }
  }

  func indexFolder(_ url: URL) {
    isIndexing = true
    indexStatus = "Scanning..."
    clipSets = []
    camerasDetected = []

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let index = try ClipIndexer.index(rootURL: url) { scanned in
          DispatchQueue.main.async {
            self.indexStatus = "Indexed \(scanned) clips..."
          }
        }
        DispatchQueue.main.async {
          self.rootURL = url
          self.clipSets = index.sets
          self.minDate = index.minDate
          self.maxDate = index.maxDate
          self.selectedStart = index.minDate
          self.selectedEnd = index.maxDate
          self.currentIndex = 0
          self.camerasDetected = self.orderCameras(Array(index.camerasFound))
          self.rebuildTimeline()
          if let first = index.sets.first {
            self.playback.load(set: first)
            self.currentSeconds = 0
            self.loadTelemetry(for: first)
          }
          self.isIndexing = false
          self.indexStatus = "Indexed \(index.sets.count) minutes"

          self.playback.onTimeUpdate = { [weak self] seconds in
            self?.updateCurrentSeconds(localSeconds: seconds)
          }
        }
      } catch {
        DispatchQueue.main.async {
          self.isIndexing = false
          self.errorMessage = "No clips found in this folder."
          self.showError = true
        }
      }
    }
  }

  func togglePlay() {
    if playback.isPlaying {
      playback.pause()
    } else {
      playback.play()
    }
  }

  func restart() {
    guard !clipSets.isEmpty else { return }
    currentIndex = 0
    playback.load(set: clipSets[0])
    currentSeconds = 0
    loadTelemetry(for: clipSets[0])
  }

  func normalizeRange() {
    if selectedEnd < selectedStart {
      selectedEnd = selectedStart
    }
  }

  func exportRange() {
    guard !clipSets.isEmpty else { return }
    normalizeRange()
    let start = floorToMinute(selectedStart)
    let end = floorToMinute(selectedEnd)

    let sets = clipSets.filter { $0.date >= start && $0.date <= end }
    if sets.isEmpty {
      errorMessage = "No clips found in the selected range."
      showError = true
      return
    }

    let panel = NSSavePanel()
    panel.title = "Save Export"
    panel.allowedContentTypes = [.mpeg4Movie]
    panel.nameFieldStringValue = "teslacam_export_hevc_max.mp4"
    panel.canCreateDirectories = true

    if panel.runModal() == .OK, let url = panel.url {
      var outputURL = url
      if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        outputURL = url.appendingPathComponent("teslacam_export_hevc_max.mp4")
      }
      let useSix = camerasDetected.count >= 6
      exporter.export(sets: sets, outputURL: outputURL, useSixCam: useSix)
    }
  }

  func beginSeek() {
    guard !isUserSeeking else { return }
    wasPlayingBeforeSeek = playback.isPlaying
    playback.pause()
    seekWorkItem?.cancel()
    isUserSeeking = true
  }

  func endSeek() {
    guard isUserSeeking else { return }
    isUserSeeking = false
    seekToGlobalTime(currentSeconds, exact: true)
    if wasPlayingBeforeSeek { playback.play() }
  }

  func liveSeek(to seconds: Double) {
    guard isUserSeeking else { return }
    seekWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.seekToGlobalTime(seconds, exact: false)
    }
    seekWorkItem = item
    DispatchQueue.main.async(execute: item)
  }

  private func updateCurrentSeconds(localSeconds: Double) {
    guard !isUserSeeking else { return }
    let start = startOffsets[safe: currentIndex] ?? 0
    currentSeconds = start + max(0, localSeconds)
    let base = clipSets[safe: currentIndex]?.date ?? Date()
    let time = base.addingTimeInterval(max(0, localSeconds))
    overlayText = overlayFormatter.string(from: time)
    if let timeline = telemetryTimeline {
      let frame = timeline.closest(to: localSeconds * 1000.0)
      telemetryText = formatTelemetry(frame?.sei)
    } else {
      telemetryText = ""
    }
  }

  private func rebuildTimeline() {
    startOffsets = []
    var sum: Double = 0
    for set in clipSets {
      startOffsets.append(sum)
      sum += max(1, set.duration)
    }
    totalDuration = max(1, sum)
  }

  private func seekToGlobalTime(_ time: Double, exact: Bool = true) {
    guard !clipSets.isEmpty else { return }
    let clamped = max(0, min(time, totalDuration - 0.001))
    var idx = 0
    for i in 0..<startOffsets.count {
      if i + 1 < startOffsets.count {
        if clamped >= startOffsets[i] && clamped < startOffsets[i + 1] {
          idx = i
          break
        }
      } else {
        idx = i
      }
    }
    let local = clamped - (startOffsets[safe: idx] ?? 0)
    if idx != currentIndex {
      currentIndex = idx
      playback.load(set: clipSets[idx], startSeconds: local)
      loadTelemetry(for: clipSets[idx])
    } else {
      playback.seek(to: local, exact: exact)
    }
    currentSeconds = clamped
  }

  private func loadTelemetry(for set: ClipSet) {
    let url = set.file(for: .front) ?? set.file(for: .back) ?? set.files.values.first
    telemetryTimeline = nil
    telemetryURL = url
    telemetryText = ""
    guard let fileURL = url else { return }
    DispatchQueue.global(qos: .utility).async {
      let timeline = try? TelemetryParser.parseTimeline(url: fileURL)
      DispatchQueue.main.async {
        guard self.telemetryURL == fileURL else { return }
        self.telemetryTimeline = timeline
      }
    }
  }

  private func formatTelemetry(_ sei: SeiMetadata?) -> String {
    guard let s = sei else { return "" }
    let speedKmh = Double(s.vehicleSpeedMps) * 3.6
    let speed = String(format: "%.1f km/h", speedKmh)
    let gear: String
    switch s.gearState {
    case .park: gear = "P"
    case .drive: gear = "D"
    case .reverse: gear = "R"
    case .neutral: gear = "N"
    }
    let ap: String
    switch s.autopilotState {
    case .none: ap = "Off"
    case .selfDriving: ap = "FSD"
    case .autosteer: ap = "Autosteer"
    case .tacc: ap = "TACC"
    }
    return "Speed: \(speed)  Gear: \(gear)  AP: \(ap)  Brake: \(s.brakeApplied ? "On" : "Off")"
  }

  private func orderCameras(_ cams: [Camera]) -> [Camera] {
    let priority: [Camera] = [.front, .back, .left_repeater, .right_repeater, .left_pillar, .right_pillar]
    return priority.filter { cams.contains($0) }
  }
}
