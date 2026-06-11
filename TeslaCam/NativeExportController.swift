import Foundation
import Combine
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

struct ExportPlan {
  enum ValidationError: LocalizedError, Equatable {
    case noClips
    case emptyTrimRange
    case noEnabledCameras
    case invalidCanvas

    var errorDescription: String? {
      switch self {
      case .noClips:
        return "There are no clips in the selected export range."
      case .emptyTrimRange:
        return "Selected trim range is empty."
      case .noEnabledCameras:
        return "Select at least one camera to export."
      case .invalidCanvas:
        return "Export canvas could not be prepared."
      }
    }
  }

  let sets: [ClipSet]
  let outputURL: URL
  let useSixCam: Bool
  let preset: ExportPreset
  let enabledCameras: Set<Camera>
  let layoutRequest: CameraLayoutRequest
  let overlayOptions: ExportOverlayOptions
  let trimStartSeconds: Double
  let trimEndSeconds: Double
  let trimStartDate: Date
  let trimEndDate: Date
  let selectedRangeText: String
  let partialClipCount: Int
  let cameraTrack: CameraTrack
  let isPreviewSample: Bool
  fileprivate let layout: TimelineFrameLayout

  var totalParts: Int { sets.count }
  var totalDuration: Double { trimEndDate.timeIntervalSince(trimStartDate) }
  var renderDuration: Double {
    TimelineFrameProvider.renderDuration(
      sets: sets,
      trimStartDate: trimStartDate,
      trimEndDate: trimEndDate
    )
  }
  var canvasSize: CGSize { layout.canvasSize }
  var tileSize: CGSize { layout.tileSize }
  var cameraOrder: [Camera] { layout.cameraOrder }
  var boundsByCamera: [Camera: CGRect] { layout.boundsByCamera }

  init(request: ExportRequest) throws {
    guard !request.sets.isEmpty else {
      throw ValidationError.noClips
    }
    guard request.trimEndDate > request.trimStartDate, request.totalDuration > 0 else {
      throw ValidationError.emptyTrimRange
    }
    guard !request.enabledCameras.isEmpty else {
      throw ValidationError.noEnabledCameras
    }

    let layout = try TimelineFrameLayout.build(
      sets: request.sets,
      enabledCameras: request.enabledCameras,
      useSixCam: request.useSixCam,
      layoutRequest: request.layoutRequest
    )
    guard layout.canvasSize.width.isFinite,
          layout.canvasSize.height.isFinite,
          layout.canvasSize.width > 0,
          layout.canvasSize.height > 0 else {
      throw ValidationError.invalidCanvas
    }

    self.sets = request.sets
    self.outputURL = request.outputURL
    self.useSixCam = request.useSixCam
    self.preset = request.preset
    self.enabledCameras = request.enabledCameras
    self.layoutRequest = request.layoutRequest
    self.overlayOptions = request.overlayOptions
    self.trimStartSeconds = request.trimStartSeconds
    self.trimEndSeconds = request.trimEndSeconds
    self.trimStartDate = request.trimStartDate
    self.trimEndDate = request.trimEndDate
    self.selectedRangeText = request.selectedRangeText
    self.partialClipCount = request.partialClipCount
    self.cameraTrack = request.cameraTrack
    self.isPreviewSample = request.isPreviewSample
    self.layout = layout
  }
}

protocol ExportPreflightFileAccess {
  func canWrite(to outputURL: URL) -> Bool
  func availableCapacity(forWritingTo outputURL: URL) -> Int64?
}

struct FileManagerExportPreflightFileAccess: ExportPreflightFileAccess {
  var fileManager: FileManager = .default

  func canWrite(to outputURL: URL) -> Bool {
    let targetDirectory = outputURL.deletingLastPathComponent()
    let scopeURL = beginSecurityScope(outputURL: outputURL, targetDirectory: targetDirectory)
    let outputExists = fileManager.fileExists(atPath: outputURL.path)

    defer {
      if !outputExists, fileManager.fileExists(atPath: outputURL.path) {
        try? fileManager.removeItem(at: outputURL)
      }
      scopeURL?.stopAccessingSecurityScopedResource()
    }

    do {
      let values = try targetDirectory.resourceValues(forKeys: [.isDirectoryKey])
      guard values.isDirectory == true else { return false }
      if outputExists {
        return fileManager.isWritableFile(atPath: outputURL.path)
      }
      return fileManager.createFile(
        atPath: outputURL.path,
        contents: Data(),
        attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
      )
    } catch {
      return false
    }
  }

  func availableCapacity(forWritingTo outputURL: URL) -> Int64? {
    let targetDirectory = outputURL.deletingLastPathComponent()
    do {
      let values = try targetDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      if let important = values.volumeAvailableCapacityForImportantUsage {
        return important
      }
      let fallback = try fileManager.attributesOfFileSystem(forPath: targetDirectory.path)
      if let number = fallback[.systemFreeSize] as? NSNumber {
        return number.int64Value
      }
      return fallback[.systemFreeSize] as? Int64
    } catch {
      return nil
    }
  }

  private func beginSecurityScope(outputURL: URL, targetDirectory: URL) -> URL? {
    if outputURL.startAccessingSecurityScopedResource() {
      return outputURL
    }
    if targetDirectory.startAccessingSecurityScopedResource() {
      return targetDirectory
    }
    return nil
  }
}

struct ExportPreflight {
  private static let minimumDiskHeadroomBytes: Int64 = 256 * 1024 * 1024
  private static let hevcEncoderMaxSidePixels: CGFloat = 8192

  var fileAccess: ExportPreflightFileAccess = FileManagerExportPreflightFileAccess()

  func summary(for plan: ExportPlan) -> ExportPreflightSummary {
    var blocking: [ExportIssue] = []
    var warnings: [ExportIssue] = []

    if plan.partialClipCount > 0 {
      warnings.append(ExportIssue(message: "\(plan.partialClipCount) selected clip span(s) are missing one or more cameras and will export with black placeholders.", isBlocking: false))
    }

    let visibleCameras = Set(plan.sets.flatMap { $0.files.keys }).union(plan.enabledCameras)
    let hiddenCameras = Camera.mixedOrder.filter { visibleCameras.contains($0) && !plan.enabledCameras.contains($0) }
    if !hiddenCameras.isEmpty {
      warnings.append(ExportIssue(message: "Hidden cameras will export as black tiles: \(hiddenCameras.map(\.displayName).joined(separator: ", ")).", isBlocking: false))
    }

    if plan.preset != .editFriendlyProRes,
       plan.canvasSize.width > Self.hevcEncoderMaxSidePixels || plan.canvasSize.height > Self.hevcEncoderMaxSidePixels {
      blocking.append(
        ExportIssue(
          message: "Composite canvas \(Int(plan.canvasSize.width.rounded(.up)))×\(Int(plan.canvasSize.height.rounded(.up))) exceeds the hardware HEVC encoder ceiling (8192 px per side). Reduce enabled cameras or switch to ProRes preset.",
          isBlocking: true
        )
      )
    }

    let hasWriteAccess = fileAccess.canWrite(to: plan.outputURL)
    if !hasWriteAccess {
      blocking.append(ExportIssue(message: "The selected export location is not writable.", isBlocking: true))
    }

    let requiredBytes = estimatedRequiredDiskBytes(for: plan)
    if let availableBytes = fileAccess.availableCapacity(forWritingTo: plan.outputURL) {
      if availableBytes < requiredBytes {
        blocking.append(
          ExportIssue(
            message: "The selected export location has only \(Self.formatBytes(availableBytes)) free. Export preflight requires at least \(Self.formatBytes(requiredBytes)).",
            isBlocking: true
          )
        )
      }
    } else {
      warnings.append(ExportIssue(message: "Free disk space could not be checked for the selected export location.", isBlocking: false))
    }

    return ExportPreflightSummary(
      blockingIssues: blocking,
      warnings: warnings,
      hasWriteAccess: hasWriteAccess,
      resolvedOutputURL: plan.outputURL,
      requiresUserSavePanel: false
    )
  }

