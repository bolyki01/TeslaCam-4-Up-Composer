import Foundation

enum ClipIndexError: Error {
  case noClipsFound
}

final class ClipIndexer {
  private static let regex: NSRegularExpression = {
    let pattern = "^(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2})-(front|back|left_repeater|right_repeater|left_pillar|right_pillar|rear)\\.(mp4|mov)$"
    return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  }()

  private static let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone.current
    df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    return df
  }()

  static func index(rootURL: URL, progress: @escaping (Int) -> Void) throws -> ClipIndex {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey, .isHiddenKey]
    guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
      throw ClipIndexError.noClipsFound
    }

    var map: [String: (date: Date, files: [Camera: URL])] = [:]
    var camerasFound = Set<Camera>()
    var scanned = 0

    for case let fileURL as URL in enumerator {
      let ext = fileURL.pathExtension.lowercased()
      if ext != "mp4" && ext != "mov" { continue }

      let name = fileURL.lastPathComponent
      guard let match = firstMatch(in: name) else { continue }
      let timestamp = match.timestamp
      guard let date = dateFormatter.date(from: timestamp) else { continue }
      let camera = match.camera

      var entry = map[timestamp] ?? (date: date, files: [:])
      entry.files[camera] = fileURL
      map[timestamp] = entry
      camerasFound.insert(camera)

      scanned += 1
      if scanned % 500 == 0 { progress(scanned) }
    }

    var sets: [ClipSet] = []
    sets.reserveCapacity(map.count)
    for (ts, entry) in map {
      // Default duration to 60s to avoid heavy scanning during index
      sets.append(ClipSet(timestamp: ts, date: entry.date, duration: 60.0, files: entry.files))
    }
    sets.sort { $0.date < $1.date }

    guard let first = sets.first, let last = sets.last else {
      throw ClipIndexError.noClipsFound
    }

    return ClipIndex(sets: sets, minDate: first.date, maxDate: last.date, camerasFound: camerasFound)
  }

  private static func firstMatch(in filename: String) -> (timestamp: String, camera: Camera)? {
    let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
    guard let m = regex.firstMatch(in: filename, options: [], range: range) else { return nil }
    guard let tsRange = Range(m.range(at: 1), in: filename) else { return nil }
    guard let camRange = Range(m.range(at: 2), in: filename) else { return nil }
    let timestamp = String(filename[tsRange])
    var cam = String(filename[camRange]).lowercased()
    if cam == "rear" { cam = "back" }
    guard let camera = Camera(rawValue: cam) else { return nil }
    return (timestamp, camera)
  }
}
