//
//  TeslaCamTests.swift
//  TeslaCamTests
//
//  Created by Bolyki György on 05/02/2026.
//

import Foundation
import AVFoundation
import CoreVideo
import Testing
@testable import TeslaCam

@MainActor
struct TeslaCamTests {

  @Test func exportPresetMappingsRemainStable() async throws {
    #expect(ExportPreset.maxQualityHEVC.scriptPreset == "HEVC_CPU_MAX")
    #expect(ExportPreset.fastHEVC.scriptPreset == "HEVC_MAX")
    #expect(ExportPreset.editFriendlyProRes.scriptPreset == "PRORES_HQ")
    #expect(ExportPreset.maxQualityHEVC.defaultExtension == "mp4")
    #expect(ExportPreset.editFriendlyProRes.defaultExtension == "mov")
  }

  @Test func exportPresetsIncludeReviewSocialAndProxyChoices() async throws {
    let names = ExportPreset.allCases.map(\.displayName)

    #expect(names.contains("Evidence HEVC"))
    #expect(names.contains("Fast Review HEVC"))
    #expect(names.contains("Social 25 MB HEVC"))
    #expect(names.contains("Proxy HEVC"))
    #expect(names.contains("Master ProRes"))
    #expect(ExportPreset.socialShareHEVC.defaultExtension == "mp4")
    #expect(ExportPreset.proxyHEVC.defaultExtension == "mp4")
  }

  @Test func cameraTrackResolvesLatestCutAtTimelineSecond() async throws {
    let track = CameraTrack(
      keyframes: [
        CameraTrackKeyframe(seconds: 10, camera: .front),
        CameraTrackKeyframe(seconds: 20, camera: .back),
        CameraTrackKeyframe(seconds: 15, camera: .left_repeater)
      ]
    )

    #expect(track.camera(at: 9.99) == nil)
    #expect(track.camera(at: 10) == .front)
    #expect(track.camera(at: 16) == .left_repeater)
    #expect(track.camera(at: 25) == .back)
    #expect(track.normalized.keyframes.map(\.seconds) == [10, 15, 20])
  }

  @Test func exportRequestCarriesCameraTrackAndPreviewFlag() async throws {
    let track = CameraTrack(keyframes: [CameraTrackKeyframe(seconds: 4, camera: .front)])
    let request = exportRequestForPlan(cameraTrack: track, isPreviewSample: true)

    #expect(request.cameraTrack == track.normalized)
    #expect(request.isPreviewSample)
  }

  @Test func telemetryTimelineBuildsEventMarkers() async throws {
    var first = SeiMetadata()
    first.brakeApplied = true
    first.blinkerLeft = true
    var second = SeiMetadata()
    second.acceleratorPedalPosition = 80
    second.steeringWheelAngle = -52
    second.autopilotState = .autosteer
    second.linearAccelX = 0.7
    second.linearAccelY = 0.8
    let timeline = TelemetryTimeline(
      frames: [
        TelemetryFrame(timestampMs: 0, sei: first),
        TelemetryFrame(timestampMs: 1100, sei: second)
      ]
    )

    let kinds = Set(TelemetryEventMarker.markers(from: timeline).map(\.kind))

    #expect(kinds.contains(.brake))
    #expect(kinds.contains(.leftBlinker))
    #expect(kinds.contains(.accelerator))
    #expect(kinds.contains(.steering))
    #expect(kinds.contains(.autopilot))
    #expect(kinds.contains(.gForce))
  }

  @Test func layoutPresetRoundTripsCameraTrackAndOverlayOptions() async throws {
    let preset = CustomLayoutPreset(
      name: "Evidence",
      layoutRequest: .sixcam,
      previewLayoutMode: .focus,
      focusedCamera: .front,
      overlayOptions: ExportOverlayOptions(
        telemetryHUD: true,
        routeMap: true,
        privacyMask: false,
        includeReport: true,
        includeScreenshot: true,
        telemetryHUDMode: .minimal,
        speedUnit: .milesPerHour
      ),
      cameraTrack: CameraTrack(keyframes: [CameraTrackKeyframe(seconds: 12, camera: .back)])
    )

    let data = try CustomLayoutPresetCodec.encode(preset)
    let decoded = try CustomLayoutPresetCodec.decode(data)

    #expect(decoded == preset)
  }