  private func estimatedRequiredDiskBytes(for plan: ExportPlan) -> Int64 {
    let seconds = max(1, plan.renderDuration)
    let bytesPerSecond: Double
    switch plan.preset {
    case .editFriendlyProRes:
      bytesPerSecond = 32 * 1024 * 1024
    case .maxQualityHEVC:
      bytesPerSecond = 8 * 1024 * 1024
    case .fastHEVC:
      bytesPerSecond = 4 * 1024 * 1024
    case .socialShareHEVC:
      bytesPerSecond = 2 * 1024 * 1024
    case .proxyHEVC:
      bytesPerSecond = 1 * 1024 * 1024
    }
    let estimatedOutput = Int64((seconds * bytesPerSecond).rounded(.up))
    return max(Self.minimumDiskHeadroomBytes, estimatedOutput + Self.minimumDiskHeadroomBytes)
  }

  private static func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB, .useTB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

final class NativeExportController: ObservableObject {
  private static let staleWorkdirAge: TimeInterval = 24 * 60 * 60

  @Published var log: String = ""
  @Published var lastError: String = ""
  @Published var currentJob: ExportJobSnapshot?
  @Published var exportHistory: [ExportJobSnapshot] = []
  @Published var queuedRequests: [ExportRequest] = []
  @Published var isStatusPresented: Bool = false

  weak var debugLog: DebugLogSink?

  var isExporting: Bool {
    guard let currentJob else { return false }
    return !currentJob.isTerminal
  }

