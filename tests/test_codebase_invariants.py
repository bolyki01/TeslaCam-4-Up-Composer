"""Tripwire tests for codebase-wide invariants.

These tests scan the shipping Python source tree for patterns that
have a documented sacred-rule reason to stay absent. They are cheap
(pure file walks; no subprocess) and they are the one place a
regression of "we accidentally introduced shell injection" or
"someone called eval on an untrusted string" surfaces immediately.

The Swift side has its own equivalent guard documented in
``docs/improvement/security-audit-2026-05-09.md`` (G3 process-spawn
audit). Those are git-grep checks; this module's job is the Python
half.

Each forbidden pattern carries a justification comment so a future
maintainer can decide whether to delete the rule or update the test
when behaviour legitimately needs to change.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
SHIPPING_ROOT = REPO_ROOT / "teslacam_cli"
SWIFT_SHIPPING_ROOT = REPO_ROOT / "TeslaCam"
XCODE_PROJECT_FILE = REPO_ROOT / "TeslaCam.xcodeproj" / "project.pbxproj"


def _shipping_python_files() -> Iterable[Path]:
    """Every .py file under teslacam_cli/, recursively."""
    yield from sorted(SHIPPING_ROOT.rglob("*.py"))


def _shipping_swift_files() -> Iterable[Path]:
    """Every .swift file under TeslaCam/ (excluding the iPad
    target's resources and any nested generated content). Plain
    rglob is fine — TeslaCam/ does not nest derived data; the
    cache isolation work parks build state under .cache/.
    """
    yield from sorted(SWIFT_SHIPPING_ROOT.rglob("*.swift"))


def _grep_lines(pattern: re.Pattern[str], paths: Iterable[Path]) -> list[tuple[Path, int, str]]:
    hits: list[tuple[Path, int, str]] = []
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        for index, line in enumerate(text.splitlines(), start=1):
            if pattern.search(line):
                hits.append((path, index, line.rstrip()))
    return hits


def _format_hits(hits: list[tuple[Path, int, str]]) -> str:
    return "\n".join(f"  {path.relative_to(REPO_ROOT)}:{line}: {body}" for path, line, body in hits)


class ForbiddenPatternTests(unittest.TestCase):
    """Patterns that must never appear in the shipping CLI source.

    Each test pins one rule. If a pattern legitimately has to come
    back (e.g. a documented exception), update the matching rule
    here in the same commit.
    """

    def test_shell_true_is_never_used_in_subprocess_calls(self):
        # Justification: every subprocess invocation in
        # teslacam_cli/process_tools.py builds an argv list and passes
        # it to subprocess.Popen WITHOUT shell=True. Reintroducing
        # shell=True would let user-controlled paths reach shell
        # metacharacters (sacred rule G3).
        pattern = re.compile(r"\bshell\s*=\s*True\b")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(hits, [], f"shell=True must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_os_system_is_never_used(self):
        # Justification: same reasoning as shell=True; os.system
        # invokes /bin/sh -c with the input string and inherits
        # injection risk.
        pattern = re.compile(r"\bos\.system\(")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(hits, [], f"os.system() must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_dynamic_eval_and_exec_are_never_used(self):
        # Justification: the CLI never needs to evaluate user-supplied
        # code; eval / exec on any string risks remote code execution
        # if the input ever flows from a TeslaCam-derived path or env
        # var. Limit to the literal call form `eval(` / `exec(` so
        # words like "evaluate" and "execute" in comments are fine.
        eval_pattern = re.compile(r"(?<![A-Za-z_])eval\(")
        exec_pattern = re.compile(r"(?<![A-Za-z_])exec\(")
        hits = _grep_lines(eval_pattern, _shipping_python_files()) + _grep_lines(
            exec_pattern, _shipping_python_files()
        )
        self.assertEqual(hits, [], f"eval()/exec() must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_dynamic_import_is_never_used(self):
        # Justification: regular `import` statements flow through the
        # well-known module resolution path; __import__ on a runtime
        # string is suspicious in CLI code that does not need plugin
        # loading. If we ever add a real plugin system, document it
        # and update this rule.
        pattern = re.compile(r"(?<![A-Za-z_])__import__\(")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(hits, [], f"__import__() must not appear in shipping CLI source:\n{_format_hits(hits)}")

    def test_break_system_packages_is_never_committed(self):
        # Justification: --break-system-packages bypasses PEP 668
        # protection and is a developer convenience for Linux-managed
        # Python installs. It must never be committed to shipping
        # source — it would leak into pip install commands the CLI
        # might construct (none today, but the rule is cheap to keep).
        pattern = re.compile(r"--break-system-packages")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertEqual(
            hits,
            [],
            f"--break-system-packages must not appear in shipping CLI source:\n{_format_hits(hits)}",
        )


class SwiftForbiddenPatternTests(unittest.TestCase):
    """Patterns that must never appear in shipping Swift source under
    ``TeslaCam/``.

    Each rule matches a sacred-rule reason. If a pattern legitimately
    needs to come back, update the rule in the same commit and explain
    why in the commit message.
    """

    def test_print_is_never_used_in_shipping_swift(self):
        # Justification: G5 logging discipline — the macOS app routes
        # every diagnostic through DebugLogSink (Logger with .private
        # message redaction). A bare `print(` in shipping Swift would
        # leak user-controlled paths to the unified log without
        # redaction. Currently zero hits; lock that.
        pattern = re.compile(r"\bprint\(")
        hits = _grep_lines(pattern, _shipping_swift_files())
        self.assertEqual(
            hits,
            [],
            f"print( must not appear in shipping Swift source — use DebugLogSink instead:\n{_format_hits(hits)}",
        )

    def test_sentry_is_never_referenced_in_shipping_swift(self):
        # Justification: sacred rule 7 — no Sentry, no analytics, no
        # external crash telemetry. The repo CLAUDE.md overrides the
        # global Sentry MCP guidance for this project; diagnostics
        # stay local via the in-app Show Log surface.
        pattern = re.compile(r"\bSentry\b")
        hits = _grep_lines(pattern, _shipping_swift_files())
        self.assertEqual(
            hits,
            [],
            f"Sentry references must not appear in shipping Swift source:\n{_format_hits(hits)}",
        )

    def test_legacy_is_never_referenced_in_shipping_swift(self):
        # Justification: sacred rule 5 — `_legacy/` and
        # `teslacam_legacy_macos.sh` are reference only. Anything in
        # shipping code that imports or path-references `_legacy/`
        # is a contract violation per H6 audit
        # (docs/improvement/hygiene-audit-2026-05-09.md).
        pattern = re.compile(r"_legacy(?:/|\\\\)")
        hits = _grep_lines(pattern, _shipping_swift_files())
        self.assertEqual(
            hits,
            [],
            f"_legacy/ references must not appear in shipping Swift source:\n{_format_hits(hits)}",
        )

    def test_ipad_target_does_not_support_portrait_orientation(self):
        # Justification: the iPad UI is a dense fixed CCTV-style
        # workspace. Portrait/narrow stacked layouts caused overlap
        # and unusable controls, so the iPad app must stay landscape.
        text = XCODE_PROJECT_FILE.read_text(encoding="utf-8")
        orientation_lines = [
            line.strip()
            for line in text.splitlines()
            if "INFOPLIST_KEY_UISupportedInterfaceOrientations" in line
        ]
        self.assertTrue(orientation_lines, "expected supported-orientation build settings in project file")
        portrait_lines = [line for line in orientation_lines if "UIInterfaceOrientationPortrait" in line]
        self.assertEqual(
            portrait_lines,
            [],
            "iPad build settings must not allow portrait orientation:\n" + "\n".join(portrait_lines),
        )

    def test_ipad_dashboard_has_no_static_top_app_title(self):
        # Justification: the iPad dashboard uses the footage grid as
        # the app identity. A static top title wastes vertical space.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        self.assertNotIn("TeslaCam CCTV", source)

    def test_ipad_inspector_is_fixed_not_scrolling_or_graph_heavy(self):
        # Justification: the loaded iPad workspace is a CCTV player.
        # The right inspector must stay fixed and focused on useful
        # telemetry/export controls, not duplicate event labels or
        # graph widgets that force scrolling.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadTelemetryRail")
        end = source.index("private struct TelemetryGrid")
        inspector_source = source[start:end]
        self.assertNotIn("ScrollView", inspector_source)
        self.assertNotIn("TelemetryEventLanes", inspector_source)
        self.assertNotIn("RouteMiniMapView", inspector_source)
        self.assertIn(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)", inspector_source)

    def test_ipad_timeline_track_has_enough_vertical_room(self):
        # Justification: the timeline track internally offsets its
        # lane/handles. Its external frame must be tall enough so it
        # cannot overlap the preset row below.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("TimelineSelectionTrack(")
        end = source.index("HStack(spacing: TeslaCamTheme.Spacing.s) {", start)
        timeline_source = source[start:end]
        self.assertIn(".frame(height: 56)", timeline_source)

    def test_timeline_track_surfaces_event_markers_for_scrubbing(self):
        # Justification: the seeker must give incident anchors while
        # scrubbing instead of being an undifferentiated bar. Keep this
        # bounded and visual-only so it does not affect playback logic.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct TimelineSelectionTrack")
        end = source.index("private struct TimelineGapBand", start)
        timeline_source = source[start:end]
        self.assertIn("let eventMarkers: [TelemetryEventMarker]", timeline_source)
        self.assertIn("let eventMarkerOffsetSeconds: Double", timeline_source)
        self.assertIn("eventMarkers.prefix(120)", timeline_source)
        self.assertIn("markerColor(for: marker.kind)", timeline_source)
        self.assertIn("allowsHitTesting(false)", timeline_source)

    def test_export_action_label_uses_effective_preset(self):
        # Justification: if overlays, reports, privacy masking, or
        # camera cuts require rendered video, the action label must not
        # still claim an original-track passthrough export.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        matches = re.findall(r'private var exportButtonTitle: String \{\s*"Export"', source)
        self.assertEqual(len(matches), 2)
        self.assertNotIn("state.exportPreset == .originalTracksMOV ? \"Export Original Tracks\"", source)
        self.assertNotIn("\"Export Original Tracks\"", source)

    def test_ipad_export_panel_avoids_system_pill_controls(self):
        # Justification: export controls sit in the visible iPad
        # inspector. They should use the app's 10px chip controls, not
        # system switches or segmented pills.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadExportOptionsPanel")
        end = source.index("#endif", start)
        export_source = source[start:end]
        self.assertNotIn("Toggle(", export_source)
        self.assertNotIn(".pickerStyle(.segmented)", export_source)

    def test_ipad_export_panel_uses_dense_side_controls(self):
        # Justification: the iPad side rail should not contain one
        # large button per row. Export controls need grouped dense
        # glass chips plus useful status content in the remaining
        # space.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadExportOptionsPanel")
        end = source.index("#endif", start)
        export_source = source[start:end]
        self.assertIn("InspectorControlGrid", export_source)
        self.assertIn("InspectorCameraGrid", export_source)
        self.assertIn("IPadExportStatusPanel", source)
        self.assertNotIn("OptionChip", export_source)
        self.assertLessEqual(export_source.count("CommandChip("), 1)

    def test_ipad_export_chips_are_compact_inline_controls(self):
        # Justification: the export panel must not look like a grid of
        # large button tiles. Chips should be short inline controls with
        # tight spacing so the side rail stays useful.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadExportOptionsPanel")
        end = source.index("#endif", start)
        export_source = source[start:end]
        self.assertIn("VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs)", export_source)
        self.assertIn(".padding(TeslaCamTheme.Spacing.s)", export_source)
        self.assertIn("GridItem(.flexible(), spacing: TeslaCamTheme.Spacing.xs)", export_source)
        self.assertIn("HStack(alignment: .center, spacing: TeslaCamTheme.Spacing.tightGap)", export_source)
        self.assertIn(".frame(height: TeslaCamTheme.Metrics.compactControlHeight)", export_source)
        self.assertNotIn(".frame(minHeight: 44)", export_source)

    def test_ipad_inspector_typography_uses_theme_fonts(self):
        # Justification: tiny one-off system fonts made the iPad
        # inspector inconsistent and hard to scan. Dense controls must
        # still use named readable type roles from the theme.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadExportStatusPanel")
        end = source.index("#endif", start)
        inspector_controls = source[start:end]
        self.assertNotIn(".font(.system(size:", inspector_controls)
        self.assertIn("TeslaCamTheme.Typography.metricValue", source)
        self.assertIn("TeslaCamTheme.Typography.miniMetricValue", inspector_controls)
        self.assertIn("TeslaCamTheme.Typography.inspectorChip", inspector_controls)
        self.assertIn("TeslaCamTheme.Typography.inspectorSymbol", inspector_controls)

    def test_ipad_map_page_uses_mapkit_route_view(self):
        # Justification: the iPad Map workspace should be a real MapKit
        # route viewer, not the lightweight SwiftUI Map stub. We need a
        # native MKMapView so route overlays, event annotations, and fit
        # behavior stay controllable in the dense dashboard.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadMapPage")
        end = source.index("private struct CameraTrackStrip", start)
        map_source = source[start:end]
        self.assertIn("IPadMapKitRouteView", map_source)
        self.assertIn("MKMapView", map_source)
        self.assertIn("MKPolylineRenderer", map_source)
        self.assertIn("MapEventAnnotation", map_source)
        self.assertNotIn("Map(position:", map_source)
        self.assertNotIn("MapPolyline(", map_source)

    def test_ipad_dashboard_tracks_dark_material_reference(self):
        # Justification: the iPad dashboard design target is a dark CCTV
        # workspace with Apple-material controls and a dominant footage
        # stage. Keep this guarded so it does not drift back to beige.
        content = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        utils = (SWIFT_SHIPPING_ROOT / "Utils.swift").read_text(encoding="utf-8")
        self.assertIn("preferredTeslaCamColorScheme()", content)
        self.assertIn("IPadStageTelemetryOverlay", content)
        self.assertIn("DemoVideoWallPlaceholder", content)
        self.assertIn("videoWallAspectRatio", content)
        self.assertIn("currentPreviewNaturalSizes", content)
        self.assertIn("Color(red: 0.045, green: 0.047, blue: 0.055)", utils)
        self.assertIn("Color.white.opacity(0.94)", utils)
        self.assertIn("environment(\\.colorScheme, .dark)", utils)
        self.assertNotIn("Color(red: 0.965, green: 0.955, blue: 0.935)", utils)
        self.assertNotIn("DemoRoadSceneView", content)
        self.assertNotIn("mountainLayer", content)

    def test_ipad_map_uses_dark_style(self):
        # Justification: Map must not flash a light rectangle inside the
        # dark CCTV dashboard.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadMapKitRouteView")
        end = source.index("private final class MapEventAnnotation", start)
        map_source = source[start:end]
        self.assertIn("overrideUserInterfaceStyle = .dark", map_source)
        self.assertIn("mapType = .mutedStandard", map_source)
        self.assertIn("UIColor(red: 0.045, green: 0.047, blue: 0.055", map_source)
        self.assertNotIn("overrideUserInterfaceStyle = .light", map_source)

    def test_ipad_scope_bar_has_no_outer_backdrop(self):
        # Justification: Browse/Map are already glass controls. A second
        # rounded rail behind them reads as an unnecessary extra shape.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct ScopeBar")
        end = source.index("private struct IPadLoadedScreen", start)
        scope_source = source[start:end]
        self.assertNotIn(".glassSurface(role: .rail", scope_source)
        self.assertNotIn(".padding(2)", scope_source)
        self.assertNotIn("GlassEffectGroup", scope_source)

    def test_ipad_panel_headers_are_single_line_without_subtitles(self):
        # Justification: section subtitles like "3 shown", "Live HUD",
        # and "HUD · output · queue" add noise in the dense CCTV
        # workspace. Panel headers should be one compact label row.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct PanelHeader")
        end = source.index("private struct MetricTile", start)
        panel_header_source = source[start:end]
        self.assertNotIn("detail", panel_header_source)
        self.assertNotIn("VStack(alignment: .leading", panel_header_source)
        self.assertNotIn("monoSmall", panel_header_source)
        self.assertNotRegex(source, r"PanelHeader\(\s*\n(?:[^\n]*\n){0,5}\s*detail\s*:")

    def test_ipad_video_stage_has_no_duplicate_bottom_hud_text(self):
        # Justification: speed/camera stats belong on the video wall
        # or the exported overlay. A second text strip below the video
        # wastes space and duplicates the telemetry.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadVideoStage")
        end = source.index("private struct IPadStageTelemetryOverlay", start)
        ipad_video_stage = source[start:end]
        self.assertNotIn("statusText", ipad_video_stage)
        self.assertNotIn("playbackUI.telemetryText", ipad_video_stage)
        self.assertNotIn("ForEach(state.camerasDetected", ipad_video_stage)

    def test_ipad_video_stage_telemetry_is_bottom_landscape_hud(self):
        # Justification: the iPad video wall should read like a CCTV
        # player. Telemetry belongs as a compact horizontal HUD at the
        # bottom of the footage, not as a tall overlay blocking a camera.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        stage_start = source.index("private struct IPadVideoStage")
        stage_end = source.index("private struct IPadStageTelemetryOverlay", stage_start)
        stage_source = source[stage_start:stage_end]
        overlay_start = stage_end
        overlay_end = source.index("private struct StageTelemetryMetric", overlay_start)
        overlay_source = source[overlay_start:overlay_end]

        self.assertIn("alignment: .bottom", stage_source)
        self.assertNotIn("alignment: .topLeading", stage_source)
        self.assertIn("HStack(spacing:", overlay_source)
        self.assertNotIn("VStack(spacing:", overlay_source)
        self.assertIn("StageTelemetryMetric(value: model.speedText", overlay_source)
        self.assertIn("StageTelemetryMetric(value: model.autopilot", overlay_source)

    def test_ipad_timeline_range_includes_30m_chip(self):
        # Justification: common one-off exports need a 30 minute quick
        # range beside the shorter presets so the bottom control row uses
        # its grid space without adding bigger buttons.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct IPadTimelineDock")
        end = source.index("private struct IPadRangeOptionsPanel", start)
        timeline_source = source[start:end]
        self.assertIn('Label("30m", systemImage:', timeline_source)
        self.assertIn('state.setRecentRange(minutes: 30)', timeline_source)
        self.assertIn('accessibilityIdentifier("range-last-30m")', timeline_source)

    def test_ipad_demo_wall_uses_camera_aspects_without_stretching(self):
        # Justification: demo mode is the design surface. Its camera wall
        # must respect camera aspect classes instead of stretching cameras
        # into arbitrary tall cells.
        source = (SWIFT_SHIPPING_ROOT / "ContentView.swift").read_text(encoding="utf-8")
        start = source.index("private struct DemoVideoWallPlaceholder")
        end = source.index("private struct DemoVideoWallTile", start)
        wall_source = source[start:end]
        self.assertIn("effectiveNaturalSizes", wall_source)
        self.assertIn("normalizedAspectRatio", wall_source)
        self.assertIn("16.0 / 9.0", wall_source)
        self.assertIn("4.0 / 3.0", wall_source)
        self.assertNotIn("LazyVGrid", wall_source)

    def test_metal_preview_grid_uses_known_camera_natural_sizes(self):
        # Justification: real preview should size HW4/HW3 grid cells from
        # clip dimensions when available. Otherwise 16:9 HW4 footage can
        # be placed inside a stale 4:3 preview grid.
        metal = (SWIFT_SHIPPING_ROOT / "MetalRenderer.swift").read_text(encoding="utf-8")
        ipad_view = (SWIFT_SHIPPING_ROOT / "MetalPlayerView_iPad.swift").read_text(encoding="utf-8")
        mac_view = (SWIFT_SHIPPING_ROOT / "MetalPlayerView.swift").read_text(encoding="utf-8")
        self.assertIn("var naturalSizes: [Camera: CGSize]", metal)
        self.assertIn("naturalSizes: naturalSizes", metal)
        self.assertIn("var naturalSizes: [Camera: CGSize]", ipad_view)
        self.assertIn("var naturalSizes: [Camera: CGSize]", mac_view)


class TestSurfaceTests(unittest.TestCase):
    """Sanity checks on the test surface itself.

    These guard against the tripwire pattern silently passing because
    the file walk found nothing — e.g. if the path constants drift to
    point at an empty directory.
    """

    def test_shipping_root_exists_and_has_python_files(self):
        self.assertTrue(SHIPPING_ROOT.is_dir(), f"{SHIPPING_ROOT} must be a directory")
        files = list(_shipping_python_files())
        self.assertGreaterEqual(len(files), 5, "expected at least a handful of .py files under teslacam_cli/")

    def test_swift_shipping_root_exists_and_has_swift_files(self):
        self.assertTrue(SWIFT_SHIPPING_ROOT.is_dir(), f"{SWIFT_SHIPPING_ROOT} must be a directory")
        files = list(_shipping_swift_files())
        self.assertGreaterEqual(len(files), 5, "expected at least a handful of .swift files under TeslaCam/")

    def test_grep_helper_actually_finds_real_lines(self):
        # If `_grep_lines` quietly returns [] for everything, the
        # forbidden-pattern tests would pass vacuously. Pin one
        # known-present token (the relative-import form used across
        # the shipping CLI) to prove the walker reads files for real.
        pattern = re.compile(r"^from \.")
        hits = _grep_lines(pattern, _shipping_python_files())
        self.assertGreater(
            len(hits),
            0,
            "_grep_lines must surface real matches; failing here means the walker is broken",
        )


if __name__ == "__main__":
    unittest.main()
