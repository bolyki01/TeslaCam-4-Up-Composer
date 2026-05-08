import Foundation

/// Pure helpers extracted from `AppState` for telemetry-derived computation.
/// Kept as a value-namespace so it has no instance state and is trivially testable.
enum TelemetryProcessor {
  /// Builds a deduplicated route from a parsed telemetry timeline. Skips frames
  /// inside the same whole second and frames whose coordinate did not move.
  static func routePoints(from timeline: TelemetryTimeline) -> [TelemetryRoutePoint] {
    var points: [TelemetryRoutePoint] = []
    points.reserveCapacity(min(240, timeline.frames.count))
    var lastWholeSecond = -1
    var lastCoordinate: TelemetryCoordinate?
    for frame in timeline.frames {
      let seconds = Int((frame.timestampMs / 1000.0).rounded(.down))
      guard seconds != lastWholeSecond else { continue }
      lastWholeSecond = seconds
      let coordinate = TelemetryCoordinate(
        latitude: frame.sei.latitudeDeg,
        longitude: frame.sei.longitudeDeg
      )
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

  /// Compact one-line telemetry overlay text. Returns empty when no SEI frame is available.
  static func formatTelemetryCompact(_ sei: SeiMetadata?) -> String {
    guard let sei else { return "" }
    return TelemetryDisplayModel(sei: sei).compactText
  }

  /// Produces a human-readable duration label like "1h 12m total" or "5m total".
  static func durationString(seconds: Double) -> String {
    let totalMinutes = max(0, Int((seconds / 60).rounded()))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 {
      return "\(minutes)m total"
    }
    return "\(hours)h \(minutes)m total"
  }

  /// Cameras that should be present for a clip set based on which side cameras
  /// were captured (HW3 repeaters vs HW4 wide/pillar). When the set is fully
  /// mixed or empty, falls back to the supplied profile.
  static func expectedCoverageCameras(for set: ClipSet, layoutProfile: CameraLayoutProfile) -> Set<Camera> {
    let present = Set(set.files.keys)
    let containsClassicSides = !present.intersection([.left_repeater, .right_repeater]).isEmpty
    let containsSixCamMarkers = !present.intersection([.left, .right, .left_pillar, .right_pillar]).isEmpty

    if containsClassicSides && !containsSixCamMarkers {
      return Set(Camera.hw3ClassicOrder)
    }
    if containsSixCamMarkers && !containsClassicSides {
      return Set(Camera.hw4SixCamOrder)
    }
    if containsClassicSides && containsSixCamMarkers {
      return present
    }

    switch layoutProfile {
    case .hw3FourCam:
      return Set(Camera.hw3ClassicOrder)
    case .hw4SixCam:
      return Set(Camera.hw4SixCamOrder)
    case .mixedUnknown:
      return present
    }
  }

  /// Builds high-level facts about a clip set (file count, total duration,
  /// most common resolution, missing-camera count) for the iPad health panel.
  static func buildClipHealthFacts(
    from sets: [ClipSet],
    layoutProfile: CameraLayoutProfile
  ) -> [ClipHealthFact] {
    let totalDuration = sets.reduce(0) { $0 + $1.duration }
    let fileCount = sets.reduce(0) { $0 + $1.files.count }
    let expectedMissing = sets.reduce(0) { partials, set in
      let expected = expectedCoverageCameras(for: set, layoutProfile: layoutProfile)
      return partials + max(0, expected.subtracting(Set(set.files.keys)).count)
    }
    let resolutions = sets.flatMap { set in
      set.naturalSizes.values.map { size in
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
      }
    }
    let mostCommonResolution = Dictionary(grouping: resolutions, by: { $0 })
      .max { lhs, rhs in lhs.value.count < rhs.value.count }?
      .key ?? "Unknown"

    return [
      ClipHealthFact(title: "Files", value: "\(fileCount)", severity: .info),
      ClipHealthFact(title: "Duration", value: durationString(seconds: totalDuration), severity: .info),
      ClipHealthFact(title: "Main Size", value: mostCommonResolution, severity: .info),
      ClipHealthFact(
        title: "Missing",
        value: "\(expectedMissing)",
        severity: expectedMissing == 0 ? .info : .warning
      )
    ]
  }

  /// Walks distinct clip-set folders and reads `event.json` + `thumb.png`
  /// to produce one summary per recorded event for the iPad event rail.
  static func buildEventSummaries(from sets: [ClipSet]) -> [TeslaCamEventSummary] {
    var seenFolders = Set<String>()
    var events: [TeslaCamEventSummary] = []
    for (index, set) in sets.enumerated() {
      guard let folder = set.files.values.first?.deletingLastPathComponent() else { continue }
      let folderKey = folder.standardizedFileURL.path
      guard seenFolders.insert(folderKey).inserted else { continue }
      events.append(loadEventSummary(folder: folder, fallbackDate: set.date, clipIndex: index))
    }
    return events.sorted { $0.timestamp < $1.timestamp }
  }

  /// Reads a single `event.json` payload alongside the clip folder, falling back
  /// to the clip's own timestamp and skipping a missing thumbnail.
  static func loadEventSummary(folder: URL, fallbackDate: Date, clipIndex: Int) -> TeslaCamEventSummary {
    let eventURL = folder.appendingPathComponent("event.json")
    let thumbnailURL = folder.appendingPathComponent("thumb.png")
    var payload: EventJSON?
    if let data = try? Data(contentsOf: eventURL) {
      payload = try? JSONDecoder().decode(EventJSON.self, from: data)
    }
    let date = payload?.parsedTimestamp ?? fallbackDate
    let coordinate = TelemetryCoordinate(
      latitude: Double(payload?.estLat ?? "") ?? 0,
      longitude: Double(payload?.estLon ?? "") ?? 0
    )
    return TeslaCamEventSummary(
      id: folder.standardizedFileURL.path,
      clipIndex: clipIndex,
      timestamp: date,
      folderURL: folder,
      thumbnailURL: FileManager.default.fileExists(atPath: thumbnailURL.path) ? thumbnailURL : nil,
      city: payload?.city ?? "",
      street: payload?.street ?? "",
      reason: payload?.reason ?? "recording",
      camera: payload?.camera ?? "",
      coordinate: coordinate.isUsable ? coordinate : nil
    )
  }
}

private struct EventJSON: Decodable {
  let timestamp: String?
  let city: String?
  let street: String?
  let estLat: String?
  let estLon: String?
  let reason: String?
  let camera: String?

  enum CodingKeys: String, CodingKey {
    case timestamp
    case city
    case street
    case estLat = "est_lat"
    case estLon = "est_lon"
    case reason
    case camera
  }

  var parsedTimestamp: Date? {
    guard let timestamp else { return nil }
    return TeslaCamFormatters.eventTimestamp.date(from: timestamp)
  }
}