  private let fm = FileManager.default
  private var activeSession: MutableExportSession?
  private var cancelRequested = false
  private var activeOutputScopeURL: URL?
  private lazy var logFileURL: URL = {
    let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = base.appendingPathComponent("TeslaCam", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("native-export.log")
  }()

  private enum ExportError: LocalizedError {
    case preparation(String)
    case encoding(String)
    case cancelled

    var errorDescription: String? {
      switch self {
      case .preparation(let detail), .encoding(let detail):
        return detail
      case .cancelled:
        return "Export cancelled by user."
      }
    }
  }

  func preflightSummary(request: ExportRequest) -> ExportPreflightSummary {
    do {
      return ExportPreflight().summary(for: try ExportPlan(request: request))
    } catch {
      return ExportPreflightSummary(
        blockingIssues: [
          ExportIssue(message: error.localizedDescription, isBlocking: true)
        ],
        warnings: [],
        hasWriteAccess: false,
        resolvedOutputURL: request.outputURL,
        requiresUserSavePanel: false
      )
    }
  }

  func export(request: ExportRequest) {
    guard !isExporting else {
      enqueue(request: request)
      return
    }
    cleanupStaleTempDirectories()
    beginOutputScope(for: request.outputURL)
    debug("start \(request.outputURL.lastPathComponent) preset=\(request.preset.rawValue)", category: "export")

    let preflight = preflightSummary(request: request)
    guard preflight.canExport else {
      publishBlockedPreflight(request: request, preflight: preflight)
      endOutputScope()
      startNextQueuedExportIfIdle()
      return
    }

    let renderDuration = (try? ExportPlan(request: request).renderDuration) ?? request.totalDuration
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
      completedDuration: 0,
      totalDuration: renderDuration,
      isIndeterminate: false,
      isTerminal: false,
      canRevealOutput: false,
      canRevealWorkingFiles: false,
      canRetry: false,
      isCancelled: false
    )

    activeSession = session
    cancelRequested = false
    log = ""
    lastError = ""
    resetLogFile()
    appendLog("Log file: \(logFileURL.path)\n")
    appendLog("Export start: \(Date())\n")
    appendLog("Output: \(request.outputURL.path)\n")
    appendLog("Preset: \(request.preset.displayName)\n")
    appendLog("Range: \(request.selectedRangeText)\n")
    appendLog("Selected cameras: \(request.enabledCameras.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: ", "))\n")
    appendStructuredLogEvent(
      "export_started",
      fields: [
        "output": request.outputURL.path,
        "preset": request.preset.rawValue,
        "range": request.selectedRangeText,
        "duration": String(format: "%.3f", request.totalDuration),
        "parts": "\(request.totalParts)"
      ]
    )
    for warning in preflight.warnings {
      appendLog("Warning: \(warning.message)\n")
      appendStructuredLogEvent("preflight_warning", fields: ["message": warning.message])
    }
    publishCurrentSession()
    isStatusPresented = true

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try self.performExport(request: request)
      } catch {
        self.runOnMain {
          self.finishFailure(error: error)
        }
      }
    }
  }

  func enqueue(request: ExportRequest) {
    queuedRequests.append(request)
    appendStructuredLogEvent("export_queued", fields: ["output": request.outputURL.path])
    startNextQueuedExportIfIdle()
  }

  func clearQueue() {
    queuedRequests.removeAll()
  }

  private func publishBlockedPreflight(request: ExportRequest, preflight: ExportPreflightSummary) {
    let message = preflight.blockingIssues.map(\.message).joined(separator: "\n")
    let now = Date()
    let session = MutableExportSession(
      id: UUID(),
      request: request,
      phase: .failed,
      progress: 1,
      phaseLabel: "Export blocked",
      startedAt: now,
      finishedAt: now,
      outputURL: request.outputURL,
      logFileURL: logFileURL,
      tempRootURL: nil,
      failureCategory: .preparation,
      failureReason: message,
      completedParts: 0,
      totalParts: request.totalParts,
      completedDuration: 0,
      totalDuration: request.totalDuration,
      isIndeterminate: false,
      isTerminal: true,
      canRevealOutput: false,
      canRevealWorkingFiles: false,
      canRetry: true,
      isCancelled: false
    )

    activeSession = session
    currentJob = session.snapshot(fileManager: fm)
    lastError = message
    isStatusPresented = true
    appendLog("Export blocked: \(message)\n")
    appendStructuredLogEvent("export_blocked", fields: ["message": message])
    debug("blocked \(request.outputURL.lastPathComponent): \(message)", category: "export")
  }

  func retry(_ snapshot: ExportJobSnapshot) {
    export(request: snapshot.request)
  }

  func dismissStatus() {
    isStatusPresented = false
    if currentJob?.isTerminal == true {
      currentJob = nil
      activeSession = nil
    }
  }

  func cancelExport() {
    cancelRequested = true
    appendLog("\nCancel requested.\n")
    debug("cancel requested", category: "export")
    updateSession {
      $0.phase = .cancelled
      $0.phaseLabel = "Cancelling export"
      $0.failureCategory = .cancelled
      $0.failureReason = "Export cancelled by user."
      $0.isCancelled = true
    }
  }

  func revealLog() {
    #if os(macOS)
    NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    #endif
  }

  func revealOutput(for snapshot: ExportJobSnapshot? = nil) {
    let url = (snapshot ?? currentJob)?.outputURL
    guard let url else { return }
    #if os(macOS)
    NSWorkspace.shared.activateFileViewerSelecting([url])
    #else
    PlatformFileAccess.shareFile(url)
    #endif
  }

  func revealWorkingFiles(for snapshot: ExportJobSnapshot? = nil) {
    guard let url = (snapshot ?? currentJob)?.workingDirectoryURL else { return }
    #if os(macOS)
    NSWorkspace.shared.activateFileViewerSelecting([url])
    #endif
  }

  private func performExport(request: ExportRequest) throws {
    try measure("native_export_full") {
      let plan = try ExportPlan(request: request)
      let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("teslacam_export_\(UUID().uuidString)", isDirectory: true)
      try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
      let logRoot = tempRoot.appendingPathComponent("logs", isDirectory: true)
      try fm.createDirectory(at: logRoot, withIntermediateDirectories: true)

      runOnMain {
        self.updateSession {
          $0.tempRootURL = tempRoot
          $0.canRevealWorkingFiles = true
          $0.phase = .preparing
          $0.phaseLabel = "Preparing clips"
          $0.progress = 0.05
          $0.isIndeterminate = false
        }
      }

      let frameProvider = TimelineFrameProvider(
        sets: plan.sets,
        trimStartDate: plan.trimStartDate,
        trimEndDate: plan.trimEndDate
      )
      let renderDuration = frameProvider.totalDuration
      let layout = plan.layout
      appendLog("Canvas: \(Int(layout.canvasSize.width))x\(Int(layout.canvasSize.height))\n")
      appendLog("Graph: \(NativeFilterGraphSummary(plan: plan).description)\n")
      debug("layout cameras=\(layout.cameraOrder.map(\.rawValue).joined(separator: ",")) canvas=\(Int(layout.canvasSize.width))x\(Int(layout.canvasSize.height))", category: "export")

      let writer = try NativeMovieWriter(outputURL: plan.outputURL, size: plan.canvasSize, preset: plan.preset)
      try writer.start()

      runOnMain {
        self.updateSession {
          $0.phase = .renderingParts
          $0.phaseLabel = "Rendering timeline"
          $0.progress = 0.10
        }
      }

      let composer = TimelineFrameComposer(
        layout: layout,
        enabledCameras: plan.enabledCameras,
        overlayOptions: plan.overlayOptions
      )
      let fps: Double = 30
      let frameCount = max(1, Int((frameProvider.totalDuration * fps).rounded(.up)))

      for frameIndex in 0..<frameCount {
        if cancelRequested {
          throw ExportError.cancelled
        }

        let renderSeconds = Double(frameIndex) / fps
        let context = frameProvider.context(for: renderSeconds)
        let cameraOverride = plan.cameraTrack.camera(at: request.trimStartSeconds + context.sourceSecondsFromTrimStart)

        if frameIndex == 0 || frameIndex % Int(max(1, fps / 2)) == 0 {
          let completedParts = min(
            request.totalParts,
            max(frameProvider.completedSetCount(at: renderSeconds), (context.clipIndex.map { $0 + 1 } ?? 0))
          )
          runOnMain {
            self.updateSession {
              $0.completedParts = completedParts
              $0.completedDuration = min(renderSeconds, renderDuration)
              $0.phase = .renderingParts
              $0.phaseLabel = "Rendering timeline"
              $0.progress = self.renderProgress(completed: renderSeconds, total: renderDuration)
            }
          }
        }

        let buffer = try composer.makeFrameBuffer(
          at: context.localSeconds,
          set: context.set,
          cameraOverride: cameraOverride
        )
        try writer.append(buffer: buffer, at: CMTime(seconds: renderSeconds, preferredTimescale: 600))
      }

      runOnMain {
        self.updateSession {
          $0.phase = .finishing
          $0.phaseLabel = "Finalizing movie"
          $0.completedParts = request.totalParts
          $0.completedDuration = renderDuration
          $0.progress = 0.98
        }
      }

      try writer.finishWriting()
      if plan.overlayOptions.needsSidecars {
        generateSidecarArtifacts(plan: plan, composer: composer, frameProvider: frameProvider)
      }
      try? fm.removeItem(at: tempRoot)

      runOnMain {
        self.updateSession {
          $0.phase = .completed
          $0.phaseLabel = "Export complete"
          $0.progress = 1.0
          $0.finishedAt = Date()
          $0.completedParts = request.totalParts
          $0.completedDuration = renderDuration
          $0.isTerminal = true
          $0.canRevealOutput = true
          $0.canRevealWorkingFiles = false
          $0.tempRootURL = nil
          $0.canRetry = true
          $0.isIndeterminate = false
        }
        self.appendLog("\nDone: \(request.outputURL.path)\n")
        self.appendStructuredLogEvent("export_completed", fields: ["output": request.outputURL.path])
        self.debug("completed \(request.outputURL.lastPathComponent)", category: "export")
        self.endOutputScope()
        self.publishCurrentSession()
        self.isStatusPresented = true
        self.startNextQueuedExportIfIdle()
      }
    }
  }

  private func generateSidecarArtifacts(
    plan: ExportPlan,
    composer: TimelineFrameComposer,
    frameProvider: TimelineFrameProvider
  ) {
    let outputBase = plan.outputURL.deletingPathExtension()
    if plan.overlayOptions.includeScreenshot {
      let screenshotURL = outputBase.appendingPathExtension("poster.png")
      do {
        let context = frameProvider.context(for: 0)
        let buffer = try composer.makeFrameBuffer(
          at: context.localSeconds,
          set: context.set,
          cameraOverride: plan.cameraTrack.camera(at: plan.trimStartSeconds)
        )
        try writePNG(from: buffer, to: screenshotURL)
        appendStructuredLogEvent("export_screenshot_written", fields: ["path": screenshotURL.path])
      } catch {
        appendStructuredLogEvent("export_screenshot_failed", fields: ["message": error.localizedDescription])
      }
    }

    if plan.overlayOptions.includeReport {
      let reportURL = outputBase.appendingPathExtension("report.pdf")
      do {
        try writeReport(plan: plan, to: reportURL)
        appendStructuredLogEvent("export_report_written", fields: ["path": reportURL.path])
      } catch {
        appendStructuredLogEvent("export_report_failed", fields: ["message": error.localizedDescription])
      }
    }
  }

  private func writePNG(from buffer: CVPixelBuffer, to url: URL) throws {
    let image = CIImage(cvPixelBuffer: buffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(image, from: image.extent) else {
      throw NSError(domain: "TeslaCam", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create export screenshot."])
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw NSError(domain: "TeslaCam", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to open screenshot destination."])
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "TeslaCam", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to write screenshot."])
    }
  }

  private func writeReport(plan: ExportPlan, to url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
      throw NSError(domain: "TeslaCam", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to create report."])
    }
    context.beginPDFPage(nil)
    drawReportLine("TeslaCam Export Report", y: 730, size: 22, context: context, mediaBox: mediaBox)
    drawReportLine("Range: \(plan.selectedRangeText)", y: 690, size: 12, context: context, mediaBox: mediaBox)
    drawReportLine("Duration: \(formatHMS(plan.totalDuration))", y: 670, size: 12, context: context, mediaBox: mediaBox)
    drawReportLine("Cameras: \(plan.enabledCameras.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: ", "))", y: 650, size: 12, context: context, mediaBox: mediaBox)
    drawReportLine("Preset: \(plan.preset.displayName)", y: 630, size: 12, context: context, mediaBox: mediaBox)
    drawReportLine("Output: \(plan.outputURL.lastPathComponent)", y: 610, size: 12, context: context, mediaBox: mediaBox)
    drawReportLine("Clip spans: \(plan.sets.count)", y: 590, size: 12, context: context, mediaBox: mediaBox)
    drawReportLine("Graph: \(NativeFilterGraphSummary(plan: plan).description)", y: 570, size: 10, context: context, mediaBox: mediaBox)
    drawReportLine("HUD: \(plan.overlayOptions.telemetryHUD ? plan.overlayOptions.telemetryHUDMode.displayName : "Off") - Units: \(plan.overlayOptions.speedUnit.displayName)", y: 550, size: 12, context: context, mediaBox: mediaBox)
    if plan.isPreviewSample {
      drawReportLine("Type: Preview sample", y: 530, size: 12, context: context, mediaBox: mediaBox)
    }
    if !plan.cameraTrack.isEmpty {
      drawReportLine("Camera cuts: \(plan.cameraTrack.keyframes.count)", y: plan.isPreviewSample ? 510 : 530, size: 12, context: context, mediaBox: mediaBox)
    }
    if plan.partialClipCount > 0 {
      drawReportLine("Partial spans: \(plan.partialClipCount)", y: 490, size: 12, context: context, mediaBox: mediaBox)
    }
    context.endPDFPage()
    context.closePDF()
  }

  private func drawReportLine(
    _ text: String,
    y: CGFloat,
    size: CGFloat,
    context: CGContext,
    mediaBox: CGRect
  ) {
    let rect = CGRect(x: 54, y: y, width: mediaBox.width - 108, height: 28)
    ExportOverlayDrawing.drawText(
      text,
      in: rect,
      context: context,
      canvasHeight: mediaBox.height,
      size: size,
      color: CGColor(gray: 0.1, alpha: 1)
    )
  }

  private func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
    let start = ContinuousClock.now
    defer {
      let elapsed = start.duration(to: .now)
      NSLog("[perf] %@ took %@", name, String(describing: elapsed))
    }
    return try work()
  }

  private func finishFailure(error: Error) {
    let category: ExportFailureCategory
    if let exportError = error as? ExportError {
      switch exportError {
      case .preparation:
        category = .preparation
      case .encoding:
        category = .partRender
      case .cancelled:
        category = .cancelled
      }
    } else {
      category = .unknown
    }

    let message = error.localizedDescription
    if category == .cancelled {
      appendLog("Export cancelled: \(message)\n")
    } else {
      appendLog("Export failed: \(message)\n")
    }
    appendStructuredLogEvent(
      category == .cancelled ? "export_cancelled" : "export_failed",
      fields: [
        "category": category.rawValue,
        "message": message
      ]
    )
    debug(category == .cancelled ? "cancelled \(message)" : "failed \(message)", category: "export")
    cleanupPartialOutput(at: activeSession?.outputURL)
    updateSession {
      $0.phase = category == .cancelled ? .cancelled : .failed
      $0.phaseLabel = category == .cancelled ? "Export cancelled" : "Export failed"
      $0.finishedAt = Date()
      $0.failureCategory = category
      $0.failureReason = message
      $0.isTerminal = true
      $0.canRetry = true
      $0.canRevealWorkingFiles = true
      $0.isIndeterminate = false
      $0.isCancelled = category == .cancelled
    }
    lastError = category == .cancelled ? "" : message
    endOutputScope()
    publishCurrentSession()
    isStatusPresented = true
    startNextQueuedExportIfIdle()
  }

  private func startNextQueuedExportIfIdle() {
    guard !isExporting, !queuedRequests.isEmpty else { return }
    let next = queuedRequests.removeFirst()
    export(request: next)
  }

  private func updateSession(_ update: (inout MutableExportSession) -> Void) {
    guard var session = activeSession else { return }
    let previousPhase = session.phase
    update(&session)
    activeSession = session
    if session.phase != previousPhase {
      appendStructuredLogEvent(
        "phase_changed",
        fields: [
          "from": previousPhase.rawValue,
          "to": session.phase.rawValue
        ]
      )
      debug("phase \(previousPhase.rawValue) -> \(session.phase.rawValue)", category: "export")
    }
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
    }
  }

  private func beginOutputScope(for outputURL: URL) {
    endOutputScope()
    if outputURL.startAccessingSecurityScopedResource() {
      activeOutputScopeURL = outputURL
      return
    }
    let parent = outputURL.deletingLastPathComponent()
    if parent.startAccessingSecurityScopedResource() {
      activeOutputScopeURL = parent
    }
  }

  private func endOutputScope() {
    activeOutputScopeURL?.stopAccessingSecurityScopedResource()
    activeOutputScopeURL = nil
  }

  private func cleanupStaleTempDirectories(now: Date = Date()) {
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    guard let entries = try? fm.contentsOfDirectory(
      at: tempRoot,
      includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
    ) else { return }

    for entry in entries where entry.lastPathComponent.hasPrefix("teslacam_export_") {
      let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
      guard values?.isDirectory == true else { continue }
      let modified = values?.contentModificationDate ?? .distantPast
      if now.timeIntervalSince(modified) > Self.staleWorkdirAge {
        try? fm.removeItem(at: entry)
      }
    }
  }

  private func appendStructuredLogEvent(_ name: String, fields: [String: String] = [:]) {
    var payload = fields
    payload["event"] = name
    payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) {
      appendLog("event: \(line)\n")
    } else {
      appendLog("event: \(name)\n")
    }
  }

  private func appendLog(_ text: String) {
    appendLogToFile(text)
    if Thread.isMainThread {
      appendLogInMemory(text)
    } else {
      runOnMain { self.appendLogInMemory(text) }
    }
  }

  private func appendLogInMemory(_ text: String) {
    let maxLen = 60000
    log.append(text)
    if log.count > maxLen {
      log = String(log.suffix(maxLen))
    }
  }

  private func resetLogFile() {
    if fm.fileExists(atPath: logFileURL.path) {
      try? fm.removeItem(at: logFileURL)
    }
    fm.createFile(atPath: logFileURL.path, contents: nil)
  }

  private func appendLogToFile(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: logFileURL) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      fm.createFile(atPath: logFileURL.path, contents: data)
    }
  }

  private func renderProgress(completed: Double, total: Double) -> Double {
    guard total > 0 else { return 0.10 }
    let clamped = min(max(completed / total, 0), 1)
    return 0.10 + (0.80 * clamped)
  }

  private func cleanupPartialOutput(at url: URL?) {
    guard let url, fm.fileExists(atPath: url.path) else { return }
    try? fm.removeItem(at: url)
  }

  private func runOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      let runLoop = CFRunLoopGetMain()
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
      CFRunLoopWakeUp(runLoop)
    }
  }

  private func debug(_ message: String, category: String) {
    debugLog?.record(message, category: category)
  }
}

