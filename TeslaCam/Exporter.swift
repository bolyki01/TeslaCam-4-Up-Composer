import Foundation
import Combine
import AppKit
import Darwin

enum ExportJobPhase: String {
  case idle
  case preparing
  case renderingParts
  case concatenating
  case finishing
  case failed
  case cancelled
  case completed

  var displayName: String {
    switch self {
    case .idle: return "Idle"
    case .preparing: return "Preparing clips"
    case .renderingParts: return "Rendering"
    case .concatenating: return "Concatenating"
    case .finishing: return "Finalizing movie"
    case .failed: return "Failed"
    case .cancelled: return "Cancelled"
    case .completed: return "Completed"
    }
  }
}

enum ExportFailureCategory: String {
  case missingScript
  case missingTools
  case outputWrite
  case launch
  case preparation
  case partRender
  case concat
  case cancelled
  case unknown

  var displayName: String {
    switch self {
    case .missingScript: return "Missing Script"
    case .missingTools: return "Missing Tools"
    case .outputWrite: return "Output Write Failure"
    case .launch: return "Launch Failure"
    case .preparation: return "Preparation Failure"
    case .partRender: return "Part Render Failure"
    case .concat: return "Concat Failure"
    case .cancelled: return "Cancelled"
    case .unknown: return "Unknown Failure"
    }
  }
}

struct ExportRequest: Identifiable {
  let id = UUID()
  let sets: [ClipSet]
  let outputURL: URL
  let useSixCam: Bool
  let preset: ExportPreset
  let enabledCameras: Set<Camera>
  let selectedRangeText: String
  let partialClipCount: Int

  var totalParts: Int {
    sets.count
  }
}

struct ExportIssue: Identifiable {
  let id = UUID()
  let message: String
  let isBlocking: Bool
}

struct ExportPreflightSummary {
  let blockingIssues: [ExportIssue]
  let warnings: [ExportIssue]

  var canExport: Bool {
    blockingIssues.isEmpty
  }
}

struct ExportJobSnapshot: Identifiable {
  let id: UUID
  let request: ExportRequest
  var phase: ExportJobPhase
  var progress: Double
  var phaseLabel: String
  var startedAt: Date
  var finishedAt: Date?
  var outputURL: URL
  var logFileURL: URL
  var workingDirectoryURL: URL?
  var failureCategory: ExportFailureCategory?
  var failureReason: String?
  var completedParts: Int
  var totalParts: Int
  var isIndeterminate: Bool
  var isTerminal: Bool
  var canRevealOutput: Bool
  var canRevealWorkingFiles: Bool
  var canRetry: Bool
  var isCancelled: Bool

  var elapsedTime: TimeInterval {
    (finishedAt ?? Date()).timeIntervalSince(startedAt)
  }

  var progressPercentText: String {
    "\(Int((progress * 100).rounded()))%"
  }

  var detailText: String {
    if totalParts > 0 {
      return "\(completedParts) / \(totalParts) minutes"
    }
    return request.selectedRangeText
  }
}

private struct MutableExportSession {
  let id: UUID
  let request: ExportRequest
  var phase: ExportJobPhase
  var progress: Double
  var phaseLabel: String
  var startedAt: Date
  var finishedAt: Date?
  var outputURL: URL
  var logFileURL: URL
  var tempRootURL: URL?
  var failureCategory: ExportFailureCategory?
  var failureReason: String?
  var completedParts: Int
  var totalParts: Int
  var isIndeterminate: Bool
  var isTerminal: Bool
  var canRevealOutput: Bool
  var canRevealWorkingFiles: Bool
  var canRetry: Bool
  var isCancelled: Bool

  func snapshot(fileManager: FileManager) -> ExportJobSnapshot {
    ExportJobSnapshot(
      id: id,
      request: request,
      phase: phase,
      progress: progress,
      phaseLabel: phaseLabel,
      startedAt: startedAt,
      finishedAt: finishedAt,
      outputURL: outputURL,
      logFileURL: logFileURL,
      workingDirectoryURL: tempRootURL,
      failureCategory: failureCategory,
      failureReason: failureReason,
      completedParts: completedParts,
      totalParts: totalParts,
      isIndeterminate: isIndeterminate,
      isTerminal: isTerminal,
      canRevealOutput: canRevealOutput && fileManager.fileExists(atPath: outputURL.path),
      canRevealWorkingFiles: canRevealWorkingFiles && tempRootURL != nil,
      canRetry: canRetry,
      isCancelled: isCancelled
    )
  }
}

