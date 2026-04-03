//
//  TeslaCamTests.swift
//  TeslaCamTests
//
//  Created by Bolyki György on 05/02/2026.
//

import Testing
@testable import TeslaCam

struct TeslaCamTests {

  @Test func exportPresetMappingsRemainStable() async throws {
    #expect(ExportPreset.maxQualityHEVC.scriptPreset == "HEVC_CPU_MAX")
    #expect(ExportPreset.fastHEVC.scriptPreset == "HEVC_MAX")
    #expect(ExportPreset.editFriendlyProRes.scriptPreset == "PRORES_HQ")
    #expect(ExportPreset.maxQualityHEVC.defaultExtension == "mp4")
    #expect(ExportPreset.editFriendlyProRes.defaultExtension == "mov")
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

}
