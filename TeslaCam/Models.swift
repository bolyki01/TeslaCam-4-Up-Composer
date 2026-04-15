import Foundation
import CoreGraphics
import Combine
import OSLog
import AVFoundation

enum Camera: String, CaseIterable, Hashable {
  case front
  case back
  case left_repeater
  case right_repeater
  case left
  case right
  case left_pillar
  case right_pillar

  static let hw3ClassicOrder: [Camera] = [
    .front,
    .back,
    .left_repeater,
    .right_repeater
  ]

  static let hw4SixCamOrder: [Camera] = [
    .front,
    .back,
    .left,
    .right,
    .left_pillar,
    .right_pillar
  ]

  static let mixedOrder: [Camera] = [
    .front,
    .back,
    .left_repeater,
    .right_repeater,
    .left,
    .right,
    .left_pillar,
    .right_pillar
  ]

  var displayName: String {
    switch self {
    case .front: return "Front"
    case .back: return "Back"
    case .left_repeater: return "Left Repeater"
    case .right_repeater: return "Right Repeater"
    case .left: return "Left"
    case .right: return "Right"
    case .left_pillar: return "Left Pillar"
    case .right_pillar: return "Right Pillar"
    }
  }
}

enum CameraLayoutProfile: String, CaseIterable, Identifiable {
  case hw3FourCam
  case hw4SixCam
  case mixedUnknown

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .hw3FourCam:
      return "HW3 4-Camera"
    case .hw4SixCam:
      return "HW4 6-Camera"
    case .mixedUnknown:
      return "Mixed / Unknown"
    }
  }

  var orderedCameras: [Camera] {
    switch self {
    case .hw3FourCam:
      return Camera.hw3ClassicOrder
    case .hw4SixCam:
      return Camera.hw4SixCamOrder
    case .mixedUnknown:
      return Camera.mixedOrder
    }
  }
}

enum ExportPreset: String, CaseIterable, Identifiable {
  case maxQualityHEVC
  case fastHEVC
  case editFriendlyProRes

  private static let referenceCanvasPixels = 1_920.0 * 1_080.0
  private static let defaultFrameRate = 30.0

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .maxQualityHEVC:
      return "Max Quality HEVC"
    case .fastHEVC:
      return "Fast HEVC"
    case .editFriendlyProRes:
      return "Edit-Friendly ProRes"
    }
  }

  var scriptPreset: String {
    switch self {
    case .maxQualityHEVC:
      return "HEVC_CPU_MAX"
    case .fastHEVC:
      return "HEVC_MAX"
    case .editFriendlyProRes:
      return "PRORES_HQ"
    }
  }

  var defaultExtension: String {
    switch self {
    case .editFriendlyProRes:
      return "mov"
    case .maxQualityHEVC, .fastHEVC:
      return "mp4"
    }
  }

  var outputLabel: String {
    switch self {
    case .maxQualityHEVC:
      return "hevc_max_quality"
    case .fastHEVC:
      return "hevc_fast"
    case .editFriendlyProRes:
      return "prores_hq"
    }
  }

  func nativeCompressionProperties(for canvasSize: CGSize) -> [String: Any] {
    switch self {
    case .editFriendlyProRes:
      return [:]
    case .maxQualityHEVC:
      return [
        AVVideoAverageBitRateKey: scaledHEVCBitRate(
          for: canvasSize,
          referenceBitRate: 45_000_000,
          scalingExponent: 0.8,
          maximumBitRate: 240_000_000
        ),
        AVVideoExpectedSourceFrameRateKey: Int(Self.defaultFrameRate),
        AVVideoMaxKeyFrameIntervalKey: Int(Self.defaultFrameRate)
      ]
    case .fastHEVC:
      return [
        AVVideoAverageBitRateKey: scaledHEVCBitRate(
          for: canvasSize,
          referenceBitRate: 20_000_000,
          scalingExponent: 0.78,
          maximumBitRate: 120_000_000
        ),
        AVVideoExpectedSourceFrameRateKey: Int(Self.defaultFrameRate),
        AVVideoMaxKeyFrameIntervalKey: Int(Self.defaultFrameRate)
      ]
    }
  }

  private func scaledHEVCBitRate(
    for canvasSize: CGSize,
    referenceBitRate: Double,
    scalingExponent: Double,
    maximumBitRate: Double
  ) -> Int {
    let width = max(1, Double(canvasSize.width.rounded(.up)))
    let height = max(1, Double(canvasSize.height.rounded(.up)))
    let pixelScale = max(1, (width * height) / Self.referenceCanvasPixels)
    let scaled = referenceBitRate * pow(pixelScale, scalingExponent)
    return Int(min(maximumBitRate, max(referenceBitRate, scaled)).rounded())
  }
}

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
  let trimStartSeconds: Double
  let trimEndSeconds: Double
  let trimStartDate: Date
  let trimEndDate: Date
  let selectedRangeText: String
  let partialClipCount: Int

  var totalParts: Int {
    sets.count
  }

  var totalDuration: Double {
    let dateSpan = trimEndDate.timeIntervalSince(trimStartDate)
    if dateSpan > 0 {
      return dateSpan
    }
    return max(0, trimEndSeconds - trimStartSeconds)
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
  let hasWriteAccess: Bool
  let resolvedOutputURL: URL
  let requiresUserSavePanel: Bool

  var canExport: Bool {
    blockingIssues.isEmpty
  }
}

