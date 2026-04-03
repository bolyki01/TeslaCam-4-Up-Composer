import Foundation

enum Camera: String, CaseIterable, Hashable {
  case front
  case back
  case left_repeater
  case right_repeater
  case left_pillar
  case right_pillar

  var displayName: String {
    switch self {
    case .front: return "Front"
    case .back: return "Back"
    case .left_repeater: return "Left"
    case .right_repeater: return "Right"
    case .left_pillar: return "Left Pillar"
    case .right_pillar: return "Right Pillar"
    }
  }
}

enum ExportPreset: String, CaseIterable, Identifiable {
  case maxQualityHEVC
  case fastHEVC
  case editFriendlyProRes

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
}

struct ClipSet: Identifiable, Hashable {
  let id: String
  let timestamp: String
  let date: Date
  let duration: Double
  var files: [Camera: URL]

  init(timestamp: String, date: Date, duration: Double, files: [Camera: URL]) {
    self.id = timestamp
    self.timestamp = timestamp
    self.date = date
    self.duration = duration
    self.files = files
  }

  func file(for camera: Camera) -> URL? {
    return files[camera]
  }
}

struct ClipIndex {
  let sets: [ClipSet]
  let minDate: Date
  let maxDate: Date
  let camerasFound: Set<Camera>
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
    let ordered = Camera.allCases.compactMap { camera -> String? in
      guard let count = missingCameraCounts[camera], count > 0 else { return nil }
      return "\(camera.displayName): \(count)"
    }
    return ordered.joined(separator: "  ")
  }
}