private struct TimelineFrameContext {
  let clipIndex: Int?
  let set: ClipSet?
  let localSeconds: Double
  let sourceSecondsFromTrimStart: Double
}

private struct TimelineFrameSegment {
  let clipIndex: Int
  let set: ClipSet
  let sourceStartSeconds: Double
  let renderStartSeconds: Double
  let duration: Double

  var renderEndSeconds: Double {
    renderStartSeconds + duration
  }
}

private struct NativeFilterGraphSummary {
  let steps: [String]

  init(plan: ExportPlan) {
    var steps = [
      "read",
      "scale",
      plan.cameraTrack.isEmpty ? "stack" : "camera-cut",
      "overlay"
    ]
    if plan.overlayOptions.needsTelemetry {
      steps.append("telemetry")
    }
    steps.append(plan.preset.defaultExtension == "mov" ? "prores" : "hevc")
    self.steps = steps
  }

  var description: String {
    steps.joined(separator: " -> ")
  }
}

private struct TimelineFrameProvider {
  let sets: [ClipSet]
  let trimStartDate: Date
  let trimEndDate: Date
  let totalDuration: Double

  private let segments: [TimelineFrameSegment]
  private let segmentStartSeconds: [Double]
  private let segmentEndSeconds: [Double]

  init(sets: [ClipSet], trimStartDate: Date, trimEndDate: Date) {
    self.sets = sets.sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.timestamp < rhs.timestamp
      }
      return lhs.date < rhs.date
    }
    self.trimStartDate = trimStartDate
    self.trimEndDate = max(trimEndDate, trimStartDate.addingTimeInterval(1.0 / 30.0))
    self.segments = Self.segments(
      for: self.sets,
      trimStartDate: self.trimStartDate,
      trimEndDate: self.trimEndDate
    )
    self.segmentStartSeconds = self.segments.map(\.renderStartSeconds)
    self.segmentEndSeconds = self.segments.map(\.renderEndSeconds)
    self.totalDuration = max(1.0 / 30.0, self.segments.last?.renderEndSeconds ?? 0)
  }

  static func renderDuration(sets: [ClipSet], trimStartDate: Date, trimEndDate: Date) -> Double {
    let orderedSets = sets.sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.timestamp < rhs.timestamp
      }
      return lhs.date < rhs.date
    }
    let endDate = max(trimEndDate, trimStartDate.addingTimeInterval(1.0 / 30.0))
    let segments = Self.segments(for: orderedSets, trimStartDate: trimStartDate, trimEndDate: endDate)
    return max(1.0 / 30.0, segments.last?.renderEndSeconds ?? 0)
  }

  private static func segments(
    for sets: [ClipSet],
    trimStartDate: Date,
    trimEndDate: Date
  ) -> [TimelineFrameSegment] {
    var renderStartSeconds = 0.0
    var segments: [TimelineFrameSegment] = []
    segments.reserveCapacity(sets.count)

    for (index, set) in sets.enumerated() {
      let clipStartDate = set.date
      let clipEndDate = set.date.addingTimeInterval(max(1.0 / 30.0, set.duration))
      let segmentStartDate = max(clipStartDate, trimStartDate)
      let segmentEndDate = min(clipEndDate, trimEndDate)
      let duration = segmentEndDate.timeIntervalSince(segmentStartDate)
      guard duration > 0 else { continue }

      segments.append(
        TimelineFrameSegment(
          clipIndex: index,
          set: set,
          sourceStartSeconds: segmentStartDate.timeIntervalSince(clipStartDate),
          renderStartSeconds: renderStartSeconds,
          duration: duration
        )
      )
      renderStartSeconds += duration
    }

    return segments
  }

  func context(for renderSeconds: Double) -> TimelineFrameContext {
    guard !segments.isEmpty else {
      return TimelineFrameContext(clipIndex: nil, set: nil, localSeconds: 0, sourceSecondsFromTrimStart: 0)
    }

    let clamped = max(0, min(renderSeconds, totalDuration))
    if clamped >= totalDuration, let segment = segments.last {
      return TimelineFrameContext(
        clipIndex: segment.clipIndex,
        set: segment.set,
        localSeconds: segment.sourceStartSeconds + segment.duration,
        sourceSecondsFromTrimStart: segment.set.date
          .addingTimeInterval(segment.sourceStartSeconds + segment.duration)
          .timeIntervalSince(trimStartDate)
      )
    }

    let index = max(0, min(segments.count - 1, upperBound(in: segmentStartSeconds, for: clamped) - 1))
    let segment = segments[index]
    let localSeconds = segment.sourceStartSeconds + clamped - segment.renderStartSeconds
    return TimelineFrameContext(
      clipIndex: segment.clipIndex,
      set: segment.set,
      localSeconds: localSeconds,
      sourceSecondsFromTrimStart: segment.set.date
        .addingTimeInterval(localSeconds)
        .timeIntervalSince(trimStartDate)
    )

  }

  func completedSetCount(at renderSeconds: Double) -> Int {
    let clamped = max(0, min(renderSeconds, totalDuration))
    return upperBound(in: segmentEndSeconds, for: clamped)
  }

  private func upperBound(in values: [Double], for target: Double) -> Int {
    var low = 0
    var high = values.count
    while low < high {
      let mid = (low + high) / 2
      if values[mid] <= target {
        low = mid + 1
      } else {
        high = mid
      }
    }
    return low
  }
}

