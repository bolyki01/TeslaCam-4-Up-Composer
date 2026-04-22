import Foundation
import AVFoundation
import CoreGraphics

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
    try index(inputURLs: [rootURL], duplicatePolicy: .mergeByTime, progress: progress)
  }

  static func index(
    inputURLs: [URL],
    duplicatePolicy: DuplicateClipPolicy = .mergeByTime,
    progress: @escaping (Int) -> Void
  ) throws -> ClipIndex {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .nameKey, .isHiddenKey]

    var map: [String: IndexedClipSetBuilder] = [:]
    var keepAllSets: [ClipSet] = []
    var keepAllPrimaryIndexByTimestamp: [String: Int] = [:]
    var camerasFound = Set<Camera>()
    var duplicateFileCount = 0
    var duplicateTimestampCount = 0
    var scanned = 0
    var seenDuplicateTimestamps = Set<String>()
    var metadataCache: [String: ClipAssetProbe] = [:]

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
        let fileURLs = enumerator.compactMap { item -> URL? in
          guard let fileURL = item as? URL else { return nil }
          return fileURL.standardizedFileURL
        }.sorted { $0.path < $1.path }
        for fileURL in fileURLs {
          parseClipFile(
            fileURL,
            duplicatePolicy: duplicatePolicy,
            into: &map,
            keepAllSets: &keepAllSets,
            keepAllPrimaryIndexByTimestamp: &keepAllPrimaryIndexByTimestamp,
            camerasFound: &camerasFound,
            duplicateFileCount: &duplicateFileCount,
            duplicateTimestampCount: &duplicateTimestampCount,
            seenDuplicateTimestamps: &seenDuplicateTimestamps,
            scanned: &scanned,
            metadataCache: &metadataCache,
            progress: progress
          )
        }
      } else {
        parseClipFile(
          input,
          duplicatePolicy: duplicatePolicy,
          into: &map,
          keepAllSets: &keepAllSets,
          keepAllPrimaryIndexByTimestamp: &keepAllPrimaryIndexByTimestamp,
          camerasFound: &camerasFound,
          duplicateFileCount: &duplicateFileCount,
          duplicateTimestampCount: &duplicateTimestampCount,
          seenDuplicateTimestamps: &seenDuplicateTimestamps,
          scanned: &scanned,
          metadataCache: &metadataCache,
          progress: progress
        )
      }
    }

    var sets: [ClipSet]
    if duplicatePolicy == .keepAll {
      sets = keepAllSets
    } else {
      sets = []
      sets.reserveCapacity(map.count)
      for (_, entry) in map {
        sets.append(entry.makeClipSet())
      }
    }
    sets.sort { lhs, rhs in
      if lhs.date == rhs.date {
        if lhs.timestamp == rhs.timestamp {
          let lhsPaths = lhs.files.values.map(\.path).sorted()
          let rhsPaths = rhs.files.values.map(\.path).sorted()
          if lhsPaths == rhsPaths {
            return lhs.id < rhs.id
          }
          return lhsPaths.lexicographicallyPrecedes(rhsPaths)
        }
        return lhs.timestamp < rhs.timestamp
      }
      return lhs.date < rhs.date
    }

    guard let first = sets.first, let last = sets.last else {
      throw ClipIndexError.noClipsFound
    }

    let maxEnd = sets.map(\.endDate).max() ?? last.endDate
    let totalDuration = max(0.1, maxEnd.timeIntervalSince(first.date))
    let overlapMinuteCount = overlapCount(in: sets)

    return ClipIndex(
      sets: sets,
      minDate: first.date,
      maxDate: maxEnd,
      totalDuration: totalDuration,
      camerasFound: camerasFound,
      layoutProfile: detectLayoutProfile(camerasFound: camerasFound),
      duplicateSummary: DuplicateResolutionSummary(
        duplicateFileCount: duplicateFileCount,
        duplicateTimestampCount: duplicateTimestampCount,
        overlapMinuteCount: overlapMinuteCount
      )
    )
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
    duplicatePolicy: DuplicateClipPolicy,
    into map: inout [String: IndexedClipSetBuilder],
    keepAllSets: inout [ClipSet],
    keepAllPrimaryIndexByTimestamp: inout [String: Int],
    camerasFound: inout Set<Camera>,
    duplicateFileCount: inout Int,
    duplicateTimestampCount: inout Int,
    seenDuplicateTimestamps: inout Set<String>,
    scanned: inout Int,
    metadataCache: inout [String: ClipAssetProbe],
    progress: (Int) -> Void
  ) {
    let fm = FileManager.default
    let ext = fileURL.pathExtension.lowercased()
    if ext != "mp4" && ext != "mov" { return }

    let name = fileURL.lastPathComponent
    guard let match = firstMatch(in: name) else { return }
    let timestamp = match.timestamp
    guard let date = dateFormatter.date(from: timestamp) else { return }
    let camera = match.camera
    let metadata = probeMetadata(for: fileURL, cache: &metadataCache)

    if duplicatePolicy == .keepAll {
      if let primaryIndex = keepAllPrimaryIndexByTimestamp[timestamp] {
        if keepAllSets[primaryIndex].files[camera] == nil {
          var files = keepAllSets[primaryIndex].files
          files[camera] = fileURL
          var durations = keepAllSets[primaryIndex].cameraDurations
          durations[camera] = metadata.duration
          var naturalSizes = keepAllSets[primaryIndex].naturalSizes
          naturalSizes[camera] = metadata.naturalSize
          keepAllSets[primaryIndex] = ClipSet(
            id: keepAllSets[primaryIndex].id,
            timestamp: keepAllSets[primaryIndex].timestamp,
            date: keepAllSets[primaryIndex].date,
            duration: max(keepAllSets[primaryIndex].duration, metadata.duration),
            files: files,
            cameraDurations: durations,
            naturalSizes: naturalSizes
          )
        } else {
          duplicateFileCount += 1
          if seenDuplicateTimestamps.insert(timestamp).inserted {
            duplicateTimestampCount += 1
          }
          let suffix = keepAllSets.filter { $0.timestamp == timestamp }.count + 1
          let duplicateID = "\(timestamp)__dup\(suffix)"
          keepAllSets.append(
            ClipSet(
              id: duplicateID,
              timestamp: timestamp,
              date: date,
              duration: metadata.duration,
              files: [camera: fileURL],
              cameraDurations: [camera: metadata.duration],
              naturalSizes: [camera: metadata.naturalSize]
            )
          )
        }
      } else {
        keepAllPrimaryIndexByTimestamp[timestamp] = keepAllSets.count
        keepAllSets.append(
          ClipSet(
            id: timestamp,
            timestamp: timestamp,
            date: date,
            duration: metadata.duration,
            files: [camera: fileURL],
            cameraDurations: [camera: metadata.duration],
            naturalSizes: [camera: metadata.naturalSize]
          )
        )
      }
      camerasFound.insert(camera)
      scanned += 1
      if scanned % 100 == 0 { progress(scanned) }
      return
    }

    var entry = map[timestamp] ?? IndexedClipSetBuilder(timestamp: timestamp, date: date)
    if let existing = entry.files[camera] {
      duplicateFileCount += 1
      if seenDuplicateTimestamps.insert(timestamp).inserted {
        duplicateTimestampCount += 1
      }
      switch duplicatePolicy {
      case .mergeByTime, .keepAll:
        if fileURL.path < existing.path {
          entry.replace(camera: camera, url: fileURL, metadata: metadata)
        }
      case .preferNewest:
        let existingDate = (try? fm.attributesOfItem(atPath: existing.path)[.modificationDate] as? Date) ?? .distantPast
        let candidateDate = (try? fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? .distantPast
        if candidateDate > existingDate || (candidateDate == existingDate && fileURL.path < existing.path) {
          entry.replace(camera: camera, url: fileURL, metadata: metadata)
        }
      }
    } else {
      entry.insert(camera: camera, url: fileURL, metadata: metadata)
    }
    map[timestamp] = entry
    camerasFound.insert(camera)

    scanned += 1
    if scanned % 100 == 0 { progress(scanned) }
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
    if token == "back" || token == "rear" || token == "rear_camera" {
      return .back
    }
    if token.contains("left") && token.contains("pillar") {
      return .left_pillar
    }
    if token.contains("right") && token.contains("pillar") {
      return .right_pillar
    }
    if (token.contains("left") && token.contains("repeat")) || token == "left_rear" {
      return .left_repeater
    }
    if (token.contains("right") && token.contains("repeat")) || token == "right_rear" {
      return .right_repeater
    }
    if token == "left" {
      return .left
    }
    if token == "right" {
      return .right
    }

    return Camera(rawValue: token)
  }

  private static func probeMetadata(for fileURL: URL, cache: inout [String: ClipAssetProbe]) -> ClipAssetProbe {
    if let cached = cache[fileURL.path] {
      return cached
    }

    let asset = AVURLAsset(
      url: fileURL,
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    )
    let loaded = loadAssetMetadata(for: asset)
    let durationSeconds = max(0.1, normalizedDuration(loaded.duration))
    let probe: ClipAssetProbe

    if let naturalSize = loaded.naturalSize {
      probe = ClipAssetProbe(
        duration: durationSeconds,
        naturalSize: naturalSize
      )
    } else {
      probe = ClipAssetProbe(duration: durationSeconds, naturalSize: CGSize(width: 1280, height: 960))
    }

    cache[fileURL.path] = probe
    return probe
  }

  private static func normalizedDuration(_ time: CMTime) -> Double {
    let seconds = CMTimeGetSeconds(time)
    guard seconds.isFinite, seconds > 0 else { return 60.0 }
    return seconds
  }

  private static nonisolated func loadAssetMetadata(for asset: AVURLAsset) -> (duration: CMTime, naturalSize: CGSize?) {
    let semaphore = DispatchSemaphore(value: 0)
    var loadedDuration = CMTime.invalid
    var loadedNaturalSize: CGSize?

    Task.detached(priority: .userInitiated) {
      defer { semaphore.signal() }
      do {
        async let duration = asset.load(.duration)
        async let tracks = asset.loadTracks(withMediaType: .video)
        loadedDuration = try await duration
        if let track = try await tracks.first {
          async let naturalSize = track.load(.naturalSize)
          async let preferredTransform = track.load(.preferredTransform)
          let transformed = try await naturalSize.applying(preferredTransform)
          loadedNaturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        } else {
          loadedNaturalSize = nil
        }
      } catch {
        loadedDuration = .invalid
        loadedNaturalSize = nil
      }
    }

    semaphore.wait()
    return (loadedDuration, loadedNaturalSize)
  }

  private static func detectLayoutProfile(camerasFound: Set<Camera>) -> CameraLayoutProfile {
    let hw3Cameras: Set<Camera> = [.front, .back, .left_repeater, .right_repeater]
    let hw4Cameras: Set<Camera> = [.front, .back, .left, .right, .left_pillar, .right_pillar]
    let usesClassicSides = camerasFound.contains(.left_repeater) || camerasFound.contains(.right_repeater)
    let usesNewSides = camerasFound.contains(.left) || camerasFound.contains(.right) || camerasFound.contains(.left_pillar) || camerasFound.contains(.right_pillar)

    if !camerasFound.isEmpty, camerasFound.isSubset(of: hw3Cameras) {
      return .hw3FourCam
    }
    if usesNewSides && !usesClassicSides && camerasFound.subtracting(hw4Cameras).isEmpty {
      return .hw4SixCam
    }
    return .mixedUnknown
  }

  private static func overlapCount(in sets: [ClipSet]) -> Int {
    guard sets.count > 1 else { return 0 }
    var overlaps = 0
    for index in 0..<(sets.count - 1) {
      if sets[index + 1].date < sets[index].endDate {
        overlaps += 1
      }
    }
    return overlaps
  }
}

private struct ClipAssetProbe {
  let duration: Double
  let naturalSize: CGSize
}

private struct IndexedClipSetBuilder {
  let timestamp: String
  let date: Date
  var files: [Camera: URL] = [:]
  var durations: [Camera: Double] = [:]
  var naturalSizes: [Camera: CGSize] = [:]

  mutating func insert(camera: Camera, url: URL, metadata: ClipAssetProbe) {
    files[camera] = url
    durations[camera] = metadata.duration
    naturalSizes[camera] = metadata.naturalSize
  }

  mutating func replace(camera: Camera, url: URL, metadata: ClipAssetProbe) {
    files[camera] = url
    durations[camera] = metadata.duration
    naturalSizes[camera] = metadata.naturalSize
  }

  func makeClipSet() -> ClipSet {
    ClipSet(
      timestamp: timestamp,
      date: date,
      duration: durations.values.max() ?? 60.0,
      files: files,
      cameraDurations: durations,
      naturalSizes: naturalSizes
    )
  }
}