final class ExportController: ObservableObject {
  @Published var log: String = ""
  @Published var lastError: String = ""
  @Published var currentJob: ExportJobSnapshot?
  @Published var exportHistory: [ExportJobSnapshot] = []
  @Published var isStatusPresented: Bool = false

  var isExporting: Bool {
    guard let currentJob else { return false }
    return !currentJob.isTerminal
  }

  private let fm = FileManager.default
  private let processLock = NSLock()
  private var runningProcess: Process?
  private var runningReadHandle: FileHandle?
  private var activeSession: MutableExportSession?
  private var outputBuffer = ""
  private var cancelRequested = false
  private lazy var logFileURL: URL = {
    let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = base.appendingPathComponent("TeslaCam", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("export.log")
  }()

  private enum ExportError: LocalizedError {
    case missingScript
    case missingTools
    case outputWrite(String)
    case processLaunchFailed(String)
    case preparation(String)

    var errorDescription: String? {
      switch self {
      case .missingScript:
        return "Composer script not found."
      case .missingTools:
        return "Bundled ffmpeg tools are missing."
      case .outputWrite(let detail):
        return detail
      case .processLaunchFailed(let detail):
        return "Failed to launch composer: \(detail)"
      case .preparation(let detail):
        return detail
      }
    }
  }

  func preflightSummary(
    request: ExportRequest
  ) -> ExportPreflightSummary {
    var blocking: [ExportIssue] = []
    var warnings: [ExportIssue] = []

    guard bundledScriptURL(useSixCam: request.useSixCam) != nil else {
      blocking.append(ExportIssue(message: "Composer script is missing from the app bundle.", isBlocking: true))
      return ExportPreflightSummary(blockingIssues: blocking, warnings: warnings)
    }
    guard bundledFfmpegPaths() != nil else {
      blocking.append(ExportIssue(message: "Bundled ffmpeg/ffprobe tools are missing from the app bundle.", isBlocking: true))
      return ExportPreflightSummary(blockingIssues: blocking, warnings: warnings)
    }

    if request.sets.isEmpty {
      blocking.append(ExportIssue(message: "There are no clips in the selected export range.", isBlocking: true))
    }

    let outputDir = request.outputURL.deletingLastPathComponent()
    var isDir: ObjCBool = false
    if !fm.fileExists(atPath: outputDir.path, isDirectory: &isDir) {
      do {
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
      } catch {
        blocking.append(ExportIssue(message: "Cannot create output directory: \(outputDir.path)", isBlocking: true))
      }
    } else if !isDir.boolValue {
      blocking.append(ExportIssue(message: "Output parent path is not a directory.", isBlocking: true))
    }

    if !fm.isWritableFile(atPath: outputDir.path) {
      blocking.append(ExportIssue(message: "Output directory is not writable: \(outputDir.path)", isBlocking: true))
    }

    if request.partialClipCount > 0 {
      warnings.append(ExportIssue(message: "\(request.partialClipCount) selected minute(s) are missing one or more cameras and will export with black placeholders.", isBlocking: false))
    }

    let hiddenCameras = Camera.allCases.filter { !request.enabledCameras.contains($0) }
    if !hiddenCameras.isEmpty {
      warnings.append(ExportIssue(message: "Hidden cameras will export as black tiles: \(hiddenCameras.map(\.displayName).joined(separator: ", ")).", isBlocking: false))
    }

    return ExportPreflightSummary(blockingIssues: blocking, warnings: warnings)
  }

  func export(request: ExportRequest) {
    guard !isExporting else { return }

    let preflight = preflightSummary(request: request)
    guard preflight.canExport else {
      lastError = preflight.blockingIssues.map(\.message).joined(separator: "\n")
      return
    }

    guard let scriptURL = bundledScriptURL(useSixCam: request.useSixCam) else {
      failBeforeLaunch(category: .missingScript, message: ExportError.missingScript.localizedDescription)
      return
    }
    guard bundledFfmpegPaths() != nil else {
      failBeforeLaunch(category: .missingTools, message: ExportError.missingTools.localizedDescription)
      return
    }

    let session = MutableExportSession(
      id: UUID(),
      request: request,
      phase: .preparing,
      progress: 0.02,
      phaseLabel: ExportJobPhase.preparing.displayName,
      startedAt: Date(),
      finishedAt: nil,
      outputURL: request.outputURL,
      logFileURL: logFileURL,
      tempRootURL: nil,
      failureCategory: nil,
      failureReason: nil,
      completedParts: 0,
      totalParts: request.totalParts,
      isIndeterminate: false,
      isTerminal: false,
      canRevealOutput: false,
      canRevealWorkingFiles: false,
      canRetry: false,
      isCancelled: false
    )

    activeSession = session
    cancelRequested = false
    outputBuffer = ""
    log = ""
    lastError = ""
    resetLogFile()
    appendLog("Log file: \(logFileURL.path)\n")
    appendLog("Export start: \(Date())\n")
    appendLog("Output: \(request.outputURL.path)\n")
    appendLog("Preset: \(request.preset.displayName)\n")
    appendLog("Range: \(request.selectedRangeText)\n")
    appendLog("Selected cameras: \(request.enabledCameras.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: ", "))\n")
    for warning in preflight.warnings {
      appendLog("Warning: \(warning.message)\n")
    }
    publishCurrentSession()
    isStatusPresented = true

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("teslacam_export_\(session.id.uuidString)")
        let inputDir = tempRoot.appendingPathComponent("input", isDirectory: true)
        let workDir = tempRoot.appendingPathComponent("parts", isDirectory: true)
        try self.fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try self.fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        DispatchQueue.main.async {
          self.updateSession {
            $0.tempRootURL = tempRoot
            $0.canRevealWorkingFiles = true
            $0.phase = .preparing
            $0.phaseLabel = "Preparing clips"
            $0.progress = 0.05
            $0.isIndeterminate = false
          }
        }

        try self.populateInputFolder(sets: request.sets, inputDir: inputDir, enabledCameras: request.enabledCameras)
        let ffmpegPaths = self.bundledFfmpegPaths()
        guard ffmpegPaths != nil else {
          throw ExportError.missingTools
        }

        DispatchQueue.main.async {
          self.updateSession {
            $0.phase = .preparing
            $0.phaseLabel = "Prepared \(request.totalParts) minute(s)"
            $0.progress = 0.10
          }
        }

        try self.runComposer(
          script: scriptURL,
          request: request,
          inputDir: inputDir,
          outputURL: request.outputURL,
          workDir: workDir,
          ffmpegPaths: ffmpegPaths
        )
      } catch {
        DispatchQueue.main.async {
          self.finishFailure(error: error)
        }
      }
    }
  }

  func retry(_ snapshot: ExportJobSnapshot) {
    export(request: snapshot.request)
  }

  func cancelExport() {
    processLock.lock()
    let process = runningProcess
    let handle = runningReadHandle
    processLock.unlock()

    handle?.readabilityHandler = nil

    cancelRequested = true
    appendLog("\nCancel requested. Stopping exporter...\n")
    updateSession {
      $0.phase = .cancelled
      $0.phaseLabel = "Cancelling export"
      $0.failureCategory = .cancelled
      $0.failureReason = "Export cancelled by user."
      $0.isCancelled = true
    }

    guard let process else {
      finalizeCancellation()
      return
    }

    if process.isRunning {
      process.terminate()
      killChildProcesses(of: process.processIdentifier, signal: "-TERM")

      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.7) { [weak self, weak process] in
        guard let self, let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        self.killChildProcesses(of: process.processIdentifier, signal: "-KILL")
      }
    } else {
      finalizeCancellation()
    }
  }

  func revealLog() {
    NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
  }

  func revealOutput(for snapshot: ExportJobSnapshot? = nil) {
    let url = (snapshot ?? currentJob)?.outputURL
    guard let url else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func revealWorkingFiles(for snapshot: ExportJobSnapshot? = nil) {
    guard let url = (snapshot ?? currentJob)?.workingDirectoryURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func populateInputFolder(sets: [ClipSet], inputDir: URL, enabledCameras: Set<Camera>) throws {
    for set in sets {
      for (camera, src) in set.files {
        guard enabledCameras.contains(camera) else { continue }
        let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
        let name = "\(set.timestamp)-\(camera.rawValue).\(ext)"
        let dest = inputDir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) { continue }
        guard fm.isReadableFile(atPath: src.path) else { continue }
        do {
          try fm.linkItem(at: src, to: dest)
        } catch {
          do {
            try fm.copyItem(at: src, to: dest)
          } catch {
            throw ExportError.preparation("Failed to prepare clip \(src.lastPathComponent).")
          }
        }
      }
    }
  }

  private func runComposer(
    script: URL,
    request: ExportRequest,
    inputDir: URL,
    outputURL: URL,
    workDir: URL,
    ffmpegPaths: (ffmpeg: String, ffprobe: String)?
  ) throws {
    guard fm.fileExists(atPath: script.path) else {
      throw ExportError.missingScript
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [script.path, inputDir.path, outputURL.path]
    process.qualityOfService = .userInitiated

    var env = ProcessInfo.processInfo.environment
    env["PRESET"] = request.preset.scriptPreset
    env["X265_PRESET"] = "fast"
    env["X265_CRF"] = "6"
    env["VT_Q"] = "5"
    env["GOP"] = "36"
    env["NO_UPSCALE"] = "1"
    env["FFLOGLEVEL"] = "info"
    env["WORKDIR"] = workDir.path
    if let paths = ffmpegPaths {
      let existing = env["PATH"] ?? ""
      let binDir = URL(fileURLWithPath: paths.ffmpeg).deletingLastPathComponent().path
      env["PATH"] = binDir + ":" + existing
      env["FFMPEG"] = paths.ffmpeg
      env["FFPROBE"] = paths.ffprobe
      appendLog("Using bundled ffmpeg: \(binDir)\n")
    }
    process.environment = env

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = nil

    let handle = pipe.fileHandleForReading
    handle.readabilityHandler = { [weak self] reader in
      let data = reader.availableData
      guard !data.isEmpty, let self else { return }
      guard let str = String(data: data, encoding: .utf8) else { return }
      DispatchQueue.main.async {
        self.consumeProcessOutput(str)
      }
    }

    do {
      try process.run()
      processLock.lock()
      runningProcess = process
      runningReadHandle = handle
      processLock.unlock()
    } catch {
      processLock.lock()
      runningProcess = nil
      runningReadHandle = nil
      processLock.unlock()
      let detail = (error as NSError)
      appendLog("Process launch failed: \(detail.localizedDescription)\n")
      throw ExportError.processLaunchFailed(detail.localizedDescription)
    }

    process.waitUntilExit()

    DispatchQueue.main.async {
      handle.readabilityHandler = nil
      self.processLock.lock()
      self.runningProcess = nil
      self.runningReadHandle = nil
      self.processLock.unlock()
      self.flushOutputBuffer()

      if self.cancelRequested {
        self.finalizeCancellation()
        return
      }

      if process.terminationStatus == 0 {
        self.updateSession {
          $0.phase = .completed
          $0.phaseLabel = "Export complete"
          $0.progress = 1.0
          $0.finishedAt = Date()
          $0.isTerminal = true
          $0.canRevealOutput = true
          $0.canRetry = true
          $0.isIndeterminate = false
        }
        self.appendLog("\nDone: \(outputURL.path)\n")
        self.cleanupTempRootIfNeeded(keepFiles: false)
        self.publishCurrentSession()
      } else {
        let category = self.activeSession?.failureCategory ?? .unknown
        let reason = self.activeSession?.failureReason ?? "Composer exited with status \(process.terminationStatus)."
        self.updateSession {
          $0.phase = .failed
          $0.phaseLabel = category == .concat ? "Concat failed" : "Export failed"
          $0.progress = min($0.progress, 0.98)
          $0.finishedAt = Date()
          $0.failureCategory = category
          $0.failureReason = reason
          $0.isTerminal = true
          $0.canRetry = true
          $0.canRevealWorkingFiles = true
          $0.isIndeterminate = false
        }
        self.lastError = reason
        self.appendLog("\nComposer exited with status \(process.terminationStatus).\n")
        self.publishCurrentSession()
      }
    }
  }

  private func finishFailure(error: Error) {
    let exportError = error as? ExportError
    let category: ExportFailureCategory
    switch exportError {
    case .missingScript:
      category = .missingScript
    case .missingTools:
      category = .missingTools
    case .outputWrite:
      category = .outputWrite
    case .processLaunchFailed:
      category = .launch
    case .preparation:
      category = .preparation
    case nil:
      category = .unknown
    }
    let message = error.localizedDescription
    appendLog("Export failed: \(message)\n")
    updateSession {
      $0.phase = .failed
      $0.phaseLabel = "Export failed"
      $0.finishedAt = Date()
      $0.failureCategory = category
      $0.failureReason = message
      $0.isTerminal = true
      $0.canRetry = true
      $0.canRevealWorkingFiles = true
      $0.isIndeterminate = false
    }
    lastError = message
    publishCurrentSession()
  }

  private func failBeforeLaunch(category: ExportFailureCategory, message: String) {
    let request = currentJob?.request
    appendLog("Export failed: \(message)\n")
    if request == nil {
      lastError = message
      return
    }
    updateSession {
      $0.phase = .failed
      $0.phaseLabel = "Export failed"
      $0.finishedAt = Date()
      $0.failureCategory = category
      $0.failureReason = message
      $0.isTerminal = true
      $0.canRetry = true
      $0.isIndeterminate = false
    }
    lastError = message
    publishCurrentSession()
  }

  private func finalizeCancellation() {
    updateSession {
      $0.phase = .cancelled
      $0.phaseLabel = "Export cancelled"
      $0.progress = min($0.progress, 0.99)
      $0.finishedAt = Date()
      $0.failureCategory = .cancelled
      $0.failureReason = "Export cancelled by user."
      $0.isTerminal = true
      $0.canRetry = true
      $0.isCancelled = true
      $0.isIndeterminate = false
    }
    cleanupTempRootIfNeeded(keepFiles: false)
    publishCurrentSession()
  }

  private func cleanupTempRootIfNeeded(keepFiles: Bool) {
    guard let tempRoot = activeSession?.tempRootURL else { return }
    if !keepFiles {
      try? fm.removeItem(at: tempRoot)
      updateSession {
        $0.tempRootURL = nil
        $0.canRevealWorkingFiles = false
      }
    }
  }

  private func consumeProcessOutput(_ text: String) {
    outputBuffer.append(text)
    while let newline = outputBuffer.firstIndex(of: "\n") {
      let line = String(outputBuffer[..<newline])
      outputBuffer.removeSubrange(...newline)
      appendLog(line + "\n")
      parseProgressMarker(line)
    }
  }

  private func flushOutputBuffer() {
    guard !outputBuffer.isEmpty else { return }
    appendLog(outputBuffer)
    parseProgressMarker(outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
    outputBuffer = ""
  }

  private func parseProgressMarker(_ line: String) {
    guard line.hasPrefix("TESLACAM_PROGRESS|") else { return }
    let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 2 else { return }
    let event = parts[1]
    switch event {
    case "TOTAL":
      guard let total = Int(parts[safe: 2] ?? "") else { return }
      updateSession {
        $0.phase = .renderingParts
        $0.phaseLabel = "Rendering minute 1 of \(max(total, 1))"
        $0.totalParts = total
        $0.progress = 0.10
        $0.completedParts = 0
      }
    case "WORKDIR":
      guard let path = parts[safe: 2] else { return }
      updateSession {
        $0.tempRootURL = URL(fileURLWithPath: path)
        $0.canRevealWorkingFiles = true
      }
    case "RENDER_START":
      guard let index = Int(parts[safe: 2] ?? ""),
            let total = Int(parts[safe: 3] ?? "") else { return }
      let label = "Rendering minute \(index) of \(total)"
      updateSession {
        $0.phase = .renderingParts
        $0.phaseLabel = label
        $0.totalParts = total
        $0.progress = renderProgress(completed: max(0, index - 1), total: total)
      }
    case "RENDER_OK":
      guard let index = Int(parts[safe: 2] ?? ""),
            let total = Int(parts[safe: 3] ?? "") else { return }
      updateSession {
        $0.phase = .renderingParts
        $0.phaseLabel = index >= total ? "Rendered \(total) minute(s)" : "Rendering minute \(min(index + 1, total)) of \(total)"
        $0.completedParts = index
        $0.totalParts = total
        $0.progress = renderProgress(completed: index, total: total)
      }
    case "RENDER_FAIL":
      guard let index = Int(parts[safe: 2] ?? ""),
            let total = Int(parts[safe: 3] ?? "") else { return }
      let timestamp = parts[safe: 4] ?? "unknown timestamp"
      updateSession {
        $0.phase = .failed
        $0.phaseLabel = "Render failed"
        $0.completedParts = max($0.completedParts, index - 1)
        $0.totalParts = total
        $0.failureCategory = .partRender
        $0.failureReason = "Failed while rendering \(timestamp)."
      }
    case "CONCAT_START":
      updateSession {
        $0.phase = .concatenating
        $0.phaseLabel = "Concatenating rendered minutes"
        $0.progress = 0.92
      }
    case "CONCAT_OK":
      updateSession {
        $0.phase = .finishing
        $0.phaseLabel = "Finalizing movie"
        $0.progress = 0.98
      }
    case "CONCAT_FAIL":
      updateSession {
        $0.phase = .failed
        $0.phaseLabel = "Concat failed"
        $0.failureCategory = .concat
        $0.failureReason = "Failed while concatenating rendered parts."
      }
    case "DONE":
      updateSession {
        $0.phase = .finishing
        $0.phaseLabel = "Finalizing movie"
        $0.progress = 0.99
      }
    case "OUTPUT":
      guard let path = parts[safe: 2] else { return }
      updateSession {
        $0.outputURL = URL(fileURLWithPath: path)
      }
    default:
      break
    }
  }

  private func renderProgress(completed: Int, total: Int) -> Double {
    guard total > 0 else { return 0.10 }
    return 0.10 + (0.80 * (Double(completed) / Double(total)))
  }

  private func updateSession(_ update: (inout MutableExportSession) -> Void) {
    guard var session = activeSession else { return }
    update(&session)
    activeSession = session
    publishCurrentSession()
  }

  private func publishCurrentSession() {
    guard let session = activeSession else {
      currentJob = nil
      return
    }
    let snapshot = session.snapshot(fileManager: fm)
    currentJob = snapshot
    if snapshot.isTerminal {
      exportHistory.removeAll { $0.id == snapshot.id }
      exportHistory.insert(snapshot, at: 0)
      activeSession = session
    }
  }

  private func appendLog(_ text: String) {
    let maxLen = 60000
    log.append(text)
    if log.count > maxLen {
      log = String(log.suffix(maxLen))
    }
    appendLogToFile(text)
  }

  private func resetLogFile() {
    if fm.fileExists(atPath: logFileURL.path) {
      try? fm.removeItem(at: logFileURL)
    }
    fm.createFile(atPath: logFileURL.path, contents: nil)
  }

  private func appendLogToFile(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    guard fm.fileExists(atPath: logFileURL.path) else {
      fm.createFile(atPath: logFileURL.path, contents: data)
      return
    }
    if let handle = try? FileHandle(forWritingTo: logFileURL) {
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        // Ignore file logging errors.
      }
      try? handle.close()
    }
  }

  func bundledScriptURL(useSixCam: Bool) -> URL? {
    let name = useSixCam ? "teslacam_6up_all_max" : "teslacam_4up_all_max"
    #if SWIFT_PACKAGE
    return Bundle.module.url(forResource: name, withExtension: "sh")
    #else
    return Bundle.main.url(forResource: name, withExtension: "sh")
    #endif
  }

  func bundledFfmpegPaths() -> (ffmpeg: String, ffprobe: String)? {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    if let dir = bundle.resourceURL?.appendingPathComponent("ffmpeg_bin") {
      let ffmpeg = dir.appendingPathComponent("ffmpeg")
      let ffprobe = dir.appendingPathComponent("ffprobe")
      if fm.fileExists(atPath: ffmpeg.path), fm.fileExists(atPath: ffprobe.path) {
        return (ffmpeg.path, ffprobe.path)
      }
    }
    if let ffmpeg = bundle.url(forResource: "ffmpeg", withExtension: nil),
       let ffprobe = bundle.url(forResource: "ffprobe", withExtension: nil) {
      return (ffmpeg.path, ffprobe.path)
    }
    return nil
  }

  private func killChildProcesses(of pid: Int32, signal: String) {
    let killer = Process()
    killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    killer.arguments = [signal, "-P", "\(pid)"]
    do {
      try killer.run()
      killer.waitUntilExit()
    } catch {
      // Best effort cleanup only.
    }
  }
}