private struct TimelineFrameLayout {
  let cameraOrder: [Camera]
  let canvasSize: CGSize
  let tileSize: CGSize
  let boundsByCamera: [Camera: CGRect]

  static func build(
    sets: [ClipSet],
    enabledCameras: Set<Camera>,
    useSixCam: Bool,
    layoutRequest: CameraLayoutRequest = .auto
  ) throws -> TimelineFrameLayout {
    let present = Set(sets.flatMap { $0.files.keys })
    let probe = TimelineFrameSizeProbe(sets: sets)
    let requestedProfile: CameraLayoutRequest
    if layoutRequest == .auto {
      requestedProfile = useSixCam ? .sixcam : .auto
    } else {
      requestedProfile = layoutRequest
    }
    let plan = CameraLayoutPlan.build(
      requestedProfile: requestedProfile,
      detectedCameras: present,
      enabledCameras: enabledCameras,
      naturalSizes: probe.naturalSizes(for: Camera.mixedOrder)
    )

    var bounds: [Camera: CGRect] = [:]
    for camera in plan.renderOrder {
      guard let cell = plan.cellByCamera[camera] else { continue }
      bounds[camera] = CGRect(
        x: cell.minX,
        y: plan.canvasSize.height - cell.maxY,
        width: cell.width,
        height: cell.height
      )
    }

    return TimelineFrameLayout(
      cameraOrder: plan.renderOrder,
      canvasSize: plan.canvasSize,
      tileSize: probe.tileSize(for: plan.renderOrder),
      boundsByCamera: bounds
    )
  }
}

