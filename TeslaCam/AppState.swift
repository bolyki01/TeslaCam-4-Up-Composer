import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

final class AppState: ObservableObject {
  @Published var rootURL: URL?
  @Published var sourceURLs: [URL] = []
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
  @Published var exportPreset: ExportPreset = .maxQualityHEVC
  @Published var selectedExportCameras: Set<Camera> = Set(Camera.allCases)
  @Published var healthSummary: ExportHealthSummary?

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
    guard !exporter.isExporting else { return }
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = "Select TeslaCam Files/Folders"
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = true
    panel.prompt = "Choose"

    if panel.runModal() == .OK {
      indexSources(panel.urls)
    }
  }

  func indexFolder(_ url: URL) {
    indexSources([url])
  }

  func indexSources(_ urls: [URL]) {
    guard !exporter.isExporting else { return }
    let normalizedSources = normalizeSources(urls)
    guard !normalizedSources.isEmpty else { return }

    isIndexing = true
    indexStatus = "Scanning..."
    clipSets = []
    camerasDetected = []
    healthSummary = nil

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let index = try ClipIndexer.index(inputURLs: normalizedSources) { scanned in
          DispatchQueue.main.async {
            self.indexStatus = "Indexed \(scanned) clips..."
          }
        }
        DispatchQueue.main.async {
          self.rootURL = normalizedSources.first
          self.sourceURLs = normalizedSources
          self.clipSets = index.sets
          self.minDate = index.minDate
          self.maxDate = index.maxDate
          self.selectedStart = index.minDate
          self.selectedEnd = index.maxDate
          self.currentIndex = 0
          self.camerasDetected = self.orderCameras(Array(index.camerasFound))
          self.selectedExportCameras = Set(self.camerasDetected)
          self.healthSummary = self.buildHealthSummary(from: index.sets)
          self.rebuildTimeline()
          if let first = index.sets.first {
            self.playback.load(set: first)
            self.currentSeconds = 0
            self.loadTelemetry(for: first)
            self.updateOverlayAndTelemetry(index: 0, localSeconds: 0)
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
          self.errorMessage = "No clips found in the selected files/folders."
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
    updateOverlayAndTelemetry(index: 0, localSeconds: 0)
  }

  func normalizeRange() {
    if selectedEnd < selectedStart {
      selectedEnd = selectedStart
    }
  }

  func setFullRange() {
    if let minDate, let maxDate {
      selectedStart = minDate
      selectedEnd = maxDate
    }
  }

  func setCurrentMinuteRange() {
    guard let set = clipSets[safe: currentIndex] else { return }
    let minute = floorToMinute(set.date)
    selectedStart = minute
    selectedEnd = minute
  }

  func setRecentRange(minutes: Int) {
    guard let maxDate else { return }
    let end = floorToMinute(maxDate)
    let start = max(minDate ?? end, end.addingTimeInterval(Double(-(minutes - 1) * 60)))
    selectedStart = floorToMinute(start)
    selectedEnd = end
    normalizeRange()
  }

  func toggleExportCamera(_ camera: Camera, isEnabled: Bool) {
    if isEnabled {
      selectedExportCameras.insert(camera)
    } else {
      selectedExportCameras.remove(camera)
      if selectedExportCameras.isEmpty, let first = camerasDetected.first {
        selectedExportCameras.insert(first)
      }
    }
  }

  func exportRange() {
    guard !clipSets.isEmpty, !exporter.isExporting else { return }
    normalizeRange()

    let panel = NSSavePanel()
    panel.title = "Save Export"
    panel.nameFieldStringValue = defaultExportFilename()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = exportPreset.defaultExtension == "mov" ? [.movie] : [.mpeg4Movie]

    if panel.runModal() == .OK, let url = panel.url {
      guard let request = makeExportRequest(for: url) else {
        errorMessage = "No clips found in the selected range."
        showError = true
        return
      }
      let preflight = exporter.preflightSummary(request: request)
      if !preflight.canExport {
        errorMessage = preflight.blockingIssues.map(\.message).joined(separator: "\n")
        showError = true
        return
      }
      exporter.export(request: request)
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

  func ingestDroppedURLs(_ urls: [URL]) {
    guard !exporter.isExporting else { return }
    indexSources(urls)
  }

  var sourceSummary: String {
    guard !sourceURLs.isEmpty else { return "" }
    if sourceURLs.count == 1 {
      return sourceURLs[0].path
    }
    return "\(sourceURLs.count) inputs • \(sourceURLs[0].lastPathComponent) + \(sourceURLs.count - 1) more"
  }

  var selectedSetsForExport: [ClipSet] {
    normalizeRange()
    let start = floorToMinute(selectedStart)
    let end = floorToMinute(selectedEnd)
    return clipSets.filter { $0.date >= start && $0.date <= end }
  }

  var selectedRangeDescription: String {
    let sets = selectedSetsForExport
    guard let first = sets.first, let last = sets.last else { return "No clips selected" }
    return "\(formatDateTime(first.date))  ->  \(formatDateTime(last.date))"
  }

  var partialSelectedSetCount: Int {
    let enabled = activeExportCameras
    guard !enabled.isEmpty else { return 0 }
    return selectedSetsForExport.reduce(into: 0) { result, set in
      let available = Set(set.files.keys).intersection(enabled)
      if available.count < enabled.count {
        result += 1
      }
    }
  }

  var exportWarningsPreview: [String] {
    var warnings: [String] = []
    if partialSelectedSetCount > 0 {
      warnings.append("\(partialSelectedSetCount) selected minute(s) are missing one or more enabled cameras and will use black placeholders.")
    }
    let hidden = camerasDetected.filter { !activeExportCameras.contains($0) }
    if !hidden.isEmpty {
      warnings.append("Hidden cameras will export as black tiles: \(hidden.map(\.displayName).joined(separator: ", ")).")
    }
    return warnings
  }

  var activeExportCameras: Set<Camera> {
    let detected = Set(camerasDetected)
    let filtered = selectedExportCameras.intersection(detected)
    if !filtered.isEmpty {
      return filtered
    }
    return detected.isEmpty ? Set(Camera.allCases) : detected
  }

  func shutdownForTermination() {
    seekWorkItem?.cancel()
    playback.stop()
    exporter.cancelExport()
  }

  private func updateCurrentSeconds(localSeconds: Double) {
    guard !isUserSeeking else { return }
    let start = startOffsets[safe: currentIndex] ?? 0
    let local = max(0, localSeconds)
    currentSeconds = start + local
    updateOverlayAndTelemetry(index: currentIndex, localSeconds: local)
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
    updateOverlayAndTelemetry(index: idx, localSeconds: local)
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
        let local = self.currentSeconds - (self.startOffsets[safe: self.currentIndex] ?? 0)
        self.updateOverlayAndTelemetry(index: self.currentIndex, localSeconds: local)
      }
    }
  }

  private func updateOverlayAndTelemetry(index: Int, localSeconds: Double) {
    let safeLocal = max(0, localSeconds)
    let base = clipSets[safe: index]?.date ?? Date()
    overlayText = overlayFormatter.string(from: base.addingTimeInterval(safeLocal))
    if let timeline = telemetryTimeline {
      let frame = timeline.closest(to: safeLocal * 1000.0)
      telemetryText = formatTelemetry(frame?.sei)
    } else {
      telemetryText = ""
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

  private func normalizeSources(_ urls: [URL]) -> [URL] {
    let fm = FileManager.default
    var seen = Set<String>()
    var out: [URL] = []
    out.reserveCapacity(urls.count)
    for raw in urls {
      let u = raw.standardizedFileURL
      guard fm.fileExists(atPath: u.path) else { continue }
      let key = u.path
      if seen.contains(key) { continue }
      seen.insert(key)
      out.append(u)
    }
    return out
  }

  private func defaultExportFilename() -> String {
    let sets = selectedSetsForExport
    guard let first = sets.first, let last = sets.last else {
      return "teslacam_\(exportPreset.outputLabel).\(exportPreset.defaultExtension)"
    }
    let suffix = first.timestamp == last.timestamp ? first.timestamp : "\(first.timestamp)_to_\(last.timestamp)"
    return "teslacam_\(suffix)_\(exportPreset.outputLabel).\(exportPreset.defaultExtension)"
  }

  private func buildOutputURL(from chosenURL: URL) -> URL {
    var outputURL = chosenURL
    if (try? chosenURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      outputURL = chosenURL.appendingPathComponent(defaultExportFilename())
    }

    let expectedExtension = exportPreset.defaultExtension
    if outputURL.pathExtension.lowercased() != expectedExtension {
      outputURL.deletePathExtension()
      outputURL.appendPathExtension(expectedExtension)
    }
    return outputURL
  }

  private func makeExportRequest(for chosenURL: URL) -> ExportRequest? {
    let sets = selectedSetsForExport
    guard !sets.isEmpty else { return nil }
    let useSix = camerasDetected.count >= 6
    return ExportRequest(
      sets: sets,
      outputURL: buildOutputURL(from: chosenURL),
      useSixCam: useSix,
      preset: exportPreset,
      enabledCameras: activeExportCameras,
      selectedRangeText: selectedRangeDescription,
      partialClipCount: partialSelectedSetCount
    )
  }

  private func buildHealthSummary(from sets: [ClipSet]) -> ExportHealthSummary {
    var gapCount = 0
    var partialSetCount = 0
    var four = 0
    var six = 0
    var missingCameraCounts: [Camera: Int] = [:]

    for (index, set) in sets.enumerated() {
      let count = set.files.count
      if count < 6 {
        partialSetCount += 1
      }
      if count >= 6 {
        six += 1
      } else {
        four += 1
      }
      for camera in Camera.allCases where set.files[camera] == nil {
        missingCameraCounts[camera, default: 0] += 1
      }
      if let next = sets[safe: index + 1] {
        let delta = next.date.timeIntervalSince(set.date)
        if delta > 61 {
          gapCount += 1
        }
      }
    }

    return ExportHealthSummary(
      totalMinutes: sets.count,
      gapCount: gapCount,
      partialSetCount: partialSetCount,
      fourCameraSetCount: four,
      sixCameraSetCount: six,
      missingCameraCounts: missingCameraCounts
    )
  }
}
