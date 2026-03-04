import Foundation

enum ClipIndexError: Error {
  case noClipsFound
}

final class ClipIndexer {
  private static let regex: NSRegularExpression = {
    // Accept broad camera tokens and normalize them in code to avoid dropping clips
    // from slightly different Tesla naming variants.
    let pattern = "^(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2})-([A-Za-z0-9_-]+)\\.(mp4|mov)$"
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
    try index(inputURLs: [rootURL], progress: progress)
  }

  static func index(inputURLs: [URL], progress: @escaping (Int) -> Void) throws -> ClipIndex {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .nameKey, .isHiddenKey]

    var map: [String: (date: Date, files: [Camera: URL])] = [:]
    var camerasFound = Set<Camera>()
    var scanned = 0

    let normalizedInputs = normalizeInputs(inputURLs)
    guard !normalizedInputs.isEmpty else {
      throw ClipIndexError.noClipsFound
    }

    for input in normalizedInputs {
      let values = try? input.resourceValues(forKeys: Set(keys))
      let isDir = values?.isDirectory ?? false

      if isDir {
        guard let enumerator = fm.enumerator(
          at: input,
          includingPropertiesForKeys: keys,
          options: [.skipsHiddenFiles]
        ) else {
          continue
        }
        for case let fileURL as URL in enumerator {
          parseClipFile(fileURL, into: &map, camerasFound: &camerasFound, scanned: &scanned, progress: progress)
        }
      } else {
        parseClipFile(input, into: &map, camerasFound: &camerasFound, scanned: &scanned, progress: progress)
      }
    }

    var sets: [ClipSet] = []
    sets.reserveCapacity(map.count)
    for (ts, entry) in map {
      // Default duration to 60s to avoid heavy scanning during index
      sets.append(ClipSet(timestamp: ts, date: entry.date, duration: 60.0, files: entry.files))
    }
    sets.sort {
      if $0.date == $1.date {
        return $0.timestamp < $1.timestamp
      }
      return $0.date < $1.date
    }

    guard let first = sets.first, let last = sets.last else {
      throw ClipIndexError.noClipsFound
    }

    return ClipIndex(sets: sets, minDate: first.date, maxDate: last.date, camerasFound: camerasFound)
  }

  private static func normalizeInputs(_ inputs: [URL]) -> [URL] {
    var seen = Set<String>()
    var out: [URL] = []
    out.reserveCapacity(inputs.count)
    for raw in inputs {
      let url = raw.standardizedFileURL
      let key = url.path
      if seen.contains(key) { continue }
      seen.insert(key)
      out.append(url)
    }
    return out
  }

  private static func parseClipFile(
    _ fileURL: URL,
    into map: inout [String: (date: Date, files: [Camera: URL])],
    camerasFound: inout Set<Camera>,
    scanned: inout Int,
    progress: (Int) -> Void
  ) {
    let ext = fileURL.pathExtension.lowercased()
    if ext != "mp4" && ext != "mov" { return }

    let name = fileURL.lastPathComponent
    guard let match = firstMatch(in: name) else { return }
    let timestamp = match.timestamp
    guard let date = dateFormatter.date(from: timestamp) else { return }
    let camera = match.camera

    var entry = map[timestamp] ?? (date: date, files: [:])
    if let existing = entry.files[camera] {
      if fileURL.path < existing.path {
        entry.files[camera] = fileURL
      }
    } else {
      entry.files[camera] = fileURL
    }
    map[timestamp] = entry
    camerasFound.insert(camera)

    scanned += 1
    if scanned % 500 == 0 { progress(scanned) }
  }

  private static func firstMatch(in filename: String) -> (timestamp: String, camera: Camera)? {
    let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
    guard let m = regex.firstMatch(in: filename, options: [], range: range) else { return nil }
    guard let tsRange = Range(m.range(at: 1), in: filename) else { return nil }
    guard let camRange = Range(m.range(at: 2), in: filename) else { return nil }
    let timestamp = String(filename[tsRange])
    let rawCamera = String(filename[camRange])
    guard let camera = normalizeCamera(rawCamera) else { return nil }
    return (timestamp, camera)
  }

  private static func normalizeCamera(_ raw: String) -> Camera? {
    var token = raw.lowercased().replacingOccurrences(of: "-", with: "_")
    token = token.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
    token = token.replacingOccurrences(of: "_?\\d+$", with: "", options: .regularExpression)

    if token == "front" || token == "fwd" || token == "forward" {
      return .front
    }
    if token == "back" || token == "rear" {
      return .back
    }
    if token.contains("left") && token.contains("pillar") {
      return .left_pillar
    }
    if token.contains("right") && token.contains("pillar") {
      return .right_pillar
    }
    if (token.contains("left") && token.contains("repeat")) || token == "left" || token == "left_rear" {
      return .left_repeater
    }
    if (token.contains("right") && token.contains("repeat")) || token == "right" || token == "right_rear" {
      return .right_repeater
    }

    if token == "rear_camera" {
      return .back
    }

    return Camera(rawValue: token)
  }
}