private struct TimelineFrameSizeProbe {
  let sets: [ClipSet]

  func tileSize(for cameras: [Camera]) -> CGSize {
    var maxWidth: CGFloat = 1
    var maxHeight: CGFloat = 1
    var foundVideo = false

    for set in sets {
      for camera in cameras {
        if let naturalSize = set.naturalSize(for: camera), naturalSize.width > 0, naturalSize.height > 0 {
          maxWidth = max(maxWidth, naturalSize.width)
          maxHeight = max(maxHeight, naturalSize.height)
          foundVideo = true
          continue
        }

        guard let url = set.file(for: camera) else { continue }
        let asset = AVURLAsset(
          url: url,
          options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        guard let size = AssetVideoTrackLoader.presentationSize(for: asset) else { continue }
        maxWidth = max(maxWidth, size.width)
        maxHeight = max(maxHeight, size.height)
        foundVideo = true
      }
    }

    if !foundVideo {
      return CGSize(width: 320, height: 240)
    }

    let fallbackWidth = max(maxWidth, 1280)
    let fallbackHeight = max(maxHeight, 960)
    return CGSize(width: fallbackWidth, height: fallbackHeight)
  }

  func naturalSizes(for cameras: [Camera]) -> [Camera: CGSize] {
    var sizes: [Camera: CGSize] = [:]
    for set in sets {
      for camera in cameras where sizes[camera] == nil {
        if let naturalSize = set.naturalSize(for: camera), naturalSize.width > 0, naturalSize.height > 0 {
          sizes[camera] = naturalSize
        }
      }
    }
    return sizes
  }
}

private enum AssetVideoTrackLoader {
  static nonisolated func presentationSize(for asset: AVURLAsset) -> CGSize? {
    let semaphore = DispatchSemaphore(value: 0)
    var loadedSize: CGSize?

    Task.detached(priority: .userInitiated) {
      defer { semaphore.signal() }
      do {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
          loadedSize = nil
          return
        }
        async let naturalSize = track.load(.naturalSize)
        async let preferredTransform = track.load(.preferredTransform)
        let transformed = try await naturalSize.applying(preferredTransform)
        loadedSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
      } catch {
        loadedSize = nil
      }
    }

    semaphore.wait()
    return loadedSize
  }
}

private final class ExportImageResultBox: @unchecked Sendable {
  nonisolated(unsafe) var image: CGImage?
}

private actor ExportPreviewImageGeneratorBox {
  private let generator: AVAssetImageGenerator

  init(asset: AVAsset, tolerance: CMTime) {
    generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
  }

  func image(at time: CMTime) async -> CGImage? {
    try? await generator.image(at: time).image
  }
}

private struct FrameImageRequest {
  let camera: Camera
  let url: URL
  let seconds: Double
  let rect: CGRect
}

private final class TimelineFrameComposer {
  let layout: TimelineFrameLayout
  let enabledCameras: Set<Camera>
  let overlayOptions: ExportOverlayOptions
  private var generators: [URL: ExportPreviewImageGeneratorBox] = [:]
  private var lastImages: [URL: CGImage] = [:]
  private var telemetryCache: [URL: TelemetryTimeline] = [:]
  private var telemetryFailures = Set<URL>()
  private var routeCache: [URL: [TelemetryRoutePoint]] = [:]
  private let pixelBufferPool: CVPixelBufferPool?

