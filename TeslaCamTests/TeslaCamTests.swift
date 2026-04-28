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
    #expect(throws: ExportPlan.ValidationError.self) {
      try ExportPlan(request: emptyRange)
    }

    let noCameras = exportRequestForPlan(enabledCameras: [])
    #expect(throws: ExportPlan.ValidationError.self) {
      try ExportPlan(request: noCameras)
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
  trimEnd: Date = Date(timeIntervalSince1970: 102)
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
    partialClipCount: 0
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

  enum CodingKeys: String, CodingKey {
    case name
    case files
    case expectedScan = "expected_scan"
    case expectedLayout = "expected_layout"
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