struct TimelineTrimSelection: Equatable {
  var startSeconds: Double
  var endSeconds: Double
  var isDragging: Bool
}

struct PreviewTimelineState: Equatable {
  var currentGlobalSeconds: Double
  var activeClipSetIndex: Int
  var playing: Bool
}

@MainActor
final class PlaybackUIState: ObservableObject {
  @Published var currentSeconds: Double = 0
  @Published var overlayText: String = ""
  @Published var telemetryText: String = ""
}

struct DebugEvent: Identifiable, Hashable {
  let id = UUID()
  let timestamp: Date
  let category: String
  let message: String
}

final class DebugLogSink: ObservableObject {
  @Published private(set) var events: [DebugEvent] = []

  private let logger = Logger(subsystem: "com.magrathean.TeslaCam", category: "debug")
  private let maxEventCount = 250

  func record(_ message: String, category: String) {
    logger.log("[\(category, privacy: .public)] \(message, privacy: .public)")
#if DEBUG
    events.append(DebugEvent(timestamp: Date(), category: category, message: message))
    if events.count > maxEventCount {
      events.removeFirst(events.count - maxEventCount)
    }
#endif
  }
}

struct TimelineGapRange: Equatable, Hashable {
  let startSeconds: Double
  let endSeconds: Double

  var duration: Double {
    max(0, endSeconds - startSeconds)
  }

  func contains(_ seconds: Double) -> Bool {
    seconds >= startSeconds && seconds < endSeconds
  }

  static func ranges(for sets: [ClipSet], minimumDuration: Double = 1) -> [TimelineGapRange] {
    let ordered = sets.sorted { lhs, rhs in
      if lhs.date == rhs.date {
        return lhs.id < rhs.id
      }
      return lhs.date < rhs.date
    }
    guard let anchor = ordered.first?.date else { return [] }

    var gaps: [TimelineGapRange] = []
    var coveredEnd = ordered[0].endDate

    for set in ordered.dropFirst() {
      let nextStart = set.date
      let uncovered = nextStart.timeIntervalSince(coveredEnd)
      if uncovered > minimumDuration {
        gaps.append(
          TimelineGapRange(
            startSeconds: max(0, coveredEnd.timeIntervalSince(anchor)),
            endSeconds: max(0, nextStart.timeIntervalSince(anchor))
          )
        )
      }
      if set.endDate > coveredEnd {
        coveredEnd = set.endDate
      }
    }

    return gaps
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
  var completedDuration: Double
  var totalDuration: Double
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
    if totalDuration > 0 {
      return "\(formatPlaybackDuration(completedDuration)) / \(formatPlaybackDuration(totalDuration))"
    }
    if totalParts > 0 {
      return "\(completedParts) / \(totalParts) clips"
    }
    return request.selectedRangeText
  }
}

struct MutableExportSession {
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
  var completedDuration: Double
  var totalDuration: Double
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
      completedDuration: completedDuration,
      totalDuration: totalDuration,
      isIndeterminate: isIndeterminate,
      isTerminal: isTerminal,
      canRevealOutput: canRevealOutput && fileManager.fileExists(atPath: outputURL.path),
      canRevealWorkingFiles: canRevealWorkingFiles && tempRootURL != nil,
      canRetry: canRetry,
      isCancelled: isCancelled
    )
  }
}