  init(layout: TimelineFrameLayout, enabledCameras: Set<Camera>, overlayOptions: ExportOverlayOptions = ExportOverlayOptions()) {
    self.layout = layout
    self.enabledCameras = enabledCameras
    self.overlayOptions = overlayOptions
    let width = Int(layout.canvasSize.width.rounded(.up))
    let height = Int(layout.canvasSize.height.rounded(.up))
    let poolAttributes: [String: Any] = [
      kCVPixelBufferPoolMinimumBufferCountKey as String: 8
    ]
    let pixelAttributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height
    ]
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(
      kCFAllocatorDefault,
      poolAttributes as CFDictionary,
      pixelAttributes as CFDictionary,
      &pool
    )
    pixelBufferPool = pool
  }

  func makeFrameBuffer(at localSeconds: Double, set: ClipSet?, cameraOverride: Camera? = nil) throws -> CVPixelBuffer {
    let width = Int(layout.canvasSize.width.rounded(.up))
    let height = Int(layout.canvasSize.height.rounded(.up))
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
    ]
    var buffer: CVPixelBuffer?
    let status: CVReturn
    if let pixelBufferPool {
      status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &buffer)
    } else {
      status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
    }
    guard status == kCVReturnSuccess, let buffer else {
      throw NSError(domain: "TeslaCam", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate frame buffer."])
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
      throw NSError(domain: "TeslaCam", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to access frame buffer."])
    }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw NSError(domain: "TeslaCam", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create color space."])
    }
    guard let context = CGContext(
      data: baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      throw NSError(domain: "TeslaCam", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create drawing context."])
    }

    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(origin: .zero, size: layout.canvasSize))

    guard let set else {
      return buffer
    }

    let focusRect = CGRect(origin: .zero, size: layout.canvasSize)
    let drawFocusCamera = cameraOverride.flatMap { camera in
      enabledCameras.contains(camera) && set.file(for: camera) != nil ? camera : nil
    }

    let imageRequests: [FrameImageRequest]
    if let camera = drawFocusCamera, let url = set.file(for: camera) {
      if let duration = set.duration(for: camera), localSeconds > duration + (1.0 / 30.0) {
        return buffer
      }
      imageRequests = [FrameImageRequest(camera: camera, url: url, seconds: localSeconds, rect: focusRect)]
    } else {
      var requests: [FrameImageRequest] = []
      requests.reserveCapacity(layout.cameraOrder.count)
      for camera in layout.cameraOrder {
        guard enabledCameras.contains(camera),
              let rect = layout.boundsByCamera[camera],
              let url = set.file(for: camera) else {
          continue
        }
        if let duration = set.duration(for: camera), localSeconds > duration + (1.0 / 30.0) {
          continue
        }
        requests.append(FrameImageRequest(camera: camera, url: url, seconds: localSeconds, rect: rect))
      }
      imageRequests = requests
    }

    let images = images(for: imageRequests)
    for request in imageRequests {
      guard let image = images[request.camera] else { continue }
      let fitted = AVMakeRect(aspectRatio: CGSize(width: image.width, height: image.height), insideRect: request.rect)
      context.draw(image, in: fitted)
    }

    if overlayOptions.privacyMask {
      ExportOverlayDrawing.drawPrivacyMask(
        context: context,
        canvasSize: layout.canvasSize,
        tileRects: drawFocusCamera == nil ? layout.boundsByCamera.values.map { $0 } : [focusRect]
      )
    }

    if overlayOptions.needsTelemetry {
      let telemetryURL = telemetrySourceURL(for: set)
      let timeline = telemetryURL.flatMap { telemetryTimeline(for: $0) }
      let frame = timeline?.closest(to: max(0, localSeconds) * 1000.0)
      let telemetry = frame.map { TelemetryDisplayModel(sei: $0.sei) }
      let route = telemetryURL.flatMap { routePoints(for: $0, timeline: timeline) } ?? []
      ExportOverlayDrawing.drawTelemetryOverlay(
        options: overlayOptions,
        telemetry: telemetry,
        route: route,
        timestamp: set.date.addingTimeInterval(max(0, localSeconds)),
        localSeconds: localSeconds,
        context: context,
        canvasSize: layout.canvasSize
      )
    }

    return buffer
  }

  private func telemetrySourceURL(for set: ClipSet) -> URL? {
    set.file(for: .front) ?? set.file(for: .back) ?? set.files.values.sorted { $0.path < $1.path }.first
  }

  private func telemetryTimeline(for url: URL) -> TelemetryTimeline? {
    if let cached = telemetryCache[url] {
      return cached
    }
    if telemetryFailures.contains(url) {
      return nil
    }
    do {
      let timeline = try TelemetryParser.parseTimeline(url: url)
      telemetryCache[url] = timeline
      return timeline
    } catch {
      telemetryFailures.insert(url)
      return nil
    }
  }

  private func routePoints(for url: URL, timeline: TelemetryTimeline?) -> [TelemetryRoutePoint] {
    if let cached = routeCache[url] {
      return cached
    }
    guard let timeline else {
      routeCache[url] = []
      return []
    }
    let points = ExportOverlayDrawing.routePoints(from: timeline)
    routeCache[url] = points
    return points
  }

  private func images(for requests: [FrameImageRequest]) -> [Camera: CGImage] {
    guard !requests.isEmpty else { return [:] }
    struct PreparedRequest {
      let request: FrameImageRequest
      let generator: ExportPreviewImageGeneratorBox
      let attempts: [Double]
      let fallback: CGImage?
    }
    let prepared = requests.map { request in
      PreparedRequest(
        request: request,
        generator: generator(for: request.url),
        attempts: [
          max(0, request.seconds),
          max(0, request.seconds - 0.10),
          max(0, request.seconds - 0.25)
        ],
        fallback: lastImages[request.url]
      )
    }

    let group = DispatchGroup()
    let lock = NSLock()
    var results: [Camera: (url: URL, image: CGImage)] = [:]

    for item in prepared {
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        let image = self.image(from: item.generator, attempts: item.attempts) ?? item.fallback
        if let image {
          lock.lock()
          results[item.request.camera] = (item.request.url, image)
          lock.unlock()
        }
        group.leave()
      }
    }
    group.wait()

    for (_, result) in results {
      lastImages[result.url] = result.image
    }
    return results.mapValues(\.image)
  }

  private func image(from generator: ExportPreviewImageGeneratorBox, attempts: [Double]) -> CGImage? {
    for candidate in attempts {
      if let image = waitForImage(from: generator, at: CMTime(seconds: candidate, preferredTimescale: 600)) {
        return image
      }
    }
    return nil
  }

  private func generator(for url: URL) -> ExportPreviewImageGeneratorBox {
    let generator = generators[url] ?? {
      let asset = AVURLAsset(url: url)
      // Tesla clips can fail exact-frame decode; allow nearest-frame lookup.
      let tolerance = CMTime(seconds: 0.15, preferredTimescale: 600)
      let generator = ExportPreviewImageGeneratorBox(asset: asset, tolerance: tolerance)
      generators[url] = generator
      return generator
    }()
    return generator
  }

  private func waitForImage(from generator: ExportPreviewImageGeneratorBox, at time: CMTime) -> CGImage? {
    let semaphore = DispatchSemaphore(value: 0)
    let resultBox = ExportImageResultBox()
    Task.detached(priority: .userInitiated) {
      resultBox.image = await generator.image(at: time)
      semaphore.signal()
    }
    semaphore.wait()
    return resultBox.image
  }
}

