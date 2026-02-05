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