  @Test func exportOverlayOptionsDecodeLegacyPresetDefaults() async throws {
    let json = """
    {
      "telemetryHUD": true,
      "routeMap": true,
      "privacyMask": false,
      "includeReport": true,
      "includeScreenshot": false
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(ExportOverlayOptions.self, from: json)

    #expect(decoded.telemetryHUD)
    #expect(decoded.routeMap)
    #expect(decoded.telemetryHUDMode == .detailed)
    #expect(decoded.speedUnit == .kilometersPerHour)
  }

  @Test func telemetryDisplayModelFormatsSpeedUnits() async throws {
    var metadata = SeiMetadata()
    metadata.vehicleSpeedMps = 10

    let model = TelemetryDisplayModel(sei: metadata)

    #expect(model.speedText(unit: .kilometersPerHour) == "36.0 km/h")
    #expect(model.speedText(unit: .milesPerHour) == "22.4 mph")
  }

  @Test func telemetryProcessorFormatsDetailedDriveData() async throws {
    var metadata = SeiMetadata()
    metadata.vehicleSpeedMps = 13.4
    metadata.acceleratorPedalPosition = 42
    metadata.steeringWheelAngle = -12
    metadata.gearState = .drive
    metadata.autopilotState = .tacc
    metadata.brakeApplied = true
    metadata.blinkerLeft = true
    metadata.headingDeg = 271.5
    metadata.latitudeDeg = 51.5074
    metadata.longitudeDeg = -0.1278
    metadata.linearAccelX = 0.12
    metadata.linearAccelY = -0.34
    metadata.linearAccelZ = 0.98

    let text = TelemetryProcessor.formatTelemetryDetailed(metadata, unit: .milesPerHour)

    #expect(text.contains("Speed: 30.0 mph"))
    #expect(text.contains("Gear: D"))
    #expect(text.contains("AP: TACC"))
    #expect(text.contains("Brake: On"))
    #expect(text.contains("Signal: Left"))
    #expect(text.contains("Heading: 272 deg"))
    #expect(text.contains("GPS: 51.50740, -0.12780"))
    #expect(text.contains("G: 0.12/-0.34/0.98"))
  }

  @Test func iPadGridMetricsKeepsRegularDashboardWithinPlannedRails() async throws {
    let metrics = IPadGridMetrics(containerWidth: 1032)

    #expect(metrics.layoutMode == .threeZone)
    #expect(metrics.eventRailWidth >= 240)
    #expect(metrics.eventRailWidth <= 280)
    #expect(metrics.inspectorWidth >= 300)
    #expect(metrics.inspectorWidth <= 340)
    #expect(metrics.centerWidth > metrics.inspectorWidth)
    #expect(Int(metrics.gutter) % 4 == 0)
  }

  @Test func iPadGridMetricsDoesNotFallBackToStackedPortraitLayout() async throws {
    let metrics = IPadGridMetrics(containerWidth: 700)

    #expect(metrics.layoutMode == .threeZone)
    #expect(metrics.centerWidth >= 320)
    #expect(Int(metrics.gutter) % 4 == 0)
  }

  @Test func compactControlsStayVisuallySmallButKeepTouchTargets() async throws {
    #expect(TeslaCamTheme.Metrics.cardCorner == 10)
    #expect(TeslaCamTheme.Metrics.controlCorner == 10)
    #expect(TeslaCamTheme.Metrics.compactCorner == 10)
    #expect(CompactControlSize.command.visualHeight <= 36)
    #expect(CompactControlSize.command.maxWidth == 160)
    #expect(CompactControlSize.chip.visualHeight <= 34)
    #expect(CompactControlSize.icon.visualWidth <= 36)

    for size in CompactControlSize.allCases {
      #expect(size.hitTargetHeight >= 44)
      #expect(size.hitTargetWidth >= 44)
    }
  }

  @Test @MainActor func demoModeLoadsSampleTimelineWithoutSourceFiles() async throws {
    let state = AppState()

    state.loadDemoTimeline()

    #expect(state.sourceURLs.isEmpty)
    #expect(state.clipSets.count == 3)
    #expect(state.totalDuration > 0)
    #expect(state.camerasDetected.contains(.front))
    #expect(state.eventSummaries.count == state.clipSets.count)
    #expect(state.telemetryModel != nil)
    #expect(state.telemetryRoute.count == state.clipSets.count)
  }

  @Test func nativeHEVCBitrateScalesWithCanvasSize() async throws {
    let hd = CGSize(width: 1920, height: 1080)
    let hw4 = CGSize(width: 5760, height: 3240)

    let hdMax = ExportPreset.maxQualityHEVC.nativeCompressionProperties(for: hd)[AVVideoAverageBitRateKey] as? Int
    let hw4Max = ExportPreset.maxQualityHEVC.nativeCompressionProperties(for: hw4)[AVVideoAverageBitRateKey] as? Int
    let hdFast = ExportPreset.fastHEVC.nativeCompressionProperties(for: hd)[AVVideoAverageBitRateKey] as? Int
    let hw4Fast = ExportPreset.fastHEVC.nativeCompressionProperties(for: hw4)[AVVideoAverageBitRateKey] as? Int

    #expect(hdMax == 45_000_000)
    #expect(hdFast == 20_000_000)
    #expect((hw4Max ?? 0) > (hdMax ?? 0))
    #expect((hw4Fast ?? 0) > (hdFast ?? 0))
  }

  @Test func exportPlanValidatesTrimRangeAndEnabledCameras() async throws {
    let emptyRange = exportRequestForPlan(
      enabledCameras: [.front],
      trimStart: Date(timeIntervalSince1970: 100),
      trimEnd: Date(timeIntervalSince1970: 100)
    )
    #expect(throws: ExportPlan.ValidationError.emptyTrimRange) {
      try ExportPlan(request: emptyRange)
    }

    let noCameras = exportRequestForPlan(enabledCameras: [])
    #expect(throws: ExportPlan.ValidationError.noEnabledCameras) {
      try ExportPlan(request: noCameras)
    }
  }

  @Test func exportPreflightWarnsWhenFreeDiskSpaceCannotBeChecked() async throws {
    // ExportPreflight.summary surfaces a non-blocking warning when the
    // file-access adapter can't determine free disk space (returns
    // nil). Without this safety net, the user might see no disk-space
    // information at all when the OS hides volume capacity (e.g. some
    // network mounts). The other two warning channels are already
    // covered (partial-clip d66432d, hidden-cameras 0c5127b); this
    // closes the third.
    let plan = try ExportPlan(
      request: exportRequestForPlan(enabledCameras: [.front])
    )
    let preflight = ExportPreflight(
      fileAccess: StubExportPreflightFileAccess(canWrite: true, availableCapacity: nil)
    )
    let summary = preflight.summary(for: plan)

    let diskUnknownWarnings = summary.warnings.filter { warning in
      warning.message.lowercased().contains("disk") &&
        warning.message.lowercased().contains("could not be checked")
    }
    #expect(!diskUnknownWarnings.isEmpty, "preflight must surface a 'disk space could not be checked' warning when capacity is nil")
    for warning in diskUnknownWarnings {
      #expect(!warning.isBlocking, "disk-unknown warning is informational; export still proceeds")
    }
    // hasWriteAccess must remain true (the write-access channel is
    // separate from the capacity channel) so we don't accidentally
    // double-fire as a blocking issue here.
    #expect(summary.hasWriteAccess)
  }

  @Test func exportPreflightWarnsAboutHiddenCamerasWhenSomeFilesAreNotEnabled() async throws {
    // ExportPreflight surfaces a non-blocking warning when a clip set
    // contains cameras the user has not enabled — they'll render as
    // black tiles rather than silently dropping out of the layout.
    // Build a request with three cameras present in files but only
    // `.front` enabled; assert the warning message names the hidden
    // cameras using their display names.
    let trimStart = Date(timeIntervalSince1970: 200)
    let trimEnd = Date(timeIntervalSince1970: 260)
    let request = ExportRequest(
      sets: [
        ClipSet(
          timestamp: "sample",
          date: trimStart,
          duration: 60,
          files: [
            .front: URL(fileURLWithPath: "/tmp/front.mov"),
            .back: URL(fileURLWithPath: "/tmp/back.mov"),
            .left_repeater: URL(fileURLWithPath: "/tmp/left.mov"),
          ],
          cameraDurations: [.front: 60, .back: 60, .left_repeater: 60],
          naturalSizes: [
            .front: CGSize(width: 1280, height: 960),
            .back: CGSize(width: 1280, height: 960),
            .left_repeater: CGSize(width: 1280, height: 960),
          ]
        )
      ],
      outputURL: URL(fileURLWithPath: "/tmp/teslacam-hidden.mov"),
      useSixCam: false,
      preset: .maxQualityHEVC,
      enabledCameras: [.front],
      trimStartSeconds: 0,
      trimEndSeconds: 60,
      trimStartDate: trimStart,
      trimEndDate: trimEnd,
      selectedRangeText: "sample",
      partialClipCount: 0,
      cameraTrack: .empty,
      isPreviewSample: false
    )
    let plan = try ExportPlan(request: request)
    let preflight = ExportPreflight(
      fileAccess: StubExportPreflightFileAccess(canWrite: true, availableCapacity: Int64.max)
    )
    let summary = preflight.summary(for: plan)

    let hiddenWarnings = summary.warnings.filter { warning in
      warning.message.contains("Hidden cameras")
    }
    #expect(!hiddenWarnings.isEmpty, "preflight must surface a 'Hidden cameras' warning when present cameras are not enabled")
    for warning in hiddenWarnings {
      #expect(!warning.isBlocking, "hidden-cameras warning is informational; export still ships with black tiles")
      // Display names of the hidden cameras should appear in the message.
      #expect(warning.message.contains(Camera.back.displayName), "warning text must name the hidden Back camera")
      #expect(warning.message.contains(Camera.left_repeater.displayName), "warning text must name the hidden Left repeater camera")
      // The enabled camera must NOT show up as 'hidden'.
      #expect(!warning.message.contains("\(Camera.front.displayName),") && !warning.message.hasSuffix(Camera.front.displayName + "."),
              "warning text must not list Front (the enabled camera) as hidden")
    }
  }

  @Test func exportPreflightWarnsAboutPartialClipsWhenRequestCarriesPartialCount() async throws {
    // ExportPlan carries partialClipCount through from the request;
    // ExportPreflight must surface a non-blocking warning that calls
    // out the count so the export status UI shows the user that some
    // clip spans will render with black placeholders. The current
    // tests cover preflight access + canvas + disk gates but never
    // exercise the partial-clip warning channel.
    let trimStart = Date(timeIntervalSince1970: 100)
    let trimEnd = Date(timeIntervalSince1970: 160)
    let request = ExportRequest(
      sets: [
        ClipSet(
          timestamp: "sample",
          date: trimStart,
          duration: 60,
          files: [.front: URL(fileURLWithPath: "/tmp/front.mov")],
          cameraDurations: [.front: 60],
          naturalSizes: [.front: CGSize(width: 1280, height: 960)]
        )
      ],
      outputURL: URL(fileURLWithPath: "/tmp/teslacam-partial.mov"),
      useSixCam: false,
      preset: .maxQualityHEVC,
      enabledCameras: [.front],
      trimStartSeconds: 0,
      trimEndSeconds: 60,
      trimStartDate: trimStart,
      trimEndDate: trimEnd,
      selectedRangeText: "sample",
      partialClipCount: 2,
      cameraTrack: .empty,
      isPreviewSample: false
    )
    let plan = try ExportPlan(request: request)
    let preflight = ExportPreflight(
      fileAccess: StubExportPreflightFileAccess(canWrite: true, availableCapacity: Int64.max)
    )
    let summary = preflight.summary(for: plan)

    let partialWarnings = summary.warnings.filter { warning in
      warning.message.contains("2") && warning.message.lowercased().contains("missing")
    }
    #expect(!partialWarnings.isEmpty, "preflight should surface a non-blocking warning that mentions the partial-clip count + 'missing'")
    for warning in partialWarnings {
      #expect(!warning.isBlocking, "partial-clip warning must be non-blocking — exports still ship with black placeholders")
    }
  }

  @Test func exportPlanRejectsRequestWithNoClips() async throws {
    // The exportRequestForPlan helper hard-codes a single-clip set so
    // the default path always has clips. Build a no-clip request
    // inline to cover the .noClips ValidationError variant — the only
    // ExportPlan error case the existing combined test does not
    // exercise.
    // Mirror exportRequestForPlan's argument list but with sets: []. Skips
    // the overlayOptions / layoutRequest fields so the helper's defaults
    // apply, exactly as the existing combined test does.
    let noClips = ExportRequest(
      sets: [],
      outputURL: URL(fileURLWithPath: "/tmp/teslacam-noclips.mov"),
      useSixCam: false,
      preset: .maxQualityHEVC,
      enabledCameras: [.front],
      trimStartSeconds: 0,
      trimEndSeconds: 60,
      trimStartDate: Date(timeIntervalSince1970: 0),
      trimEndDate: Date(timeIntervalSince1970: 60),
      selectedRangeText: "sample",
      partialClipCount: 0,
      cameraTrack: .empty,
      isPreviewSample: false
    )
    #expect(throws: ExportPlan.ValidationError.noClips) {
      try ExportPlan(request: noClips)
    }
  }

  @Test func exportPlanValidationErrorsCarryHumanDescription() async throws {
    // Every ValidationError case must carry a non-empty
    // LocalizedError.errorDescription so the surfaced UI / status
    // text is never blank when ExportPlan rejects a request. The
    // strings themselves can change, but they must not be nil or
    // empty.
    let cases: [ExportPlan.ValidationError] = [
      .noClips,
      .emptyTrimRange,
      .noEnabledCameras,
      .invalidCanvas,
    ]
    for variant in cases {
      let description = (variant as LocalizedError).errorDescription
      #expect(description != nil, "ValidationError.\(variant) must carry an errorDescription")
      #expect(!(description ?? "").isEmpty, "ValidationError.\(variant) errorDescription must be non-empty")
    }
  }

  @Test func exportPlanCapturesHw4CanvasWithoutDownscaling() async throws {
    let size = CGSize(width: 1920, height: 1080)
    let cameras = Set(Camera.hw4SixCamOrder)
    let request = exportRequestForPlan(
      useSixCam: true,
      enabledCameras: cameras,
      files: Dictionary(uniqueKeysWithValues: cameras.map { ($0, URL(fileURLWithPath: "/tmp/\($0.rawValue).mov")) }),
      naturalSizes: Dictionary(uniqueKeysWithValues: cameras.map { ($0, size) })
    )

    let plan = try ExportPlan(request: request)

    #expect(plan.canvasSize == CGSize(width: 5760, height: 3240))
    #expect(plan.tileSize == size)
    #expect(plan.cameraOrder == Camera.hw4SixCamOrder)
    #expect(plan.totalDuration == request.totalDuration)
  }

  @Test func exportPreflightReportsAccessAndDiskProblemsThroughAdapter() async throws {
    let request = exportRequestForPlan()
    let plan = try ExportPlan(request: request)
    let preflight = ExportPreflight(
      fileAccess: StubExportPreflightFileAccess(
        canWrite: false,
        availableCapacity: 1
      )
    )

    let summary = preflight.summary(for: plan)

    #expect(!summary.canExport)
    #expect(summary.blockingIssues.contains { $0.message == "The selected export location is not writable." })
    #expect(summary.blockingIssues.contains { $0.message.contains("Export preflight requires at least") })
  }

  @Test func exportPreflightEstimatesRecordedClipDurationForSparseTimeline() async throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let later = start.addingTimeInterval(15 * 24 * 60 * 60)
    let sets = [
      ClipSet(
        timestamp: "first",
        date: start,
        duration: 60,
        files: [.front: URL(fileURLWithPath: "/tmp/first-front.mov")],
        cameraDurations: [.front: 60],
        naturalSizes: [.front: CGSize(width: 1920, height: 1080)]
      ),
      ClipSet(
        timestamp: "second",
        date: later,
        duration: 60,
        files: [.front: URL(fileURLWithPath: "/tmp/second-front.mov")],
        cameraDurations: [.front: 60],
        naturalSizes: [.front: CGSize(width: 1920, height: 1080)]
      )
    ]
    let request = ExportRequest(
      sets: sets,
      outputURL: URL(fileURLWithPath: "/tmp/sparse.mov"),
      useSixCam: false,
      preset: .editFriendlyProRes,
      enabledCameras: [.front],
      trimStartSeconds: 0,
      trimEndSeconds: later.addingTimeInterval(60).timeIntervalSince(start),
      trimStartDate: start,
      trimEndDate: later.addingTimeInterval(60),
      selectedRangeText: "sparse",
      partialClipCount: 0
    )
    let plan = try ExportPlan(request: request)
    let preflight = ExportPreflight(
      fileAccess: StubExportPreflightFileAccess(
        canWrite: true,
        availableCapacity: 272 * 1024 * 1024 * 1024
      )
    )

    let summary = preflight.summary(for: plan)

    #expect(plan.totalDuration > 15 * 24 * 60 * 60)
    #expect(abs(plan.renderDuration - 120) < 0.001)
    #expect(summary.canExport)
  }

  @Test func exportPreflightBlocksOversizedHevcCanvasButAllowsProRes() async throws {
    let cameras: Set<Camera> = [.front]
    let oversized = CGSize(width: 9000, height: 2400)
    let hevcPlan = try ExportPlan(
      request: exportRequestForPlan(
        preset: .fastHEVC,
        enabledCameras: cameras,
        files: [.front: URL(fileURLWithPath: "/tmp/front.mov")],
        naturalSizes: [.front: oversized]
      )
    )
    let proResPlan = try ExportPlan(
      request: exportRequestForPlan(
        preset: .editFriendlyProRes,
        enabledCameras: cameras,
        files: [.front: URL(fileURLWithPath: "/tmp/front.mov")],
        naturalSizes: [.front: oversized]
      )
    )
    let preflight = ExportPreflight(fileAccess: StubExportPreflightFileAccess(canWrite: true, availableCapacity: Int64.max))

    let hevc = preflight.summary(for: hevcPlan)
    let proRes = preflight.summary(for: proResPlan)

    let width = Int(hevcPlan.canvasSize.width.rounded(.up))
    let height = Int(hevcPlan.canvasSize.height.rounded(.up))
    #expect(hevc.blockingIssues.map(\.message) == [
      "Composite canvas \(width)×\(height) exceeds the hardware HEVC encoder ceiling (8192 px per side). Reduce enabled cameras or switch to ProRes preset."
    ])
    #expect(proRes.canExport)
  }

  @Test func nativeExportPublishesPreflightBlockAsStatus() async throws {
    let controller = NativeExportController()
    let request = exportRequestForPlan(enabledCameras: [])

    controller.export(request: request)

    #expect(controller.currentJob?.phase == .failed)
    #expect(controller.currentJob?.failureReason == "Select at least one camera to export.")
    #expect(controller.isStatusPresented)
  }

  @Test func exportQueueStartsNextRequestWhenIdle() async throws {
    let controller = NativeExportController()
    let request = exportRequestForPlan(enabledCameras: [])

    controller.enqueue(request: request)

    #expect(controller.queuedRequests.isEmpty)
    #expect(controller.currentJob?.phase == .failed)
    #expect(controller.currentJob?.request.id == request.id)
  }

  @Test func preflightWriteCheckDoesNotMutateExistingOutputFile() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let output = root.url.appendingPathComponent("existing.mp4")
    try Data("original".utf8).write(to: output)

    let access = FileManagerExportPreflightFileAccess()
    #expect(access.canWrite(to: output))
    let data = try Data(contentsOf: output)
    #expect(String(data: data, encoding: .utf8) == "original")
  }

  @Test func preflightWriteCheckAllowsChosenNonExistingOutputFile() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let output = root.url.appendingPathComponent("new-export.mp4")

    let access = FileManagerExportPreflightFileAccess()
    #expect(access.canWrite(to: output))
    #expect(!FileManager.default.fileExists(atPath: output.path))
  }

  @Test func healthSummaryMixedCoverageFlagReflectsCounts() async throws {
    let summary = ExportHealthSummary(
      totalMinutes: 12,
      gapCount: 1,
      partialSetCount: 2,
      fourCameraSetCount: 4,
      sixCameraSetCount: 8,
      missingCameraCounts: [.right_pillar: 2]
    )

    #expect(summary.hasMixedCoverage)
    #expect(summary.missingCoverageSummary.contains("Right Pillar: 2"))
  }

  @Test func exportRequestTracksRealTotalDuration() async throws {
    let request = ExportRequest(
      sets: [
        ClipSet(timestamp: "a", date: Date(timeIntervalSince1970: 100), duration: 2, files: [:]),
        ClipSet(timestamp: "b", date: Date(timeIntervalSince1970: 200), duration: 63, files: [:])
      ],
      outputURL: URL(fileURLWithPath: "/tmp/test.mov"),
      useSixCam: false,
      preset: .maxQualityHEVC,
      enabledCameras: [.front],
      trimStartSeconds: 0,
      trimEndSeconds: 65,
      trimStartDate: Date(timeIntervalSince1970: 100),
      trimEndDate: Date(timeIntervalSince1970: 165),
      selectedRangeText: "range",
      partialClipCount: 0
    )

    #expect(request.totalParts == 2)
    #expect(abs(request.totalDuration - 65) < 0.001)
  }

  @Test func exportSnapshotDetailUsesRealDurationProgress() async throws {
    let request = ExportRequest(
      sets: [
        ClipSet(timestamp: "a", date: Date(timeIntervalSince1970: 100), duration: 125, files: [:])
      ],
      outputURL: URL(fileURLWithPath: "/tmp/test.mov"),
      useSixCam: false,
      preset: .maxQualityHEVC,
      enabledCameras: [.front],
      trimStartSeconds: 0,
      trimEndSeconds: 125,
      trimStartDate: Date(timeIntervalSince1970: 100),
      trimEndDate: Date(timeIntervalSince1970: 225),
      selectedRangeText: "range",
      partialClipCount: 0
    )

    let snapshot = ExportJobSnapshot(
      id: UUID(),
      request: request,
      phase: .renderingParts,
      progress: 0.5,
      phaseLabel: "Rendering",
      startedAt: .now,
      finishedAt: nil,
      outputURL: request.outputURL,
      logFileURL: URL(fileURLWithPath: "/tmp/log.txt"),
      workingDirectoryURL: nil,
      failureCategory: nil,
      failureReason: nil,
      completedParts: 0,
      totalParts: request.totalParts,
      completedDuration: 61,
      totalDuration: request.totalDuration,
      isIndeterminate: false,
      isTerminal: false,
      canRevealOutput: false,
      canRevealWorkingFiles: false,
      canRetry: false,
      isCancelled: false
    )

    #expect(snapshot.detailText == "1:01 / 2:05")
  }

  @Test func playbackControllerTracksSharedTimelineWithoutPlayers() async throws {
    let controller = MultiCamPlaybackController()
    let set = ClipSet(
      timestamp: "sample",
      date: Date(timeIntervalSince1970: 100),
      duration: 12,
      files: [:]
    )

    controller.load(set: set, startSeconds: 3.5)
    #expect(abs(controller.currentItemTime().seconds - 3.5) < 0.001)

    controller.seek(to: 20)
    #expect(abs(controller.currentItemTime().seconds - 12) < 0.001)

    controller.seek(to: 1.25)
    #expect(abs(controller.currentItemTime().seconds - 1.25) < 0.001)
  }

  @Test func playbackControllerProjectsPreviewTimeBetweenUITicks() async throws {
    var hostTime: CFTimeInterval = 100
    let controller = MultiCamPlaybackController(timeProvider: { hostTime })
    let set = ClipSet(
      timestamp: "sample",
      date: Date(timeIntervalSince1970: 100),
      duration: 12,
      files: [:]
    )

    controller.load(set: set)
    controller.play()
    hostTime += 0.05

    #expect(abs(controller.currentItemTime().seconds - 0.05) < 0.005)
    controller.pause()
  }

  @Test func duplicateFilesPreferNewestWhenRequested() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let olderFolder = root.url.appendingPathComponent("folder_a", isDirectory: true)
    let newerFolder = root.url.appendingPathComponent("folder_b", isDirectory: true)
    try FileManager.default.createDirectory(at: olderFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: newerFolder, withIntermediateDirectories: true)

    let frontOlder = olderFolder.appendingPathComponent("2026-01-01_00-00-00-front.mp4")
    let frontNewer = newerFolder.appendingPathComponent("2026-01-01_00-00-00-front.mp4")
    let back = olderFolder.appendingPathComponent("2026-01-01_00-00-00-rear.mp4")
    try "older".write(to: frontOlder, atomically: true, encoding: .utf8)
    try "newer".write(to: frontNewer, atomically: true, encoding: .utf8)
    try "back".write(to: back, atomically: true, encoding: .utf8)

    let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newerDate = Date(timeIntervalSince1970: 1_700_000_100)
    try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: frontOlder.path)
    try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: frontNewer.path)

    let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .preferNewest) { _ in }

    #expect(index.duplicateFileCount == 1)
    #expect(index.sets.count == 1)
    #expect(index.sets[0].file(for: .front)?.lastPathComponent == frontNewer.lastPathComponent)
  }

  @Test func duplicateFilesKeepAllWhenRequested() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let olderFolder = root.url.appendingPathComponent("folder_a", isDirectory: true)
    let newerFolder = root.url.appendingPathComponent("folder_b", isDirectory: true)
    try FileManager.default.createDirectory(at: olderFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: newerFolder, withIntermediateDirectories: true)

    let frontOlder = olderFolder.appendingPathComponent("2026-01-01_00-00-00-front.mp4")
    let frontNewer = newerFolder.appendingPathComponent("2026-01-01_00-00-00-front.mp4")
    let back = olderFolder.appendingPathComponent("2026-01-01_00-00-00-rear.mp4")
    try "older".write(to: frontOlder, atomically: true, encoding: .utf8)
    try "newer".write(to: frontNewer, atomically: true, encoding: .utf8)
    try "back".write(to: back, atomically: true, encoding: .utf8)

    let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .keepAll) { _ in }

    #expect(index.duplicateFileCount == 1)
    #expect(index.sets.count == 2)
    #expect(index.sets.contains { $0.file(for: .front)?.lastPathComponent == frontOlder.lastPathComponent })
    #expect(index.sets.contains { $0.file(for: .front)?.lastPathComponent == frontNewer.lastPathComponent })
  }

  @Test func indexSkipsSymlinkedDirectoriesAndFiles() async throws {
    let root = try TemporaryDirectory.make()
    let external = try TemporaryDirectory.make()
    defer { try? root.remove() }
    defer { try? external.remove() }

    let front = root.url.appendingPathComponent("2026-01-01_00-00-00-front.mp4")
    let externalRear = external.url.appendingPathComponent("2026-01-01_00-00-00-rear.mp4")
    try "front".write(to: front, atomically: true, encoding: .utf8)
    try "rear".write(to: externalRear, atomically: true, encoding: .utf8)

    let linkDir = root.url.appendingPathComponent("linked_dir", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: external.url)
    let linkRear = root.url.appendingPathComponent("2026-01-01_00-00-00-rear.mp4")
    try FileManager.default.createSymbolicLink(at: linkRear, withDestinationURL: externalRear)

    let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .mergeByTime) { _ in }
    #expect(index.sets.count == 1)
    #expect(index.sets[0].files[.front] != nil)
    #expect(index.sets[0].files[.back] == nil)
  }

  @Test func telemetryParserRejectsMalformedData() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let sample = root.url.appendingPathComponent("bad.mp4")
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: sample)

    #expect(throws: Error.self) {
      try TelemetryParser.parseTimeline(url: sample)
    }
  }

  @Test func telemetryParserExtractsTeslaSeiFromMdatWithoutVideoConfig() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let sample = root.url.appendingPathComponent("sei_only.mp4")
    var metadata = SeiMetadata()
    metadata.version = 1
    metadata.gearState = .drive
    metadata.frameSeqNo = 42
    metadata.vehicleSpeedMps = 13.4
    metadata.acceleratorPedalPosition = 18
    metadata.steeringWheelAngle = -2
    metadata.autopilotState = .tacc
    metadata.latitudeDeg = 51.5074
    metadata.longitudeDeg = -0.1278
    metadata.headingDeg = 271.5
    try makeMp4WithTeslaSei(metadata: metadata).write(to: sample)

    let timeline = try TelemetryParser.parseTimeline(url: sample)

    let frame = try #require(timeline.frames.first)
    #expect(timeline.frames.count == 1)
    #expect(frame.sei.version == 1)
    #expect(frame.sei.gearState == .drive)
    #expect(frame.sei.frameSeqNo == 42)
    #expect(abs(frame.sei.vehicleSpeedMps - 13.4) < 0.001)
    #expect(frame.sei.autopilotState == .tacc)
    #expect(abs(frame.sei.latitudeDeg - 51.5074) < 0.000001)
    #expect(abs(frame.sei.longitudeDeg - -0.1278) < 0.000001)
    #expect(abs(frame.sei.headingDeg - 271.5) < 0.000001)
  }

  @Test func telemetryProcessorRoutePointsCollapsesSameSecondAndStationaryFrames() async throws {
    var moving = SeiMetadata()
    moving.latitudeDeg = 51.5
    moving.longitudeDeg = -0.1
    moving.vehicleSpeedMps = 12
    var samePoint = SeiMetadata()
    samePoint.latitudeDeg = 51.5
    samePoint.longitudeDeg = -0.1
    var nextPoint = SeiMetadata()
    nextPoint.latitudeDeg = 51.501
    nextPoint.longitudeDeg = -0.099
    nextPoint.vehicleSpeedMps = 14

    let timeline = TelemetryTimeline(frames: [
      TelemetryFrame(timestampMs: 0, sei: moving),
      TelemetryFrame(timestampMs: 250, sei: moving),     // same whole second → dropped
      TelemetryFrame(timestampMs: 1100, sei: samePoint), // same coordinate → dropped
      TelemetryFrame(timestampMs: 2100, sei: nextPoint)
    ])

    let route = TelemetryProcessor.routePoints(from: timeline)
    #expect(route.count == 2)
    #expect(route[0].coordinate.latitude == 51.5)
    #expect(route[1].coordinate.latitude == 51.501)
  }

  @Test func telemetryRouteReplayInterpolatesFrameBetweenRoutePoints() async throws {
    let route = [
      TelemetryRoutePoint(
        id: 0,
        seconds: 10,
        coordinate: TelemetryCoordinate(latitude: 51.5000, longitude: -0.1000),
        speedKmh: 36,
        headingDeg: 350
      ),
      TelemetryRoutePoint(
        id: 1,
        seconds: 20,
        coordinate: TelemetryCoordinate(latitude: 51.5100, longitude: -0.0900),
        speedKmh: 72,
        headingDeg: 10
      )
    ]

    let frame = TelemetryRouteReplay(route: route).frame(at: 15)

    #expect(abs(frame.coordinate.latitude - 51.5050) < 0.000001)
    #expect(abs(frame.coordinate.longitude - -0.0950) < 0.000001)
    #expect(abs(frame.speedKmh - 54) < 0.000001)
    #expect(abs(frame.headingDeg - 0) < 0.000001)
  }

  @Test func telemetryRouteReplayKeepsEndpointsWhenDecimatingDisplaySamples() async throws {
    let route = (0..<12).map { index in
      TelemetryRoutePoint(
        id: index,
        seconds: Double(index),
        coordinate: TelemetryCoordinate(latitude: 51.5 + Double(index) * 0.001, longitude: -0.1),
        speedKmh: Double(index),
        headingDeg: 0
      )
    }

    let display = TelemetryRouteReplay.displaySamples(from: route, maxPoints: 5)

    #expect(display.count == 5)
    #expect(display.first?.id == 0)
    #expect(display.last?.id == 11)
  }

  @Test func telemetryRouteStyleUsesSpanAwareLineWidthAndStableSignature() async throws {
    #expect(TelemetryRouteStyle.lineWidth(latitudeDelta: 9, longitudeDelta: 1) == 2.0)
    #expect(TelemetryRouteStyle.lineWidth(latitudeDelta: 0.4, longitudeDelta: 0.4) == 4.0)

    let route = [
      TelemetryRoutePoint(
        id: 0,
        seconds: 1.0,
        coordinate: TelemetryCoordinate(latitude: 51.5000001, longitude: -0.1000001),
        speedKmh: 10,
        headingDeg: 90
      ),
      TelemetryRoutePoint(
        id: 1,
        seconds: 2.0,
        coordinate: TelemetryCoordinate(latitude: 51.5000002, longitude: -0.1000002),
        speedKmh: 12,
        headingDeg: 92
      )
    ]

    #expect(TelemetryRouteSignature.route(route) == "1:51.5,-0.1|2:51.5,-0.1")
  }

  @Test func telemetryProcessorDurationStringFormatsHoursAndMinutes() async throws {
    #expect(TelemetryProcessor.durationString(seconds: 0) == "0m total")
    #expect(TelemetryProcessor.durationString(seconds: 540) == "9m total")
    #expect(TelemetryProcessor.durationString(seconds: 3 * 3600 + 7 * 60) == "3h 7m total")
  }

  @Test func telemetryProcessorExpectedCoverageHonorsLayoutProfileWhenAmbiguous() async throws {
    let frontOnly = ClipSet(timestamp: "_", date: Date(), duration: 1, files: [.front: URL(fileURLWithPath: "/x")])
    #expect(TelemetryProcessor.expectedCoverageCameras(for: frontOnly, layoutProfile: .hw3FourCam) == Set(Camera.hw3ClassicOrder))
    #expect(TelemetryProcessor.expectedCoverageCameras(for: frontOnly, layoutProfile: .hw4SixCam) == Set(Camera.hw4SixCamOrder))

    let hw3Set = ClipSet(timestamp: "_", date: Date(), duration: 1, files: [
      .front: URL(fileURLWithPath: "/a"),
      .left_repeater: URL(fileURLWithPath: "/b")
    ])
    #expect(TelemetryProcessor.expectedCoverageCameras(for: hw3Set, layoutProfile: .hw4SixCam) == Set(Camera.hw3ClassicOrder))
  }

  @Test func sourceStoreNormalizeDeduplicatesAndDropsMissingFiles() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let liveOne = root.url.appendingPathComponent("alpha", isDirectory: true)
    let liveTwo = root.url.appendingPathComponent("beta", isDirectory: true)
    try FileManager.default.createDirectory(at: liveOne, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: liveTwo, withIntermediateDirectories: true)
    let phantom = root.url.appendingPathComponent("does-not-exist", isDirectory: true)

    let store = SourceStore()
    let normalized = store.normalize([liveOne, liveTwo, liveOne, phantom])

    #expect(normalized.map(\.path) == [liveOne.standardizedFileURL.path, liveTwo.standardizedFileURL.path])
  }

  @Test func sourceStoreBookmarkRoundTripRestoresPreviouslyRememberedURLs() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let folder = root.url.appendingPathComponent("kept", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let suite = "TeslaCamTests.SourceStore.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    // Plain bookmarks (not security-scoped) so the test runs without app signing.
    let key = "TeslaCam.lastSourceBookmarks.under-test"
    let writeStore = SourceStore(
      bookmarkKey: key,
      userDefaults: defaults,
      bookmarkCreationOptions: [],
      bookmarkResolutionOptions: []
    )
    writeStore.rememberBookmarks(for: [folder])

    let readStore = SourceStore(
      bookmarkKey: key,
      userDefaults: defaults,
      bookmarkCreationOptions: [],
      bookmarkResolutionOptions: []
    )
    let restored = readStore.restoreBookmarkedURLs()

    // macOS bookmark resolution returns the canonical /private/var path; the
    // input was the /var alias. Compare via resolvingSymlinksInPath so the
    // assertion is independent of the temp-directory symlink layout.
    let canonical = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL.path }
    #expect(restored.map(canonical) == [canonical(folder)])
  }

  @Test func sourceStoreRestoreReturnsEmptyAndPreservesBlobWhenAllFoldersAreGone() async throws {
    // Sandbox-revoke / drive-ejected / folder-deleted edge case for the
    // SourceStore bookmark layer. When every persisted bookmark resolves
    // to a URL whose underlying file no longer exists, restore() must
    // surface an empty list (no crash, no spurious URLs) and must NOT
    // rewrite the persisted blob — leaving the bookmark data behind so a
    // future re-mount can still resolve it.
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let folder = root.url.appendingPathComponent("vanished", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let suite = "TeslaCamTests.SourceStore.Revoke.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "TeslaCam.lastSourceBookmarks.revoke-under-test"

    let writeStore = SourceStore(
      bookmarkKey: key,
      userDefaults: defaults,
      bookmarkCreationOptions: [],
      bookmarkResolutionOptions: []
    )
    writeStore.rememberBookmarks(for: [folder])
    let blobBeforeRevoke = defaults.array(forKey: key) as? [Data] ?? []
    #expect(blobBeforeRevoke.count == 1)

    // Revoke: the folder disappears between launches.
    try FileManager.default.removeItem(at: folder)

    let readStore = SourceStore(
      bookmarkKey: key,
      userDefaults: defaults,
      bookmarkCreationOptions: [],
      bookmarkResolutionOptions: []
    )
    let restored = readStore.restoreBookmarkedURLs()
    #expect(restored.isEmpty)

    // Blob untouched because zero bookmarks survived — keep the bookmark
    // around so a future remount can still resolve it.
    let blobAfter = defaults.array(forKey: key) as? [Data] ?? []
    #expect(blobAfter == blobBeforeRevoke)
  }

  @Test func sourceStoreRestoreDropsMissingBookmarkAndShrinksBlobToSurvivors() async throws {
    // Partial-survivor scenario: two folders bookmarked, one gets removed.
    // restore() must return only the survivor and rewrite the persisted
    // blob to drop the dead bookmark — otherwise the missing folder lingers
    // forever in the blob, polluting subsequent restores.
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }
    let kept = root.url.appendingPathComponent("kept", isDirectory: true)
    let removed = root.url.appendingPathComponent("removed", isDirectory: true)
    try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: true)

    let suite = "TeslaCamTests.SourceStore.Partial.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "TeslaCam.lastSourceBookmarks.partial-under-test"

    let writeStore = SourceStore(
      bookmarkKey: key,
      userDefaults: defaults,
      bookmarkCreationOptions: [],
      bookmarkResolutionOptions: []
    )
    writeStore.rememberBookmarks(for: [kept, removed])
    let blobBefore = defaults.array(forKey: key) as? [Data] ?? []
    #expect(blobBefore.count == 2)

    try FileManager.default.removeItem(at: removed)

    let readStore = SourceStore(
      bookmarkKey: key,
      userDefaults: defaults,
      bookmarkCreationOptions: [],
      bookmarkResolutionOptions: []
    )
    let restored = readStore.restoreBookmarkedURLs()

    // Compare via resolvingSymlinksInPath so the assertion is independent
    // of the temp-directory /var ↔ /private/var aliasing (matches the
    // round-trip test above).
    let canonical = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL.path }
    #expect(restored.map(canonical) == [canonical(kept)])

    // Blob shrunk to the survivor only.
    let blobAfter = defaults.array(forKey: key) as? [Data] ?? []
    #expect(blobAfter.count == 1)
  }

  @Test func indexerScansRealFootageWhenSourceIsAvailable() async throws {
    // Opt-in real-footage Swift sibling of the Python real-footage
    // planner test (tests/test_integration.py::RealFootageIntegrationTests).
    // Skipped (vacuous pass) when neither
    // TESLACAM_REAL_FOOTAGE_SOURCE nor the project-owner local
    // fallback ~/Downloads/Teslacam resolves to a directory; CI
    // never has either.
    //
    // When fired, locks the contract for an HW3 source folder:
    //   - ClipIndexer.index does not throw
    //   - at least one clip set is found
    //   - cameras detected are the four HW3 classics
    //   - layoutProfile is hw3FourCam (auto layout)
    //   - totalDuration is positive
    let env = ProcessInfo.processInfo.environment
    let candidates: [URL] = {
      var out: [URL] = []
      if let raw = env["TESLACAM_REAL_FOOTAGE_SOURCE"], !raw.isEmpty {
        out.append(URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath))
      }
      if let home = env["HOME"], !home.isEmpty {
        out.append(URL(fileURLWithPath: home).appendingPathComponent("Downloads").appendingPathComponent("Teslacam"))
      }
      return out
    }()

    var source: URL?
    var isDir: ObjCBool = false
    for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir) && isDir.boolValue {
      source = candidate
      break
    }
    guard let source else {
      // No real source configured. Vacuous pass — the planner-side
      // Python test covers the same surface when configured.
      return
    }

    let index = try ClipIndexer.index(inputURLs: [source], duplicatePolicy: .mergeByTime) { _ in }

    #expect(index.sets.count >= 1, "real-footage source must produce at least one clip set")
    #expect(index.totalDuration > 0, "totalDuration must be positive on real footage")

    // HW3 classic source — these are the four cameras the user's
    // current ~/Downloads/Teslacam folder carries; if a future
    // source switches to HW4 the assertion below should be relaxed
    // to "at least one camera present", but for the locked baseline
    // (docs/improvement/real-footage-baseline-2026-05-09.md) HW3 is
    // the canonical test source.
    let expected: Set<Camera> = [.front, .back, .left_repeater, .right_repeater]
    #expect(index.camerasFound.isSubset(of: expected) || expected.isSubset(of: index.camerasFound),
            "real-footage cameras differ from HW3 baseline; got \(index.camerasFound)")
    #expect(index.layoutProfile == .hw3FourCam, "expected HW3 four-cam layout for the canonical source")
  }

  @Test func indexerSurvivesUnreadableAndCorruptedClipFilesWithFallbackDuration() async throws {
    // Lock the contract for corrupted / unreadable media: ClipIndexer
    // must not crash, must index every well-named clip file (filename
    // pattern is the source of truth), and must fall back to the
    // 60-second default duration when AVAsset cannot decode the bytes.
    // The composer's clip-readability check is a separate downstream
    // gate; the indexer's job is to surface every named clip so the
    // health summary can flag it.
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let savedClips = root.url.appendingPathComponent("SavedClips", isDirectory: true)
    try FileManager.default.createDirectory(at: savedClips, withIntermediateDirectories: true)

    // 1. Empty file — zero bytes. AVAsset returns invalid duration.
    let emptyURL = savedClips.appendingPathComponent("2026-07-01_00-00-00-front.mp4")
    try Data().write(to: emptyURL)

    // 2. Truncated mp4 header — valid 'ftyp' box prefix but no moov
    //    atom, so AVAsset can't establish duration / track metadata.
    let truncatedURL = savedClips.appendingPathComponent("2026-07-01_00-01-00-back.mp4")
    var truncatedHeader = Data()
    // box size = 24 bytes (big-endian)
    truncatedHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x18])
    // box type 'ftyp'
    truncatedHeader.append(contentsOf: [0x66, 0x74, 0x79, 0x70])
    // major brand 'isom'
    truncatedHeader.append(contentsOf: [0x69, 0x73, 0x6F, 0x6D])
    // minor version + compatible brands (just enough to be 24 bytes total)
    truncatedHeader.append(contentsOf: Array(repeating: UInt8(0), count: 12))
    try truncatedHeader.write(to: truncatedURL)

    // 3. Random garbage — guarantees AVAsset failure.
    let garbageURL = savedClips.appendingPathComponent("2026-07-01_00-02-00-left_repeater.mp4")
    var garbage = Data(count: 512)
    for index in 0..<garbage.count {
      garbage[index] = UInt8(index & 0xFF)
    }
    try garbage.write(to: garbageURL)

    // Index — must not throw.
    let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .mergeByTime) { _ in }

    // All three timestamps survived (filename is the source of truth;
    // AVAsset failure does not drop the clip).
    #expect(index.sets.count == 3)
    let timestamps = Set(index.sets.map(\.timestamp))
    #expect(timestamps == [
      "2026-07-01_00-00-00",
      "2026-07-01_00-01-00",
      "2026-07-01_00-02-00",
    ])

    // Every clip set falls back to the 60.0s default. The indexer's
    // normalizedDuration helper returns 60.0 on invalid CMTime; the
    // builder's max() across cameras propagates that into ClipSet.
    for clipSet in index.sets {
      #expect(clipSet.duration == 60.0, "expected 60s fallback for unreadable clip \(clipSet.timestamp), got \(clipSet.duration)")
    }
  }

  @Test func sharedOutputFixturesMatchNativeOutputContractForEveryPolicy() async throws {
    // Swift parity for the expected_output block emitted by
    // script/regen_fixtures.py. Exercises DomainOutputContract's three
    // helpers (defaultOutputFilename, uniqueOutputPath via
    // applyConflictPolicy(.unique), applyConflictPolicy(.overwrite|.error))
    // against each fixture's natural clip range with
    // clipDurationSeconds = 60 — same stub the regen script uses.
    let fixtureDirectory = repositoryRootForTests()
      .appendingPathComponent("fixtures", isDirectory: true)
      .appendingPathComponent("domain", isDirectory: true)
      .appendingPathComponent("cases", isDirectory: true)
    let fixtureURLs = try FileManager.default.contentsOfDirectory(
      at: fixtureDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    #expect(fixtureURLs.count >= 4)

    let decoder = JSONDecoder()
    var checkedFixtures = 0
    for fixtureURL in fixtureURLs {
      let fixture = try decoder.decode(DomainFixtureCase.self, from: Data(contentsOf: fixtureURL))
      guard let expected = fixture.expectedOutput else { continue }
      checkedFixtures += 1

      let root = try TemporaryDirectory.make()
      defer { try? root.remove() }
      try materializeDomainFixture(fixture, at: root.url)

      let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .mergeByTime) { _ in }

      // Empty-dataset branch: assert both sides agree there are no clips.
      if expected.emptyDataset == true {
        #expect(index.sets.isEmpty)
        continue
      }

      // Compute the natural range with a 60s clip duration, mirroring
      // Python's dataset_range + StubMediaProbe.
      let sortedSets = index.sets.sorted { lhs, rhs in
        if lhs.date == rhs.date { return lhs.timestamp < rhs.timestamp }
        return lhs.date < rhs.date
      }
      try #require(!sortedSets.isEmpty)
      let earliest = sortedSets.first!.date
      let latest = sortedSets.last!.date.addingTimeInterval(60.0)

      let actualDefaults: [String: String] = [
        "lossless": DomainOutputContract.defaultOutputFilename(mode: "lossless", startTime: earliest, endTime: latest),
        "quality": DomainOutputContract.defaultOutputFilename(mode: "quality", startTime: earliest, endTime: latest),
      ]
      try #require(expected.defaultFilenameByMode != nil)
      #expect(actualDefaults == expected.defaultFilenameByMode!)

      let targetName = actualDefaults["lossless"]!

      // unique-cascade: three calls in a fresh tempdir, write the
      // resolved file each time so the next call hits the next slot.
      let outDirA = try TemporaryDirectory.make()
      defer { try? outDirA.remove() }
      let target = outDirA.url.appendingPathComponent(targetName)
      var actualUnique: [String] = []
      for _ in 0..<3 {
        let resolved = try DomainOutputContract.applyConflictPolicy(path: target, policy: .unique)
        actualUnique.append(resolved.lastPathComponent)
        FileManager.default.createFile(atPath: resolved.path, contents: Data())
      }
      try #require(expected.uniqueResolution != nil)
      #expect(actualUnique == expected.uniqueResolution!)

      // overwrite-with-conflict: returns the input path unchanged.
      let outDirB = try TemporaryDirectory.make()
      defer { try? outDirB.remove() }
      let overwriteTarget = outDirB.url.appendingPathComponent(targetName)
      FileManager.default.createFile(atPath: overwriteTarget.path, contents: Data())
      let overwriteResolved = try DomainOutputContract.applyConflictPolicy(path: overwriteTarget, policy: .overwrite)
      try #require(expected.overwriteWithConflict != nil)
      #expect(overwriteResolved.lastPathComponent == expected.overwriteWithConflict!)

      // error-with-conflict: throws OutputAlreadyExistsError when the
      // path exists. We assert the language-agnostic contract (raises
      // + message contains the fragment); the fixture's
      // exception_type stays Python-side detail.
      let expectedError = try #require(expected.errorWithConflict)
      let outDirC = try TemporaryDirectory.make()
      defer { try? outDirC.remove() }
      let errorTarget = outDirC.url.appendingPathComponent(targetName)
      FileManager.default.createFile(atPath: errorTarget.path, contents: Data())
      if expectedError.raises {
        var caught: Error?
        do {
          _ = try DomainOutputContract.applyConflictPolicy(path: errorTarget, policy: .error)
        } catch {
          caught = error
        }
        let raised = try #require(caught, "error policy must raise on existing path")
        let fragment = expectedError.messageContains ?? DomainOutputContract.errorMessageFragment
        let message = (raised as? LocalizedError)?.errorDescription ?? "\(raised)"
        #expect(
          message.contains(fragment),
          "error message did not contain expected fragment for \(fixture.name): got \(message)"
        )
      } else {
        // No fixture currently flips this branch; the assertion exists so
        // a future fixture that disables raise still has a passable shape.
        let resolved = try DomainOutputContract.applyConflictPolicy(path: errorTarget, policy: .error)
        #expect(resolved == errorTarget)
      }
    }

    #expect(checkedFixtures >= 1)
  }

  @Test func sharedSelectionFixturesMatchNativeSelectionManifestForAllDuplicatePolicies() async throws {
    // Swift parity for the expected_selection.{policy} block emitted by
    // script/regen_fixtures.py. Uses a fixed clipDurationSeconds = 60
    // (matches the StubMediaProbe both the regen script and the Python
    // parity test agree on) so the fixture data does not depend on
    // AVAsset returning realistic durations for empty mp4 placeholders.
    let fixtureDirectory = repositoryRootForTests()
      .appendingPathComponent("fixtures", isDirectory: true)
      .appendingPathComponent("domain", isDirectory: true)
      .appendingPathComponent("cases", isDirectory: true)
    let fixtureURLs = try FileManager.default.contentsOfDirectory(
      at: fixtureDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    #expect(fixtureURLs.count >= 4)

    let decoder = JSONDecoder()
    var checkedFixtures = 0
    for fixtureURL in fixtureURLs {
      let fixture = try decoder.decode(DomainFixtureCase.self, from: Data(contentsOf: fixtureURL))
      guard let expectedSelection = fixture.expectedSelection else { continue }
      checkedFixtures += 1

      let root = try TemporaryDirectory.make()
      defer { try? root.remove() }
      try materializeDomainFixture(fixture, at: root.url)

      for policy in DuplicateClipPolicy.allCases {
        let expected = try #require(expectedSelection[policy.contractValue])
        let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: policy) { _ in }

        let actual: DomainSelectionManifest
        if index.sets.isEmpty {
          actual = .empty
        } else {
          let sortedSets = index.sets.sorted { lhs, rhs in
            if lhs.date == rhs.date {
              return lhs.timestamp < rhs.timestamp
            }
            return lhs.date < rhs.date
          }
          let earliest = sortedSets.first!.date
          let latest = sortedSets.last!.date.addingTimeInterval(60.0)
          actual = sortedSets.domainSelectionManifest(
            startTime: earliest,
            endTime: latest,
            clipDurationSeconds: 60.0,
            relativeTo: root.url
          )
        }
        #expect(actual == expected, "selection parity differs for \(fixture.name) under policy \(policy.contractValue)")
      }
    }

    #expect(checkedFixtures >= 1)
  }

  @Test func sharedDomainFixturesMatchNativeScanManifestsForAllDuplicatePolicies() async throws {
    let fixtureDirectory = repositoryRootForTests()
      .appendingPathComponent("fixtures", isDirectory: true)
      .appendingPathComponent("domain", isDirectory: true)
      .appendingPathComponent("cases", isDirectory: true)
    let fixtureURLs = try FileManager.default.contentsOfDirectory(
      at: fixtureDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    #expect(fixtureURLs.count >= 4)

    let decoder = JSONDecoder()
    for fixtureURL in fixtureURLs {
      let fixture = try decoder.decode(DomainFixtureCase.self, from: Data(contentsOf: fixtureURL))
      let root = try TemporaryDirectory.make()
      defer { try? root.remove() }
      try materializeDomainFixture(fixture, at: root.url)

      for policy in DuplicateClipPolicy.allCases {
        let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: policy) { _ in }
        let actual = index.domainScanManifest(relativeTo: root.url).withoutContractHeader
        let expected = try #require(fixture.expectedScan[policy.contractValue])
        #expect(actual == expected)
      }
    }
  }

  @Test func sharedLayoutFixturesMatchNativeLayoutPlan() async throws {
    let fixtureDirectory = repositoryRootForTests()
      .appendingPathComponent("fixtures", isDirectory: true)
      .appendingPathComponent("domain", isDirectory: true)
      .appendingPathComponent("cases", isDirectory: true)
    let fixtureURLs = try FileManager.default.contentsOfDirectory(
      at: fixtureDirectory,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    let decoder = JSONDecoder()
    var checked = 0
    for fixtureURL in fixtureURLs {
      let fixture = try decoder.decode(DomainFixtureCase.self, from: Data(contentsOf: fixtureURL))
      guard let expectedLayout = fixture.expectedLayout else { continue }
      checked += 1
      let detected = Set(fixture.expectedScan.values.flatMap(\.cameras).compactMap(Camera.init(rawValue:)))

      for request in CameraLayoutRequest.allCases {
        let expected = try #require(expectedLayout[request.rawValue])
        let plan = CameraLayoutPlan.build(
          requestedProfile: request,
          detectedCameras: detected,
          enabledCameras: detected,
          naturalSizes: [:]
        )
        #expect(plan.domainLayoutManifest == expected)
      }
    }

    #expect(checked >= 1)
  }

  @Test func currentMinuteRangeUsesCurrentClipBounds() async throws {
    let state = AppState()
    let date = Date(timeIntervalSince1970: 1_700_000_123)
    state.clipSets = [
      ClipSet(timestamp: "2023-11-14_22-15-23", date: date, duration: 43, files: [:])
    ]
    state.minDate = date
    state.maxDate = date.addingTimeInterval(43)
    state.rebuildTimelineForTesting()
    state.currentIndex = 0

    state.setCurrentMinuteRange()

    #expect(abs(state.trimStartSeconds - 0) < 0.001)
    #expect(abs(state.trimEndSeconds - 43) < 0.001)
  }

  @Test func testExportRangeClampsAroundCurrentMinute() async throws {
    let state = AppState()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let middle = start.addingTimeInterval(10 * 60 + 19)
    let end = start.addingTimeInterval(20 * 60 + 41)
    state.minDate = start
    state.maxDate = end
    state.currentIndex = 1
    state.clipSets = [
      ClipSet(timestamp: "a", date: start, duration: 60, files: [:]),
      ClipSet(timestamp: "b", date: middle, duration: 60, files: [:]),
      ClipSet(timestamp: "c", date: end, duration: 60, files: [:])
    ]
    state.rebuildTimelineForTesting()
    state.currentSeconds = 60

    state.setTestExportRange(minutes: 3)

    #expect(abs(state.trimStartSeconds - 0) < 0.001)
    #expect(abs(state.trimEndSeconds - 180) < 0.001)
  }

  @Test func timelinePlaybackSegmentMatchesLoadedClipWithinTolerance() async throws {
    let segment = TimelinePlaybackSegment(clipIndex: 2, startSeconds: 120, duration: 59.9996)

    #expect(segment.matchesLoadedSegment(clipIndex: 2, startSeconds: 120.0004, duration: 60.0))
  }

  @Test func timelinePlaybackSegmentDetectsClipBoundaryChanges() async throws {
    let clipSegment = TimelinePlaybackSegment(clipIndex: 2, startSeconds: 120, duration: 60)
    let gapSegment = TimelinePlaybackSegment(clipIndex: nil, startSeconds: 180, duration: 15)

    #expect(!clipSegment.matchesLoadedSegment(clipIndex: 3, startSeconds: 120, duration: 60))
    #expect(!clipSegment.matchesLoadedSegment(clipIndex: nil, startSeconds: 120, duration: 60))
    #expect(!gapSegment.matchesLoadedSegment(clipIndex: nil, startSeconds: 181, duration: 15))
  }

  @Test func timelineGapRangesReflectUnrecordedSpansBetweenCoveredClips() async throws {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let sets = [
      ClipSet(timestamp: "a", date: anchor, duration: 50, files: [:]),
      ClipSet(timestamp: "b", date: anchor.addingTimeInterval(80), duration: 60, files: [:]),
      ClipSet(timestamp: "c", date: anchor.addingTimeInterval(170), duration: 30, files: [:])
    ]

    let gaps = TimelineGapRange.ranges(for: sets)

    #expect(gaps.count == 2)
    #expect(abs(gaps[0].startSeconds - 50) < 0.001)
    #expect(abs(gaps[0].endSeconds - 80) < 0.001)
    #expect(abs(gaps[1].startSeconds - 140) < 0.001)
    #expect(abs(gaps[1].endSeconds - 170) < 0.001)
  }

  @Test func timelineGapRangesIgnoreOverlapAndTinyOffsets() async throws {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let sets = [
      ClipSet(timestamp: "a", date: anchor, duration: 60, files: [:]),
      ClipSet(timestamp: "b", date: anchor.addingTimeInterval(59), duration: 60, files: [:]),
      ClipSet(timestamp: "c", date: anchor.addingTimeInterval(120.4), duration: 30, files: [:])
    ]

    let gaps = TimelineGapRange.ranges(for: sets, minimumDuration: 2)

    #expect(gaps.isEmpty)
  }

  @Test func timelineCoverageMapReturnsGapSegmentBetweenClips() async throws {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let coverage = TimelineCoverageMap(sets: [
      ClipSet(timestamp: "a", date: anchor, duration: 50, files: [:]),
      ClipSet(timestamp: "b", date: anchor.addingTimeInterval(80), duration: 60, files: [:])
    ])

    #expect(coverage.activeClipIndex(at: 10) == 0)
    #expect(coverage.activeClipIndex(at: 60) == nil)

    let gap = coverage.playbackSegment(at: 60)
    #expect(gap.clipIndex == nil)
    #expect(abs(gap.startSeconds - 50) < 0.001)
    #expect(abs(gap.duration - 30) < 0.001)
  }

  @Test func timelineCoverageMapCountsCompletedClipsByEndTime() async throws {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let coverage = TimelineCoverageMap(sets: [
      ClipSet(timestamp: "a", date: anchor, duration: 50, files: [:]),
      ClipSet(timestamp: "b", date: anchor.addingTimeInterval(80), duration: 60, files: [:]),
      ClipSet(timestamp: "c", date: anchor.addingTimeInterval(170), duration: 30, files: [:])
    ])

    #expect(coverage.completedClipCount(at: 49.9) == 0)
    #expect(coverage.completedClipCount(at: 50) == 1)
    #expect(coverage.completedClipCount(at: 139.9) == 1)
    #expect(coverage.completedClipCount(at: 200) == 3)
  }

  @Test func timelineCoverageMapPreservesOriginalIndicesForUnsortedSets() async throws {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let sets = [
      ClipSet(timestamp: "late", date: anchor.addingTimeInterval(120), duration: 30, files: [:]),
      ClipSet(timestamp: "early", date: anchor, duration: 30, files: [:])
    ]
    let coverage = TimelineCoverageMap(sets: sets)

    #expect(coverage.activeClipIndex(at: 5) == 1)
    #expect(coverage.nearestClipIndex(to: 60) == 1)
    #expect(coverage.activeClipIndex(at: 125) == 0)
  }

  @Test func timelineStoreOwnsCoverageAndTrimSelection() async throws {
    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let sets = [
      ClipSet(timestamp: "a", date: anchor, duration: 50, files: [:]),
      ClipSet(timestamp: "b", date: anchor.addingTimeInterval(80), duration: 60, files: [:])
    ]
    var store = TimelineStore()

    store.load(sets: sets, minDate: anchor, maxDate: anchor.addingTimeInterval(140))
    store.setTrimRange(startSeconds: 52, endSeconds: 84, snapToMinute: true)

    #expect(abs(store.totalDuration - 140) < 0.001)
    #expect(store.gapRanges == [TimelineGapRange(startSeconds: 50, endSeconds: 80)])
    #expect(abs(store.trimStartSeconds - 0) < 0.001)
    #expect(abs(store.trimEndSeconds - 120) < 0.001)
    #expect(store.selectedSetsForExport.map(\.timestamp) == ["a", "b"])
    #expect(store.currentGapRange(at: 60) == TimelineGapRange(startSeconds: 50, endSeconds: 80))
  }

  @Test func exportStoreResolvesNamesAndBuildsRequests() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let store = ExportStore(fileManager: .default)
    let first = store.resolvedOutputURL(
      chosenURL: root.url,
      preferredFilename: "manual-export.mov",
      preset: .maxQualityHEVC
    )
    try Data().write(to: first)

    let second = store.resolvedOutputURL(
      chosenURL: root.url,
      preferredFilename: "manual-export.mov",
      preset: .maxQualityHEVC
    )

    let anchor = Date(timeIntervalSince1970: 1_700_000_000)
    let request = store.makeRequest(
      sets: [
        ClipSet(
          timestamp: "a",
          date: anchor,
          duration: 60,
          files: [.front: URL(fileURLWithPath: "/tmp/front.mov"), .left: URL(fileURLWithPath: "/tmp/left.mov")]
        )
      ],
      chosenURL: second,
      preset: .maxQualityHEVC,
      enabledCameras: [.front, .left],
      trimStartSeconds: 0,
      trimEndSeconds: 60,
      trimStartDate: anchor,
      trimEndDate: anchor.addingTimeInterval(60),
      selectedRangeText: "range",
      partialClipCount: 0
    )

    #expect(first.lastPathComponent == "manual-export.mp4")
    #expect(second.lastPathComponent == "manual-export-2.mp4")
    #expect(request?.outputURL.lastPathComponent == "manual-export-2.mp4")
    #expect(request?.useSixCam == true)
  }

  @Test func exportDirectoryNamingAvoidsExistingFiles() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let state = AppState()
    state.clipSets = [
      ClipSet(timestamp: "a", date: Date(timeIntervalSince1970: 1_700_000_000), duration: 60, files: [:])
    ]
    state.selectedExportCameras = [.front]
    state.layoutProfile = .hw3FourCam
    state.exportPreset = .maxQualityHEVC
    state.rebuildTimelineForTesting()

    let initial = state.resolvedExportURL(forTesting: root.url)
    try Data().write(to: initial)

    let resolved = state.resolvedExportURL(forTesting: root.url)

    #expect(resolved.lastPathComponent == "\(initial.deletingPathExtension().lastPathComponent)-2.mp4")
  }

  @Test func exportFileNamingAvoidsExistingFiles() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let chosen = root.url.appendingPathComponent("manual-export.mp4")
    try Data().write(to: chosen)

    let state = AppState()
    state.exportPreset = .maxQualityHEVC

    let resolved = state.resolvedExportURL(forTesting: chosen)

    #expect(resolved.lastPathComponent == "manual-export-2.mp4")
  }

  @Test func duplicateResolverDefaultsToMergePolicyOnly() async throws {
    let state = AppState()
    let summary = DuplicateResolutionSummary(
      duplicateFileCount: 2,
      duplicateTimestampCount: 1,
      overlapMinuteCount: 1
    )

    state.presentDuplicateResolverIfNeededForTesting(summary: summary)
    #expect(state.isDuplicateResolverPresented)

    state.dismissDuplicateResolver()
    state.chooseDuplicatePolicy(.keepAll)
    state.presentDuplicateResolverIfNeededForTesting(summary: summary)
    #expect(!state.isDuplicateResolverPresented)

    state.showDuplicateResolverForConflicts = true
    state.presentDuplicateResolverIfNeededForTesting(summary: summary)
    #expect(state.isDuplicateResolverPresented)
  }

  @Test func indexUsesRealClipDurationAndDetectsFourCamProfile() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let timestamp = "2026-04-08_11-30-00"
    let clipDate = try #require(teslaTimestampDate(timestamp))
    let duration: Double = 2.0

    try makeVideo(
      at: root.url.appendingPathComponent("\(timestamp)-front.mov"),
      duration: duration,
      size: CGSize(width: 1280, height: 960)
    )
    try makeVideo(
      at: root.url.appendingPathComponent("\(timestamp)-rear.mov"),
      duration: duration,
      size: CGSize(width: 1280, height: 960)
    )
    try makeVideo(
      at: root.url.appendingPathComponent("\(timestamp)-left_repeater.mov"),
      duration: duration,
      size: CGSize(width: 1280, height: 960)
    )
    try makeVideo(
      at: root.url.appendingPathComponent("\(timestamp)-right_repeater.mov"),
      duration: duration,
      size: CGSize(width: 1280, height: 960)
    )

    let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .mergeByTime) { _ in }

    #expect(index.layoutProfile == .hw3FourCam)
    #expect(index.sets.count == 1)
    #expect(abs(index.sets[0].duration - duration) < 0.25)
    #expect(abs(index.totalDuration - duration) < 0.25)
    #expect(abs(index.minDate.timeIntervalSince(clipDate)) < 1)
    #expect(abs(index.maxDate.timeIntervalSince(clipDate.addingTimeInterval(duration))) < 0.25)
  }

  @Test func indexDetectsSixCamProfileWhenNewSideAndPillarClipsExist() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let timestamp = "2026-04-08_12-00-00"
    let duration: Double = 1.0
    let cameras: [String] = [
      "front",
      "rear",
      "left",
      "right",
      "left_pillar",
      "right_pillar"
    ]

    for camera in cameras {
      try makeVideo(
        at: root.url.appendingPathComponent("\(timestamp)-\(camera).mov"),
        duration: duration,
        size: CGSize(width: 1920, height: 1080)
      )
    }

    let index = try ClipIndexer.index(inputURLs: [root.url], duplicatePolicy: .mergeByTime) { _ in }

    #expect(index.layoutProfile == .hw4SixCam)
    #expect(index.sets.count == 1)
    #expect(index.camerasFound.contains(.left))
    #expect(index.camerasFound.contains(.right))
    #expect(index.camerasFound.contains(.left_pillar))
    #expect(index.camerasFound.contains(.right_pillar))
  }

  @Test func nativeExportWritesMovieForSampleTimeline() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let outputURL = root.url.appendingPathComponent("sample_export.mov")
    let base = Date(timeIntervalSince1970: 1_775_650_200)
    let sets = [
      ClipSet(timestamp: "sample_1", date: base, duration: 1, files: [:]),
      ClipSet(timestamp: "sample_2", date: base.addingTimeInterval(60), duration: 1, files: [:])
    ]
    let request = ExportRequest(
      sets: sets,
      outputURL: outputURL,
      useSixCam: false,
      preset: .editFriendlyProRes,
      enabledCameras: [.front, .back, .left_repeater, .right_repeater],
      trimStartSeconds: 0,
      trimEndSeconds: 2,
      trimStartDate: base,
      trimEndDate: base.addingTimeInterval(2),
      selectedRangeText: "sample",
      partialClipCount: 0
    )

    let controller = NativeExportController()
    controller.export(request: request)

    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
      if controller.currentJob?.isTerminal == true {
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    #expect(controller.currentJob?.phase == .completed)
    let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    #expect(size > 0)
  }

  @Test func nativeExportWritesOverlaySidecars() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let outputURL = root.url.appendingPathComponent("overlay_export.mov")
    let base = Date(timeIntervalSince1970: 1_775_650_200)
    let request = ExportRequest(
      sets: [
        ClipSet(timestamp: "sample_1", date: base, duration: 1, files: [:])
      ],
      outputURL: outputURL,
      useSixCam: false,
      preset: .editFriendlyProRes,
      enabledCameras: [.front, .back, .left_repeater, .right_repeater],
      overlayOptions: ExportOverlayOptions(
        telemetryHUD: true,
        routeMap: true,
        privacyMask: true,
        includeReport: true,
        includeScreenshot: true
      ),
      trimStartSeconds: 0,
      trimEndSeconds: 1,
      trimStartDate: base,
      trimEndDate: base.addingTimeInterval(1),
      selectedRangeText: "overlay",
      partialClipCount: 0
    )

    let controller = NativeExportController()
    controller.export(request: request)

    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
      if controller.currentJob?.isTerminal == true {
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    #expect(controller.currentJob?.phase == .completed)
    let poster = outputURL.deletingPathExtension().appendingPathExtension("poster.png")
    let report = outputURL.deletingPathExtension().appendingPathExtension("report.pdf")
    #expect(FileManager.default.fileExists(atPath: poster.path))
    #expect(FileManager.default.fileExists(atPath: report.path))
    let posterSize = (try? poster.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    let reportSize = (try? report.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    #expect(posterSize > 0)
    #expect(reportSize > 0)
  }

  @Test func nativeExportUsesThreeByThreeCanvasForHw4Composite() async throws {
    let root = try TemporaryDirectory.make()
    defer { try? root.remove() }

    let timestamp = "2026-04-08_12-00-00"
    let clipDate = try #require(teslaTimestampDate(timestamp))
    let duration: Double = 1.0
    let size = CGSize(width: 1920, height: 1080)
    let files: [Camera: URL] = [
      .front: root.url.appendingPathComponent("\(timestamp)-front.mov"),
      .back: root.url.appendingPathComponent("\(timestamp)-rear.mov"),
      .left: root.url.appendingPathComponent("\(timestamp)-left.mov"),
      .right: root.url.appendingPathComponent("\(timestamp)-right.mov"),
      .left_pillar: root.url.appendingPathComponent("\(timestamp)-left_pillar.mov"),
      .right_pillar: root.url.appendingPathComponent("\(timestamp)-right_pillar.mov")
    ]

    for url in files.values {
      try makeVideo(at: url, duration: duration, size: size)
    }

    let outputURL = root.url.appendingPathComponent("hw4_export.mov")
    let request = ExportRequest(
      sets: [
        ClipSet(
          timestamp: timestamp,
          date: clipDate,
          duration: duration,
          files: files,
          cameraDurations: Dictionary(uniqueKeysWithValues: files.keys.map { ($0, duration) }),
          naturalSizes: Dictionary(uniqueKeysWithValues: files.keys.map { ($0, size) })
        )
      ],
      outputURL: outputURL,
      useSixCam: true,
      preset: .editFriendlyProRes,
      enabledCameras: Set(files.keys),
      trimStartSeconds: 0,
      trimEndSeconds: duration,
      trimStartDate: clipDate,
      trimEndDate: clipDate.addingTimeInterval(duration),
      selectedRangeText: "hw4",
      partialClipCount: 0
    )

    let controller = NativeExportController()
    controller.export(request: request)

    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
      if controller.currentJob?.isTerminal == true {
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    let asset = AVURLAsset(url: outputURL)
    let track = try #require(await asset.loadTracks(withMediaType: .video).first)
    let naturalSize = try await track.load(.naturalSize)

    #expect(Int(naturalSize.width.rounded()) == 5760)
    #expect(Int(naturalSize.height.rounded()) == 3240)
  }

}

private struct TemporaryDirectory {
  let url: URL

  static func make() throws -> TemporaryDirectory {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("teslacam-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return TemporaryDirectory(url: url)
  }

  func remove() throws {
    try FileManager.default.removeItem(at: url)
  }
}

private struct StubExportPreflightFileAccess: ExportPreflightFileAccess {
  var canWrite: Bool
  var availableCapacity: Int64?

  func canWrite(to outputURL: URL) -> Bool {
    canWrite
  }

  func availableCapacity(forWritingTo outputURL: URL) -> Int64? {
    availableCapacity
  }
}

private func exportRequestForPlan(
  preset: ExportPreset = .maxQualityHEVC,
  useSixCam: Bool = false,
  enabledCameras: Set<Camera> = [.front],
  files: [Camera: URL] = [.front: URL(fileURLWithPath: "/tmp/front.mov")],
  naturalSizes: [Camera: CGSize] = [.front: CGSize(width: 1920, height: 1080)],
  trimStart: Date = Date(timeIntervalSince1970: 100),
  trimEnd: Date = Date(timeIntervalSince1970: 102),
  cameraTrack: CameraTrack = .empty,
  isPreviewSample: Bool = false
) -> ExportRequest {
  ExportRequest(
    sets: [
      ClipSet(
        timestamp: "sample",
        date: trimStart,
        duration: max(0, trimEnd.timeIntervalSince(trimStart)),
        files: files,
        cameraDurations: Dictionary(uniqueKeysWithValues: files.keys.map { ($0, max(0, trimEnd.timeIntervalSince(trimStart))) }),
        naturalSizes: naturalSizes
      )
    ],
    outputURL: URL(fileURLWithPath: "/tmp/export.\(preset.defaultExtension)"),
    useSixCam: useSixCam,
    preset: preset,
    enabledCameras: enabledCameras,
    trimStartSeconds: 0,
    trimEndSeconds: max(0, trimEnd.timeIntervalSince(trimStart)),
    trimStartDate: trimStart,
    trimEndDate: trimEnd,
    selectedRangeText: "sample",
    partialClipCount: 0,
    cameraTrack: cameraTrack,
    isPreviewSample: isPreviewSample
  )
}

private func makeVideo(at url: URL, duration: Double, size: CGSize) throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
  let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(size.width),
    AVVideoHeightKey: Int(size.height)
  ]
  let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
  input.expectsMediaDataInRealTime = false
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: Int(size.width),
      kCVPixelBufferHeightKey as String: Int(size.height)
    ]
  )

  guard writer.canAdd(input) else {
    throw NSError(domain: "TeslaCamTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
  }
  writer.add(input)
  writer.startWriting()
  writer.startSession(atSourceTime: .zero)

  let fps = 10
  let frameCount = max(1, Int(duration * Double(fps)))
  for frameIndex in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
      Thread.sleep(forTimeInterval: 0.001)
    }

    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
      ] as CFDictionary,
      &pixelBuffer
    )

    guard let pixelBuffer else {
      throw NSError(domain: "TeslaCamTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate pixel buffer"])
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
      memset(base, Int32(frameIndex % 255), CVPixelBufferGetDataSize(pixelBuffer))
    }

    let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
    guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
      throw NSError(domain: "TeslaCamTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot append frame"])
    }
  }

  input.markAsFinished()
  let group = DispatchGroup()
  group.enter()
  writer.finishWriting {
    group.leave()
  }
  group.wait()

  if let error = writer.error {
    throw error
  }
}

private func makeMp4WithTeslaSei(metadata: SeiMetadata) -> Data {
  let nal = makeTeslaSeiNal(metadata: metadata)
  var mdatPayload = Data()
  appendUInt32BE(UInt32(nal.count), to: &mdatPayload)
  mdatPayload.append(nal)

  var data = Data()
  appendUInt32BE(UInt32(8 + mdatPayload.count), to: &data)
  data.append(contentsOf: [0x6D, 0x64, 0x61, 0x74])
  data.append(mdatPayload)
  return data
}

private func makeTeslaSeiNal(metadata: SeiMetadata) -> Data {
  var payload = Data()
  appendProtoVarint(field: 1, value: UInt64(metadata.version), to: &payload)
  appendProtoVarint(field: 2, value: UInt64(metadata.gearState.rawValue), to: &payload)
  appendProtoVarint(field: 3, value: metadata.frameSeqNo, to: &payload)
  appendProtoFixed32(field: 4, value: metadata.vehicleSpeedMps.bitPattern, to: &payload)
  appendProtoFixed32(field: 5, value: metadata.acceleratorPedalPosition.bitPattern, to: &payload)
  appendProtoFixed32(field: 6, value: metadata.steeringWheelAngle.bitPattern, to: &payload)
  appendProtoVarint(field: 7, value: metadata.blinkerLeft ? 1 : 0, to: &payload)
  appendProtoVarint(field: 8, value: metadata.blinkerRight ? 1 : 0, to: &payload)
  appendProtoVarint(field: 9, value: metadata.brakeApplied ? 1 : 0, to: &payload)
  appendProtoVarint(field: 10, value: UInt64(metadata.autopilotState.rawValue), to: &payload)
  appendProtoFixed64(field: 11, value: metadata.latitudeDeg.bitPattern, to: &payload)
  appendProtoFixed64(field: 12, value: metadata.longitudeDeg.bitPattern, to: &payload)
  appendProtoFixed64(field: 13, value: metadata.headingDeg.bitPattern, to: &payload)
  appendProtoFixed64(field: 14, value: metadata.linearAccelX.bitPattern, to: &payload)
  appendProtoFixed64(field: 15, value: metadata.linearAccelY.bitPattern, to: &payload)
  appendProtoFixed64(field: 16, value: metadata.linearAccelZ.bitPattern, to: &payload)

  var nal = Data([0x06, 0x05, 0x00, 0x42, 0x69])
  nal.append(payload)
  nal.append(0x80)
  return nal
}

private func appendProtoVarint(field: Int, value: UInt64, to data: inout Data) {
  appendVarint(UInt64(field << 3), to: &data)
  appendVarint(value, to: &data)
}

private func appendProtoFixed32(field: Int, value: UInt32, to data: inout Data) {
  appendVarint(UInt64((field << 3) | 5), to: &data)
  data.append(UInt8(value & 0xFF))
  data.append(UInt8((value >> 8) & 0xFF))
  data.append(UInt8((value >> 16) & 0xFF))
  data.append(UInt8((value >> 24) & 0xFF))
}

private func appendProtoFixed64(field: Int, value: UInt64, to data: inout Data) {
  appendVarint(UInt64((field << 3) | 1), to: &data)
  for shift in stride(from: 0, through: 56, by: 8) {
    data.append(UInt8((value >> UInt64(shift)) & 0xFF))
  }
}

private func appendVarint(_ value: UInt64, to data: inout Data) {
  var value = value
  while value >= 0x80 {
    data.append(UInt8(value & 0x7F) | 0x80)
    value >>= 7
  }
  data.append(UInt8(value))
}

private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
  data.append(UInt8((value >> 24) & 0xFF))
  data.append(UInt8((value >> 16) & 0xFF))
  data.append(UInt8((value >> 8) & 0xFF))
  data.append(UInt8(value & 0xFF))
}

private func teslaTimestampDate(_ timestamp: String) -> Date? {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone.current
  formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
  return formatter.date(from: timestamp)
}

private struct DomainFixtureCase: Decodable {
  let name: String
  let files: [DomainFixtureFile]
  let expectedScan: [String: DomainScanManifestWithoutHeader]
  let expectedLayout: [String: DomainLayoutManifest]?
  let expectedSelection: [String: DomainSelectionManifest]?
  let expectedOutput: DomainOutputManifest?

  enum CodingKeys: String, CodingKey {
    case name
    case files
    case expectedScan = "expected_scan"
    case expectedLayout = "expected_layout"
    case expectedSelection = "expected_selection"
    case expectedOutput = "expected_output"
  }
}

private struct DomainFixtureFile: Decodable {
  let path: String
  let mtime: TimeInterval?
}

private struct DomainScanManifestWithoutHeader: Codable, Equatable {
  let clipSetCount: Int
  let duplicateFileCount: Int
  let duplicateTimestampCount: Int
  let cameras: [String]
  let clipSets: [DomainClipSetManifest]

  enum CodingKeys: String, CodingKey {
    case clipSetCount = "clip_set_count"
    case duplicateFileCount = "duplicate_file_count"
    case duplicateTimestampCount = "duplicate_timestamp_count"
    case cameras
    case clipSets = "clip_sets"
  }
}

private extension DomainScanManifest {
  var withoutContractHeader: DomainScanManifestWithoutHeader {
    DomainScanManifestWithoutHeader(
      clipSetCount: clipSetCount,
      duplicateFileCount: duplicateFileCount,
      duplicateTimestampCount: duplicateTimestampCount,
      cameras: cameras,
      clipSets: clipSets
    )
  }
}

private extension DuplicateClipPolicy {
  var contractValue: String {
    switch self {
    case .mergeByTime: return "merge-by-time"
    case .keepAll: return "keep-all"
    case .preferNewest: return "prefer-newest"
    }
  }
}

private func repositoryRootForTests() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func materializeDomainFixture(_ fixture: DomainFixtureCase, at root: URL) throws {
  for entry in fixture.files {
    let url = root.appendingPathComponent(entry.path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("fixture".utf8).write(to: url)
    if let mtime = entry.mtime {
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: mtime)],
        ofItemAtPath: url.path
      )
    }
  }
}