private enum ExportOverlayDrawing {
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  static func drawTelemetryOverlay(
    options: ExportOverlayOptions,
    telemetry: TelemetryDisplayModel?,
    route: [TelemetryRoutePoint],
    timestamp: Date,
    localSeconds: Double,
    context: CGContext,
    canvasSize: CGSize
  ) {
    if options.routeMap, !route.isEmpty {
      drawRouteMap(route: route, currentSeconds: localSeconds, context: context, canvasSize: canvasSize)
    }

    guard options.telemetryHUD else { return }
    drawTimestampOverlay(date: timestamp, context: context, canvasSize: canvasSize)

    let panelHeight: CGFloat = options.telemetryHUDMode == .minimal ? 92 : 174
    let panel = CGRect(x: 26, y: 26, width: min(560, canvasSize.width * 0.36), height: panelHeight)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.58))
    context.fill(panel)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.stroke(panel, width: 1)

    let lines: [String]
    if let telemetry {
      switch options.telemetryHUDMode {
      case .minimal:
        lines = [
          "\(telemetry.speedText(unit: options.speedUnit))   Gear \(telemetry.gear)",
          "AP \(telemetry.autopilot)   Brake \(telemetry.brakeApplied ? "On" : "Off")"
        ]
      case .detailed:
        lines = [
          "Speed  \(telemetry.speedText(unit: options.speedUnit))",
          "Pedal  \(telemetry.acceleratorText)    Brake  \(telemetry.brakeApplied ? "On" : "Off")",
          "Steer  \(telemetry.steeringText)    Gear  \(telemetry.gear)",
          "AP     \(telemetry.autopilot)",
          "Head   \(telemetry.headingText)"
        ]
      }
    } else {
      lines = [
        "No Tesla telemetry",
        "Speed/AP unavailable for this clip"
      ]
    }
    for (index, line) in lines.enumerated() {
      drawText(
        line,
        in: CGRect(x: panel.minX + 18, y: panel.minY + 18 + CGFloat(index * 28), width: panel.width - 36, height: 24),
        context: context,
        canvasHeight: canvasSize.height,
        size: index == 0 ? 23 : 17,
        color: CGColor(red: 1, green: 1, blue: 1, alpha: index == 0 ? 0.95 : 0.78)
      )
    }
  }

  private static func drawTimestampOverlay(date: Date, context: CGContext, canvasSize: CGSize) {
    let panel = CGRect(x: 26, y: max(26, canvasSize.height - 104), width: min(360, canvasSize.width * 0.30), height: 78)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.58))
    context.fill(panel)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.stroke(panel, width: 1)

    drawText(
      ExportOverlayDrawing.dateFormatter.string(from: date),
      in: CGRect(x: panel.minX + 16, y: panel.minY + 14, width: panel.width - 32, height: 24),
      context: context,
      canvasHeight: canvasSize.height,
      size: 18,
      color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
    )
    drawText(
      ExportOverlayDrawing.timeFormatter.string(from: date),
      in: CGRect(x: panel.minX + 16, y: panel.minY + 42, width: panel.width - 32, height: 24),
      context: context,
      canvasHeight: canvasSize.height,
      size: 19,
      color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.78)
    )
  }

  static func drawPrivacyMask(context: CGContext, canvasSize: CGSize, tileRects: [CGRect]) {
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.76))
    let topBand = CGRect(x: 0, y: canvasSize.height - 96, width: canvasSize.width, height: 96)
    context.fill(topBand)
    for rect in tileRects {
      let bandHeight = max(54, rect.height * 0.16)
      context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bandHeight))
    }
  }

  static func routePoints(from timeline: TelemetryTimeline) -> [TelemetryRoutePoint] {
    var points: [TelemetryRoutePoint] = []
    points.reserveCapacity(min(240, timeline.frames.count))
    var lastWholeSecond = -1
    var lastCoordinate: TelemetryCoordinate?
    for frame in timeline.frames {
      let seconds = Int((frame.timestampMs / 1000.0).rounded(.down))
      guard seconds != lastWholeSecond else { continue }
      lastWholeSecond = seconds
      let coordinate = TelemetryCoordinate(latitude: frame.sei.latitudeDeg, longitude: frame.sei.longitudeDeg)
      guard coordinate.isUsable, coordinate != lastCoordinate else { continue }
      lastCoordinate = coordinate
      points.append(
        TelemetryRoutePoint(
          id: points.count,
          seconds: frame.timestampMs / 1000.0,
          coordinate: coordinate,
          speedKmh: Double(frame.sei.vehicleSpeedMps) * 3.6,
          headingDeg: frame.sei.headingDeg
        )
      )
    }
    return points
  }

  private static func drawRouteMap(
    route: [TelemetryRoutePoint],
    currentSeconds: Double,
    context: CGContext,
    canvasSize: CGSize
  ) {
    let displayRoute = TelemetryRouteReplay.displaySamples(from: route, maxPoints: 900)
    let side = min(310, min(canvasSize.width, canvasSize.height) * 0.28)
    let panel = CGRect(x: canvasSize.width - side - 26, y: 26, width: side, height: side)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.58))
    context.fill(panel)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    context.stroke(panel, width: 1)

    let points = displayRoute.map(\.coordinate)
    let latitudes = points.map(\.latitude)
    let longitudes = points.map(\.longitude)
    guard let minLat = latitudes.min(),
          let maxLat = latitudes.max(),
          let minLon = longitudes.min(),
          let maxLon = longitudes.max() else { return }

    let latSpan = max(0.00001, maxLat - minLat)
    let lonSpan = max(0.00001, maxLon - minLon)
    let inset: CGFloat = 22
    let drawRect = panel.insetBy(dx: inset, dy: inset)
    func point(for coordinate: TelemetryCoordinate) -> CGPoint {
      let x = drawRect.minX + CGFloat((coordinate.longitude - minLon) / lonSpan) * drawRect.width
      let y = drawRect.minY + CGFloat((coordinate.latitude - minLat) / latSpan) * drawRect.height
      return CGPoint(x: x, y: y)
    }

    let path = CGMutablePath()
    for (index, item) in displayRoute.enumerated() {
      let p = point(for: item.coordinate)
      if index == 0 {
        path.move(to: p)
      } else {
        path.addLine(to: p)
      }
    }
    context.setStrokeColor(CGColor(red: 0.22, green: 0.58, blue: 1, alpha: 0.95))
    context.setLineWidth(max(3, CGFloat(TelemetryRouteStyle.lineWidth(latitudeDelta: latSpan, longitudeDelta: lonSpan))))
    context.addPath(path)
    context.strokePath()

    let current = TelemetryRouteReplay(route: route).frame(at: currentSeconds)
    let p = point(for: current.coordinate)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    context.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
  }

  static func drawText(
    _ text: String,
    in rect: CGRect,
    context: CGContext,
    canvasHeight: CGFloat,
    size: CGFloat,
    color: CGColor
  ) {
    context.saveGState()
    context.textMatrix = .identity
    context.translateBy(x: 0, y: canvasHeight)
    context.scaleBy(x: 1, y: -1)
    let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
    let attributed = NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: color
      ]
    )
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
    CTFrameDraw(frame, context)
    context.restoreGState()
  }
}

private final class NativeMovieWriter {
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor

  init(outputURL: URL, size: CGSize, preset: ExportPreset) throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    writer = try AVAssetWriter(outputURL: outputURL, fileType: preset.defaultExtension == "mov" ? .mov : .mp4)

    let codec: AVVideoCodecType
    let compression: [String: Any]
    switch preset {
    case .editFriendlyProRes:
      codec = .proRes422HQ
      compression = preset.nativeCompressionProperties(for: size)
    case .maxQualityHEVC, .fastHEVC, .socialShareHEVC, .proxyHEVC:
      codec = .hevc
      compression = preset.nativeCompressionProperties(for: size)
    }

    var settings: [String: Any] = [
      AVVideoCodecKey: codec.rawValue,
      AVVideoWidthKey: Int(size.width.rounded(.up)),
      AVVideoHeightKey: Int(size.height.rounded(.up))
    ]
    if !compression.isEmpty {
      settings[AVVideoCompressionPropertiesKey] = compression
    }

    input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false

    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: Int(size.width.rounded(.up)),
        kCVPixelBufferHeightKey as String: Int(size.height.rounded(.up))
      ]
    )

    guard writer.canAdd(input) else {
      throw NSError(domain: "TeslaCam", code: 5, userInfo: [NSLocalizedDescriptionKey: "Writer cannot accept video input."])
    }
    writer.add(input)
  }

  func start() throws {
    guard writer.startWriting() else {
      throw NSError(domain: "TeslaCam", code: 6, userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "Failed to start writer."])
    }
    writer.startSession(atSourceTime: .zero)
  }

  func append(buffer: CVPixelBuffer, at time: CMTime) throws {
    while !input.isReadyForMoreMediaData {
      Thread.sleep(forTimeInterval: 0.005)
    }
    guard adaptor.append(buffer, withPresentationTime: time) else {
      throw NSError(domain: "TeslaCam", code: 7, userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "Failed to append frame."])
    }
  }

  func finishWriting() throws {
    input.markAsFinished()
    let group = DispatchGroup()
    group.enter()
    var finishError: Error?
    writer.finishWriting {
      finishError = self.writer.error
      group.leave()
    }
    group.wait()
    if let finishError {
      throw finishError
    }
  }
}