enum DuplicateClipPolicy: String, CaseIterable, Identifiable {
  case mergeByTime
  case keepAll
  case preferNewest

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .mergeByTime:
      return "Merge by Time"
    case .keepAll:
      return "Keep All"
    case .preferNewest:
      return "Prefer Newest"
    }
  }
}

enum ScanStage: Int, CaseIterable, Identifiable {
  case scanningNestedFolders
  case parsingTimestamps
  case mergingClips
  case preparingTimeline

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .scanningNestedFolders:
      return "Scanning nested folders"
    case .parsingTimestamps:
      return "Parsing timestamps"
    case .mergingClips:
      return "Merging clips by time"
    case .preparingTimeline:
      return "Preparing timeline"
    }
  }
}

struct ClipSet: Identifiable, Hashable {
  let id: String
  let timestamp: String
  let date: Date
  let duration: Double
  var files: [Camera: URL]
  var cameraDurations: [Camera: Double]
  var naturalSizes: [Camera: CGSize]

  init(
    id: String? = nil,
    timestamp: String,
    date: Date,
    duration: Double,
    files: [Camera: URL],
    cameraDurations: [Camera: Double] = [:],
    naturalSizes: [Camera: CGSize] = [:]
  ) {
    self.id = id ?? timestamp
    self.timestamp = timestamp
    self.date = date
    self.duration = duration
    self.files = files
    self.cameraDurations = cameraDurations
    self.naturalSizes = naturalSizes
  }

  init(
    timestamp: String,
    date: Date,
    duration: Double,
    files: [Camera: URL],
    cameraDurations: [Camera: Double] = [:],
    naturalSizes: [Camera: CGSize] = [:]
  ) {
    self.init(
      id: nil,
      timestamp: timestamp,
      date: date,
      duration: duration,
      files: files,
      cameraDurations: cameraDurations,
      naturalSizes: naturalSizes
    )
  }

  func file(for camera: Camera) -> URL? {
    files[camera]
  }

  func duration(for camera: Camera) -> Double? {
    cameraDurations[camera]
  }

  func naturalSize(for camera: Camera) -> CGSize? {
    naturalSizes[camera]
  }

  var endDate: Date {
    date.addingTimeInterval(duration)
  }
}

struct DuplicateResolutionSummary: Hashable {
  let duplicateFileCount: Int
  let duplicateTimestampCount: Int
  let overlapMinuteCount: Int

  var hasConflicts: Bool {
    duplicateFileCount > 0 || overlapMinuteCount > 0
  }
}

struct ClipIndex {
  let sets: [ClipSet]
  let minDate: Date
  let maxDate: Date
  let totalDuration: Double
  let camerasFound: Set<Camera>
  let layoutProfile: CameraLayoutProfile
  let duplicateSummary: DuplicateResolutionSummary

  var duplicateFileCount: Int {
    duplicateSummary.duplicateFileCount
  }
}

struct ExportHealthSummary {
  let totalMinutes: Int
  let gapCount: Int
  let partialSetCount: Int
  let fourCameraSetCount: Int
  let sixCameraSetCount: Int
  let missingCameraCounts: [Camera: Int]

  var hasMixedCoverage: Bool {
    fourCameraSetCount > 0 && sixCameraSetCount > 0
  }

  var missingCoverageSummary: String {
    let ordered = Camera.mixedOrder.compactMap { camera -> String? in
      guard let count = missingCameraCounts[camera], count > 0 else { return nil }
      return "\(camera.displayName): \(count)"
    }
    return ordered.joined(separator: "  ")
  }
}

private func formatPlaybackDuration(_ seconds: Double) -> String {
  let wholeSeconds = max(0, Int(seconds.rounded(.down)))
  let hours = wholeSeconds / 3600
  let minutes = (wholeSeconds % 3600) / 60
  let secs = wholeSeconds % 60
  if hours > 0 {
    return String(format: "%d:%02d:%02d", hours, minutes, secs)
  }
  return String(format: "%d:%02d", minutes, secs)
}
