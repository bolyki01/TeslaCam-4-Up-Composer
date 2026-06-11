import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import MapKit
#endif

struct ContentView: View {
  @EnvironmentObject var state: AppState
  @State private var isDropTarget = false

  var body: some View {
    ZStack {
      TeslaCamSceneBackground()

      Group {
        if state.isIndexing {
          IndexingScreen(state: state)
        } else if state.clipSets.isEmpty {
          OnboardingScreen(state: state)
        } else {
          loadedScreen
        }
      }
      .disabled(state.exporter.isExporting)

      if let job = state.exporter.currentJob, state.exporter.isExporting || state.exporter.isStatusPresented {
        ExportOverlayCard(state: state, job: job)
      }
    }
    #if os(macOS)
    .frame(minWidth: 1100, minHeight: 760)
    #endif
    .preferredTeslaCamColorScheme()
    .onAppear { state.onAppear() }
    .alert("Error", isPresented: $state.showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(state.errorMessage)
    }
    .sheet(isPresented: $state.isDuplicateResolverPresented) {
      DuplicateResolverSheet(state: state)
    }
    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleFileDrop(providers:))
    #if os(iOS)
    .fileImporter(
      isPresented: $state.isFileImporterPresented,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        state.indexSources(urls)
      case .failure:
        break
      }
    }
    #endif
  }

  private var loadedScreen: some View {
#if os(iOS)
    IPadLoadedScreen(state: state, playbackUI: state.playbackUI)
#else
    GeometryReader { proxy in
      VStack(spacing: 0) {
        LoadedStatusBar(state: state)

        ScrollView(.vertical, showsIndicators: false) {
          VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.cardGap) {
            PreviewPanelCard(
              state: state,
              playbackUI: state.playbackUI,
              maxAvailableHeight: loadedPreviewMaxHeight(for: proxy.size.height)
            )

            TimelineExportCard(
              state: state,
              playback: state.playback,
              playbackUI: state.playbackUI,
              timelineMarkers: timelineMarkers,
              isSingleDayTimeline: isSingleDayTimeline
            )
          }
          .frame(maxWidth: loadedContentMaxWidth, alignment: .top)
          .padding(TeslaCamTheme.Metrics.contentPadding)
          .frame(maxWidth: .infinity, alignment: .top)
        }
      }
    }
    .accessibilityIdentifier("loaded-screen")
#endif
  }

  private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
    guard !state.exporter.isExporting else { return false }
    let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    guard !fileProviders.isEmpty else { return false }

    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []

    for provider in fileProviders {
      group.enter()
      provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
        defer { group.leave() }
        guard let data,
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              url.isFileURL else { return }
        lock.lock()
        urls.append(url)
        lock.unlock()
      }
    }

    group.notify(queue: .main) {
      guard !urls.isEmpty else { return }
      state.ingestDroppedURLs(urls)
    }
    return true
  }

  private var timelineMarkers: [Date] {
    guard let min = state.minDate, let max = state.maxDate else { return [] }
    let interval = max.timeIntervalSince(min)
    guard interval > 0 else { return [] }
    return [0.2, 0.4, 0.6, 0.8].map { fraction in
      min.addingTimeInterval(interval * fraction)
    }
  }

  private var isSingleDayTimeline: Bool {
    guard let min = state.minDate, let max = state.maxDate else { return true }
    return Calendar.current.isDate(min, inSameDayAs: max)
  }

  private var loadedContentMaxWidth: CGFloat {
    switch state.camerasDetected.count {
    case 0...4:
      return 860
    case 5...6:
      return 1080
    default:
      return 1320
    }
  }

  private func loadedPreviewMaxHeight(for totalHeight: CGFloat) -> CGFloat {
    // Keep the controls reachable without scrolling.
    let reserved: CGFloat = state.camerasDetected.count <= 4 ? 420 : 460
    return max(240, totalHeight - reserved)
  }
}

#if os(iOS)
private enum IPadWorkspaceMode: String, CaseIterable, Identifiable {
  case browse
  case map

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .browse:
      return "Browse"
    case .map:
      return "Map"
    }
  }
}

private struct GridPanel<Content: View>: View {
  var role: SurfaceRole = .panel
  var padding: CGFloat = TeslaCamTheme.Metrics.cardPaddingCompact
  var radius: CGFloat = TeslaCamTheme.Metrics.cardCorner
  @ViewBuilder var content: () -> Content

  var body: some View {
    GlassEffectGroup(spacing: TeslaCamTheme.Spacing.m) {
      content()
        .padding(padding)
        .glassSurface(role: role, radius: radius)
    }
  }
}

private struct PanelHeader: View {
  let title: String
  var systemImage: String? = nil

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
      }
      Text(title.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
      Spacer(minLength: 0)
    }
  }
}

private struct MetricTile: View {
  let title: String
  let value: String
  var warning: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
      Text(title.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      Text(value)
        .font(TeslaCamTheme.Typography.metricValue)
        .foregroundStyle(warning ? TeslaCamTheme.Colors.gapAccent : TeslaCamTheme.Colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(TeslaCamTheme.Spacing.m)
    .glassSurface(role: warning ? .selected : .control, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}

private struct CommandChip: View {
  let title: String
  var systemImage: String? = nil
  var role: SurfaceRole = .control
  var disabled: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      if let systemImage {
        Label(title, systemImage: systemImage)
      } else {
        Text(title)
      }
    }
    .compactButtonStyle(role: role, size: .command)
    .disabled(disabled)
  }
}

private struct IconChip: View {
  let systemImage: String
  var role: SurfaceRole = .control
  var disabled: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
    }
    .compactButtonStyle(role: role, size: .icon)
    .disabled(disabled)
  }
}

private struct ScopeBar<Option: Hashable>: View {
  let options: [Option]
  @Binding var selection: Option
  let label: (Option) -> String

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Button {
          selection = option
        } label: {
          Text(label(option))
        }
        .compactButtonStyle(role: selection == option ? .selected : .control, size: .chip)
      }
    }
  }
}

private struct IPadLoadedScreen: View {
  @ObservedObject var state: AppState
  @ObservedObject var playbackUI: PlaybackUIState
  @State private var workspaceMode: IPadWorkspaceMode = .browse

  var body: some View {
    GeometryReader { proxy in
      let metrics = IPadGridMetrics(containerWidth: max(320, proxy.size.width - 16))
      if proxy.size.height > proxy.size.width {
        IPadLandscapeLockScreen()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(metrics.outerPadding)
      } else {
        HStack(alignment: .top, spacing: metrics.gutter) {
          IPadEventRail(state: state)
            .frame(width: metrics.eventRailWidth)
            .frame(maxHeight: .infinity)

          stage(
            maxHeight: max(360, proxy.size.height - metrics.outerPadding * 2),
            centerWidth: metrics.centerWidth
          )
            .frame(width: metrics.centerWidth)

          IPadTelemetryRail(state: state)
            .frame(width: metrics.inspectorWidth)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(metrics.outerPadding)
      }
    }
    .accessibilityIdentifier("loaded-screen")
  }

  private func stage(maxHeight: CGFloat, centerWidth: CGFloat) -> some View {
    GridPanel(padding: TeslaCamTheme.Spacing.m, radius: TeslaCamTheme.Metrics.cardCorner) {
      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
        HStack(spacing: TeslaCamTheme.Spacing.s) {
          ScopeBar(
            options: IPadWorkspaceMode.allCases,
            selection: $workspaceMode,
            label: { $0.displayName }
          )
          .frame(width: 176, alignment: .leading)

          Spacer(minLength: 0)

          IconChip(systemImage: "folder") {
            state.chooseFolder()
          }
          .accessibilityLabel("Choose Folder")
        }

        stageBody(maxHeight: maxHeight, centerWidth: centerWidth)
      }
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  @ViewBuilder
  private func stageBody(maxHeight: CGFloat, centerWidth: CGFloat) -> some View {
    if workspaceMode == .map {
      IPadMapPage(state: state)
        .frame(maxWidth: .infinity)
        .frame(height: max(320, maxHeight - 48))
    } else {
      IPadVideoStage(
        state: state,
        playbackUI: playbackUI,
        height: videoHeight(for: maxHeight, width: centerWidth),
        naturalSizes: previewNaturalSizes
      )

      IPadTimelineDock(
        state: state,
        playback: state.playback,
        playbackUI: playbackUI
      )
    }
  }

  private func videoHeight(for maxHeight: CGFloat, width: CGFloat) -> CGFloat {
    let contentWidth = max(320, width - TeslaCamTheme.Spacing.m * 2)
    let idealHeight = contentWidth / videoWallAspectRatio
    let reservedForControls: CGFloat = 156
    let usableHeight = max(220, maxHeight - reservedForControls)
    let expandedHeight = max(360, idealHeight * 1.35)
    return max(260, min(usableHeight, expandedHeight))
  }

  private var videoWallAspectRatio: CGFloat {
    let detected = Set(state.camerasDetected)
    let plan = CameraLayoutPlan.build(
      requestedProfile: state.layoutRequest,
      detectedCameras: detected,
      enabledCameras: detected,
      naturalSizes: previewNaturalSizes
    )
    guard plan.canvasSize.height > 0 else { return 16.0 / 9.0 }
    return max(1, plan.canvasSize.width / plan.canvasSize.height)
  }

  private var previewNaturalSizes: [Camera: CGSize] {
    let actual = state.currentPreviewNaturalSizes
    if !actual.isEmpty {
      return actual
    }

    let detected = state.camerasDetected.isEmpty ? Camera.hw4SixCamOrder : state.camerasDetected
    let usesHW4 = state.layoutRequest == .sixcam || !Set(detected).isDisjoint(with: Set([.left, .right, .left_pillar, .right_pillar]))
    let fallback = usesHW4 ? CGSize(width: 1920, height: 1080) : CGSize(width: 1280, height: 960)
    return Dictionary(uniqueKeysWithValues: detected.map { ($0, fallback) })
  }
}

private struct IPadLandscapeLockScreen: View {
  var body: some View {
    GridPanel(role: .overlay, padding: TeslaCamTheme.Spacing.xxl, radius: TeslaCamTheme.Metrics.cardCorner) {
      VStack(spacing: TeslaCamTheme.Spacing.m) {
        Image(systemName: "rectangle.landscape.rotate")
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
        Text("Rotate iPad")
          .font(TeslaCamTheme.Typography.panelTitle)
          .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        Text("Dashboard view is landscape-only to keep CCTV controls fixed.")
          .font(TeslaCamTheme.Typography.bodySmall)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: 360)
    }
  }
}

private struct IPadVideoStage: View {
  @ObservedObject var state: AppState
  @ObservedObject var playbackUI: PlaybackUIState
  let height: CGFloat
  let naturalSizes: [Camera: CGSize]

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Rectangle()
          .fill(TeslaCamTheme.Colors.surface)
          .overlay(
            Group {
              if state.sourceURLs.isEmpty {
                DemoVideoWallPlaceholder(
                  cameras: state.activePreviewCameras,
                  layoutRequest: state.layoutRequest,
                  naturalSizes: naturalSizes
                )
              } else {
                MetalPlayerView(
                  playback: state.playback,
                  cameraOrder: state.activePreviewCameras,
                  layoutRequest: state.layoutRequest,
                  previewLayoutMode: state.previewLayoutMode,
                  focusedCamera: state.focusedCamera,
                  naturalSizes: naturalSizes
                )
              }
            }
            .clipped()
          )

        if !state.privacyMode, let telemetry = state.telemetryModel {
          IPadStageTelemetryOverlay(model: telemetry, speedUnit: state.exportOverlayOptions.speedUnit)
            .padding(.horizontal, TeslaCamTheme.Spacing.m)
            .padding(.bottom, TeslaCamTheme.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }

        if state.currentGapRange != nil {
          Text("No recording in this span")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
            .padding(.horizontal, TeslaCamTheme.Spacing.l)
            .padding(.vertical, TeslaCamTheme.Spacing.m)
            .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurfaceStrong, radius: TeslaCamTheme.Metrics.compactCorner)
        }
      }
      .frame(height: height)
      .clipped()
    }
    .clipShape(Rectangle())
    .overlay(
      Rectangle()
        .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
    )
  }

}

private struct IPadStageTelemetryOverlay: View {
  let model: TelemetryDisplayModel
  let speedUnit: TelemetrySpeedUnit

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      StageTelemetryMetric(value: model.speedText(unit: speedUnit).split(separator: " ").first.map(String.init) ?? "--", label: speedUnit.displayName)
      StageTelemetryMetric(value: model.acceleratorText, label: "Pedal")
      StageTelemetryMetric(value: model.steeringText.replacingOccurrences(of: " deg", with: "°"), label: "Steer")
      StageTelemetryMetric(value: model.gear, label: "Gear")
      StageTelemetryMetric(value: model.autopilot, label: "AP")
      StageTelemetryMetric(value: model.brakeApplied ? "On" : "Off", label: "Brake")
      StageTelemetryMetric(value: model.signalText, label: "Signal")
      StageTelemetryMetric(value: model.headingText.replacingOccurrences(of: " deg", with: "°"), label: "Head")
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.s)
    .padding(.vertical, TeslaCamTheme.Spacing.xs)
    .glassSurface(role: .overlay, radius: TeslaCamTheme.Metrics.cardCorner)
  }
}

private struct StageTelemetryMetric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(TeslaCamTheme.Typography.miniMetricValue)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(label.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(minWidth: 48, maxWidth: .infinity, alignment: .leading)
  }
}

private struct DemoVideoWallPlaceholder: View {
  let cameras: [Camera]
  let layoutRequest: CameraLayoutRequest
  let naturalSizes: [Camera: CGSize]

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let gap = TeslaCamTheme.Spacing.xs
      let columns = displayCameras.count > 4 ? 2 : 2
      let rows = max(1, Int(ceil(Double(max(displayCameras.count, 1)) / Double(columns))))
      let cellWidth = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
      let cellHeight = (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)

      ZStack {
        Rectangle().fill(Color.black.opacity(0.94))

        VStack(spacing: gap) {
          ForEach(0..<rows, id: \.self) { row in
            HStack(spacing: gap) {
              ForEach(0..<columns, id: \.self) { column in
                let index = row * columns + column
                if displayCameras.indices.contains(index) {
                  let camera = displayCameras[index]
                  DemoVideoWallTile(camera: camera)
                    .aspectRatio(normalizedAspectRatio(for: camera), contentMode: .fit)
                    .frame(width: cellWidth, height: cellHeight)
                } else {
                  Color.clear
                    .frame(width: cellWidth, height: cellHeight)
                }
              }
            }
          }
        }
      }
      .frame(width: size.width, height: size.height)
      .clipped()
    }
  }

  private var displayCameras: [Camera] {
    cameras.isEmpty ? Camera.hw3ClassicOrder : cameras
  }

  private var effectiveNaturalSizes: [Camera: CGSize] {
    var sizes = naturalSizes
    for camera in displayCameras where sizes[camera] == nil {
      sizes[camera] = defaultSize(for: camera)
    }
    return sizes
  }

  private func normalizedAspectRatio(for camera: Camera) -> CGFloat {
    let size = effectiveNaturalSizes[camera] ?? defaultSize(for: camera)
    let raw = size.height > 0 ? size.width / size.height : 16.0 / 9.0
    return raw > 1.45 ? 16.0 / 9.0 : 4.0 / 3.0
  }

  private func defaultSize(for _: Camera) -> CGSize {
    if usesHW4Layout {
      return CGSize(width: 1920, height: 1080)
    }
    return CGSize(width: 1280, height: 960)
  }

  private var usesHW4Layout: Bool {
    layoutRequest == .sixcam || !Set(displayCameras).isDisjoint(with: Set([.left, .right, .left_pillar, .right_pillar]))
  }
}

private struct DemoVideoWallTile: View {
  let camera: Camera

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color.black.opacity(0.72),
          Color(red: 0.11, green: 0.13, blue: 0.14),
          Color.black.opacity(0.84)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      VStack(alignment: .leading) {
        HStack {
          Image(systemName: "video")
          Text(camera.shortName.uppercased())
          Spacer()
          Text("DEMO")
        }
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(Color.white.opacity(0.62))

        Spacer()

        HStack(spacing: TeslaCamTheme.Spacing.xs) {
          ForEach(0..<18, id: \.self) { index in
            Rectangle()
              .fill(index % 5 == 0 ? TeslaCamTheme.Colors.accent.opacity(0.55) : Color.white.opacity(0.12))
              .frame(width: 2, height: CGFloat(10 + (index % 4) * 6))
          }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(0.42)

        Spacer()
      }
      .padding(TeslaCamTheme.Spacing.m)
    }
  }
}

private struct IPadTimelineDock: View {
  @ObservedObject var state: AppState
  @ObservedObject var playback: MultiCamPlaybackController
  @ObservedObject var playbackUI: PlaybackUIState

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
      HStack(spacing: TeslaCamTheme.Spacing.s) {
        Button {
          state.togglePlay()
        } label: {
          Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
        }
        .compactButtonStyle(role: .selected, size: .icon)
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        .accessibilityIdentifier("toggle-playback")

        Text("\(formatHMS(playbackUI.currentSeconds)) / \(formatHMS(state.totalDuration))")
          .font(TeslaCamTheme.Typography.monoDetail)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)

        Spacer(minLength: 0)

        Text(formatHMS(state.selectedTrimDuration))
          .font(TeslaCamTheme.Typography.monoDetail)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      }

      TimelineSelectionTrack(
        currentSeconds: Binding(
          get: { playbackUI.currentSeconds },
          set: { playbackUI.currentSeconds = $0 }
        ),
        selectedStartSeconds: $state.trimStartSeconds,
        selectedEndSeconds: $state.trimEndSeconds,
        gapRanges: state.timelineGapRanges,
        totalDuration: max(state.totalDuration, 1),
        onSeekStart: { state.beginSeek() },
        onSeekChange: { state.liveSeek(to: $0) },
        onSeekEnd: { state.endSeek() },
        onDragStart: { state.beginTrimDrag() },
        onDragChange: { start, end in state.updateTrimRange(startSeconds: start, endSeconds: end) },
        onDragEnd: { start, end in state.endTrimDrag(startSeconds: start, endSeconds: end) }
      )
      .frame(height: 56)

      HStack(spacing: TeslaCamTheme.Spacing.s) {
        Button("All") { state.setFullRange() }
          .compactButtonStyle(role: .control, size: .chip)
          .accessibilityIdentifier("range-whole-timeline")
        Button("1m") { state.setCurrentMinuteRange() }
          .compactButtonStyle(role: .control, size: .chip)
          .accessibilityIdentifier("range-current-minute")
        Button("5m") { state.setRecentRange(minutes: 5) }
          .compactButtonStyle(role: .control, size: .chip)
          .accessibilityIdentifier("range-last-5m")
        Button("15m") { state.setRecentRange(minutes: 15) }
          .compactButtonStyle(role: .control, size: .chip)
          .accessibilityIdentifier("range-last-15m")
        Button("30m") { state.setRecentRange(minutes: 30) }
          .compactButtonStyle(role: .control, size: .chip)
          .accessibilityIdentifier("range-last-30m")
        Spacer(minLength: 0)
      }
    }
    .padding(TeslaCamTheme.Spacing.s)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }

}

private struct IPadRangeOptionsPanel: View {
  @ObservedObject var state: AppState

  var body: some View {
    let minDate = state.minDate ?? Date()
    let maxDate = state.maxDate ?? Date()

    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      PanelHeader(
        title: "Range",
        systemImage: "timeline.selection"
      )

      RangeControlCard(title: "From") {
        DatePicker(
          "",
          selection: Binding(
            get: { state.selectedStart },
            set: { state.updateTrimStart(from: $0) }
          ),
          in: minDate...maxDate,
          displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
      }

      RangeControlCard(title: "To") {
        DatePicker(
          "",
          selection: Binding(
            get: { state.selectedEnd },
            set: { state.updateTrimEnd(from: $0) }
          ),
          in: minDate...maxDate,
          displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
      }

      RangeControlCard(title: "Preset") {
        Picker("", selection: $state.exportPreset) {
          ForEach(ExportPreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
        Text("Dupes")
          .font(TeslaCamTheme.Typography.label)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        Picker(
          "",
          selection: Binding(
            get: { state.duplicatePolicy },
            set: { state.updateDuplicatePolicy($0) }
          )
        ) {
          ForEach(DuplicateClipPolicy.allCases) { policy in
            Text(policy.displayName).tag(policy)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }
      .padding(TeslaCamTheme.Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassSurface(role: .control, radius: TeslaCamTheme.Metrics.compactCorner)

      CameraToggleRow(state: state)
    }
    .padding(TeslaCamTheme.Spacing.s)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }
}

private struct IPadMapPage: View {
  @ObservedObject var state: AppState
  @State private var fitToken = 0

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
      HStack {
        PanelHeader(
          title: "Map",
          systemImage: "map"
        )
        Spacer()
        CommandChip(title: "Fit", systemImage: "viewfinder", disabled: coordinates.isEmpty) {
          fitToken += 1
        }
      }

      if coordinates.isEmpty {
        VStack(spacing: TeslaCamTheme.Spacing.s) {
          Text("No GPS events")
            .font(TeslaCamTheme.Typography.body.weight(.semibold))
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          Text("This export has no located events.")
            .font(TeslaCamTheme.Typography.monoSmall)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
      } else {
        IPadMapKitRouteView(
          route: routePoints,
          events: eventsWithCoordinates,
          focusedEventID: state.currentEvent?.id,
          fitToken: fitToken,
          onSelectEvent: { event in
            state.jumpToEvent(event)
          }
        )
        .clipShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous)
            .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
        )
      }
    }
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }

  private var eventsWithCoordinates: [TeslaCamEventSummary] {
    guard !state.privacyMode else { return [] }
    return state.filteredEventSummaries.filter { $0.coordinate?.isUsable == true }
  }

  private var routePoints: [TelemetryRoutePoint] {
    state.privacyMode ? [] : state.telemetryRoute
  }

  private var coordinates: [TelemetryCoordinate] {
    let eventCoordinates = eventsWithCoordinates.compactMap(\.coordinate)
    let route = routePoints.map(\.coordinate)
    return eventCoordinates + route
  }
}

private struct IPadMapKitRouteView: UIViewRepresentable {
  let route: [TelemetryRoutePoint]
  let events: [TeslaCamEventSummary]
  let focusedEventID: TeslaCamEventSummary.ID?
  let fitToken: Int
  let onSelectEvent: (TeslaCamEventSummary) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> MKMapView {
    let mapView = MKMapView(frame: .zero)
    mapView.delegate = context.coordinator
    mapView.overrideUserInterfaceStyle = .dark
    mapView.mapType = .mutedStandard
    mapView.pointOfInterestFilter = .excludingAll
    mapView.showsCompass = true
    mapView.showsScale = true
    mapView.showsUserLocation = false
    mapView.isPitchEnabled = false
    mapView.isRotateEnabled = false
    mapView.backgroundColor = UIColor(red: 0.045, green: 0.047, blue: 0.055, alpha: 1)
    return mapView
  }

  func updateUIView(_ mapView: MKMapView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.sync(mapView)
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    var parent: IPadMapKitRouteView
    private var routeOverlay: MKPolyline?
    private var routeSignature = ""
    private var annotationSignature = ""
    private var lastFitToken: Int?
    private var lastFitRouteSignature = ""
    private var lastFocusedEventID: String?

    init(parent: IPadMapKitRouteView) {
      self.parent = parent
    }

    func sync(_ mapView: MKMapView) {
      syncRouteOverlay(in: mapView)
      syncAnnotations(in: mapView)
      fitIfNeeded(mapView)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      guard overlay is MKPolyline else {
        return MKOverlayRenderer(overlay: overlay)
      }
      let renderer = MKPolylineRenderer(overlay: overlay)
      renderer.strokeColor = UIColor(red: 0.24, green: 0.51, blue: 0.97, alpha: 0.92)
      renderer.lineWidth = CGFloat(TelemetryRouteStyle.lineWidth(
        latitudeDelta: mapView.region.span.latitudeDelta,
        longitudeDelta: mapView.region.span.longitudeDelta
      ))
      renderer.lineCap = .round
      renderer.lineJoin = .round
      return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let eventAnnotation = annotation as? MapEventAnnotation else { return nil }
      let reuseIdentifier = "map-event"
      let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier)
        ?? MKAnnotationView(annotation: eventAnnotation, reuseIdentifier: reuseIdentifier)
      view.annotation = eventAnnotation
      view.image = Self.markerImage(selected: eventAnnotation.event.id == parent.focusedEventID)
      view.centerOffset = CGPoint(x: 0, y: -10)
      view.canShowCallout = false
      view.displayPriority = .required
      view.accessibilityLabel = "\(eventAnnotation.event.reasonTitle), \(eventAnnotation.event.locationTitle)"
      return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      guard let annotation = view.annotation as? MapEventAnnotation else { return }
      parent.onSelectEvent(annotation.event)
      mapView.deselectAnnotation(annotation, animated: true)
    }

    private func syncRouteOverlay(in mapView: MKMapView) {
      let signature = routePathSignature(parent.route)
      guard signature != routeSignature else { return }
      if let routeOverlay {
        mapView.removeOverlay(routeOverlay)
      }
      routeSignature = signature
      let displayRoute = TelemetryRouteReplay.displaySamples(from: parent.route, maxPoints: 2_000)
      let coordinates = displayRoute.map { $0.coordinate.clLocation }
      guard coordinates.count > 1 else {
        routeOverlay = nil
        return
      }
      let overlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
      routeOverlay = overlay
      mapView.addOverlay(overlay)
    }

    private func syncAnnotations(in mapView: MKMapView) {
      let signature = eventAnnotationSignature(parent.events, focusedEventID: parent.focusedEventID)
      guard signature != annotationSignature else { return }
      let oldAnnotations = mapView.annotations.compactMap { $0 as? MapEventAnnotation }
      mapView.removeAnnotations(oldAnnotations)
      annotationSignature = signature
      let annotations = parent.events.compactMap { event in
        MapEventAnnotation(event: event)
      }
      mapView.addAnnotations(annotations)
    }

    private func fitIfNeeded(_ mapView: MKMapView) {
      let tokenChanged = lastFitToken != parent.fitToken
      let routeChanged = lastFitRouteSignature != routeSignature
      let focusChanged = lastFocusedEventID != parent.focusedEventID
      guard tokenChanged || routeChanged || focusChanged else { return }
      lastFitToken = parent.fitToken
      lastFitRouteSignature = routeSignature
      lastFocusedEventID = parent.focusedEventID

      if let focused = parent.events.first(where: { $0.id == parent.focusedEventID })?.coordinate {
        mapView.setRegion(Self.focusedRegion(for: focused.clLocation), animated: true)
        return
      }

      let allCoordinates = parent.route.map(\.coordinate) + parent.events.compactMap(\.coordinate)
      Self.fit(allCoordinates.map(\.clLocation), in: mapView)
    }

    private func routePathSignature(_ route: [TelemetryRoutePoint]) -> String {
      TelemetryRouteSignature.route(route)
    }

    private func eventAnnotationSignature(_ events: [TeslaCamEventSummary], focusedEventID: String?) -> String {
      events.map { event in
        let lat = event.coordinate?.latitude.roundedForMapSignature ?? 0
        let lon = event.coordinate?.longitude.roundedForMapSignature ?? 0
        return "\(event.id):\(lat),\(lon):\(focusedEventID == event.id)"
      }
      .joined(separator: ";")
    }

    private static func fit(_ coordinates: [CLLocationCoordinate2D], in mapView: MKMapView) {
      guard let first = coordinates.first else { return }
      guard coordinates.count > 1 else {
        mapView.setRegion(focusedRegion(for: first), animated: true)
        return
      }

      var rect = MKMapRect.null
      for coordinate in coordinates {
        let point = MKMapPoint(coordinate)
        let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
        rect = rect.isNull ? pointRect : rect.union(pointRect)
      }
      guard !rect.isNull else { return }
      mapView.setVisibleMapRect(
        rect,
        edgePadding: UIEdgeInsets(top: 44, left: 44, bottom: 44, right: 44),
        animated: true
      )
    }

    private static func focusedRegion(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
      MKCoordinateRegion(
        center: coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
      )
    }

    private static func markerImage(selected: Bool) -> UIImage {
      let side: CGFloat = selected ? 22 : 18
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
      return renderer.image { context in
        let rect = CGRect(x: 1.5, y: 1.5, width: side - 3, height: side - 3)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)
        let fill = selected
          ? UIColor(red: 0.93, green: 0.38, blue: 0.28, alpha: 0.96)
          : UIColor(red: 0.24, green: 0.51, blue: 0.97, alpha: 0.94)
        fill.setFill()
        path.fill()
        UIColor.white.withAlphaComponent(selected ? 0.9 : 0.55).setStroke()
        path.lineWidth = selected ? 2 : 1.5
        path.stroke()
        context.cgContext.setFillColor(UIColor.white.withAlphaComponent(selected ? 0.92 : 0.72).cgColor)
        context.cgContext.fill(CGRect(x: side / 2 - 2, y: side / 2 - 2, width: 4, height: 4))
      }
    }
  }
}

private final class MapEventAnnotation: NSObject, MKAnnotation {
  let event: TeslaCamEventSummary
  let coordinate: CLLocationCoordinate2D

  init?(event: TeslaCamEventSummary) {
    guard let coordinate = event.coordinate, coordinate.isUsable else { return nil }
    self.event = event
    self.coordinate = coordinate.clLocation
  }

  var title: String? { event.reasonTitle }
  var subtitle: String? { event.locationTitle }
}

private extension TelemetryCoordinate {
  var clLocation: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

private extension Double {
  var roundedForMapSignature: Double {
    (self * 100_000).rounded() / 100_000
  }
}

private struct CameraTrackStrip: View {
  let track: CameraTrack
  let duration: Double
  let currentSeconds: Double

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      Image(systemName: "timeline.selection")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)

      Canvas { context, size in
        let baseline = size.height * 0.5
        var base = Path()
        base.move(to: CGPoint(x: 0, y: baseline))
        base.addLine(to: CGPoint(x: size.width, y: baseline))
        context.stroke(base, with: .color(TeslaCamTheme.Colors.stroke), lineWidth: 2)

        for cut in track.normalized.keyframes {
          let x = CGFloat(min(1, max(0, cut.seconds / duration))) * size.width
          let rect = CGRect(x: x - 3, y: 8, width: 6, height: size.height - 16)
          context.fill(Path(rect), with: .color(TeslaCamTheme.Colors.accent))
        }

        let nowX = CGFloat(min(1, max(0, currentSeconds / duration))) * size.width
        var now = Path()
        now.move(to: CGPoint(x: nowX, y: 4))
        now.addLine(to: CGPoint(x: nowX, y: size.height - 4))
        context.stroke(now, with: .color(.white.opacity(0.75)), lineWidth: 1)
      }

      Text(track.keyframes.isEmpty ? "No cuts" : "\(track.keyframes.count) cuts")
        .font(TeslaCamTheme.Typography.monoSmall)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        .frame(width: 72, alignment: .trailing)
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.l)
  }
}

private struct IPadEventRail: View {
  @ObservedObject var state: AppState

  var body: some View {
    GridPanel(role: .rail) {
      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
        HStack {
          PanelHeader(
            title: "Events",
            systemImage: "film.stack"
          )
          IconChip(systemImage: "arrow.clockwise", disabled: !state.canReloadSources) {
            state.reloadSources()
          }
        }

        Text(sourceTitle)
          .font(TeslaCamTheme.Typography.monoSmall)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          .lineLimit(2)
          .padding(TeslaCamTheme.Spacing.m)
          .frame(maxWidth: .infinity, alignment: .leading)
          .glassSurface(role: .control, radius: TeslaCamTheme.Metrics.compactCorner)

        HStack(spacing: TeslaCamTheme.Spacing.s) {
          Image(systemName: "magnifyingglass")
            .font(TeslaCamTheme.Typography.label)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          TextField("Search", text: $state.eventSearchText)
            .textFieldStyle(.plain)
            .font(TeslaCamTheme.Typography.bodySmall)
        }
        .padding(.horizontal, TeslaCamTheme.Spacing.m)
        .frame(height: 36)
        .glassSurface(role: .control, radius: TeslaCamTheme.Metrics.compactCorner, interactive: true)

        HStack(spacing: TeslaCamTheme.Spacing.s) {
          Picker("Sort", selection: $state.eventSortMode) {
            ForEach(TeslaCamEventSortMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity)

          Picker("Type", selection: Binding(
            get: { state.eventReasonFilter == "all" ? "All" : state.eventReasonFilter },
            set: { state.eventReasonFilter = $0 == "All" ? "all" : $0 }
          )) {
            ForEach(state.eventReasonOptions, id: \.self) { reason in
              Text(reason).tag(reason)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity)
        }
        .controlSize(.small)

        ScrollView(.vertical, showsIndicators: false) {
          LazyVStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
            ForEach(state.filteredEventSummaries) { event in
              IPadEventRow(
                event: event,
                active: state.currentEvent?.id == event.id
              ) {
                state.jumpToEvent(event)
              }
            }
          }
        }
      }
    }
  }

  private var sourceTitle: String {
    if state.sourceURLs.count > 1 {
      return "\(state.sourceURLs.count) sources"
    }
    return state.sourceURLs.first?.lastPathComponent ?? "No source"
  }
}

private struct IPadEventRow: View {
  let event: TeslaCamEventSummary
  let active: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: TeslaCamTheme.Spacing.s) {
        EventThumbnailView(url: event.thumbnailURL)
          .frame(width: 56, height: 42)
          .clipShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous))

        VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
          Text(TeslaCamFormatters.timelineSameDay.string(from: event.timestamp))
            .font(TeslaCamTheme.Typography.monoSmall)
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          Text(event.locationTitle)
            .font(TeslaCamTheme.Typography.label)
            .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
            .lineLimit(1)
          Text(event.reasonTitle)
            .font(.system(size: 11))
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(TeslaCamTheme.Spacing.s)
      .glassSurface(role: active ? .selected : .control, radius: TeslaCamTheme.Metrics.compactCorner, interactive: true)
    }
    .buttonStyle(.plain)
  }
}

private struct EventThumbnailView: View {
  let url: URL?

  var body: some View {
    Group {
      if let url, let image = UIImage(contentsOfFile: url.path) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Rectangle()
          .fill(TeslaCamTheme.Colors.surfaceElevated)
          .overlay(
            Image(systemName: "video")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          )
      }
    }
  }
}

private struct IPadLayoutToolbar: View {
  @ObservedObject var state: AppState

  var body: some View {
    GridPanel {
      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
        PanelHeader(
          title: "Playback",
          systemImage: "slider.horizontal.3"
        )

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
          Picker("View", selection: $state.previewLayoutMode) {
            ForEach(PreviewLayoutMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)

          Picker("Grid", selection: $state.layoutRequest) {
            ForEach(CameraLayoutRequest.allCases) { request in
              Text(request.displayName).tag(request)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)

          Picker("Focus", selection: Binding(
            get: { state.focusedCamera ?? state.activePreviewCameras.first ?? .front },
            set: { state.setFocusedCamera($0) }
          )) {
            ForEach(state.camerasDetected, id: \.self) { camera in
              Text(camera.shortName).tag(camera)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)

          Picker("Rate", selection: Binding(
            get: { state.playbackRate },
            set: { state.setPlaybackRate($0) }
          )) {
            ForEach(AppState.allowedPlaybackRates, id: \.self) { rate in
              Text(rateText(rate)).tag(rate)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)

        HStack(spacing: TeslaCamTheme.Spacing.s) {
          HStack(spacing: TeslaCamTheme.Spacing.xs) {
            Image(systemName: state.privacyMode ? "eye.slash" : "eye")
              .font(TeslaCamTheme.Typography.label)
              .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
            Toggle("Privacy", isOn: $state.privacyMode)
              .labelsHidden()
              .toggleStyle(.switch)
              .fixedSize()
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Privacy")

          CommandChip(title: "Cut", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            state.addCameraTrackCut()
          }

          IconChip(systemImage: "timeline.selection", disabled: state.cameraTrack.isEmpty) {
            state.clearCameraTrack()
          }

          Text("\(state.cameraTrack.keyframes.count) cuts")
            .font(TeslaCamTheme.Typography.monoSmall)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)

          Spacer(minLength: 0)
        }
        .controlSize(.small)
      }
    }
  }

  private func rateText(_ rate: Double) -> String {
    rate == 1.0 ? "1x" : String(format: "%.2gx", rate)
  }
}

private struct IPadTelemetryRail: View {
  @ObservedObject var state: AppState

  var body: some View {
    GridPanel(role: .rail) {
      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
        PanelHeader(
          title: "Telemetry",
          systemImage: "gauge.with.dots.needle.67percent"
        )

        if state.privacyMode {
          PrivacyTelemetryCard()
        } else if let telemetry = state.telemetryModel {
          TelemetryGrid(model: telemetry, speedUnit: state.exportOverlayOptions.speedUnit)
        } else {
          EmptyTelemetryCard()
        }

        IPadExportOptionsPanel(state: state)

        IPadExportStatusPanel(state: state)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }
}

private struct ClipHealthPanel: View {
  let facts: [ClipHealthFact]

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      PanelHeader(title: "Health", systemImage: "cross.case")

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
        ForEach(facts) { fact in
          MetricTile(
            title: fact.title,
            value: fact.value,
            warning: fact.severity == .warning
          )
        }
      }
    }
    .padding(TeslaCamTheme.Spacing.m)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }
}

private struct TelemetryGrid: View {
  let model: TelemetryDisplayModel
  let speedUnit: TelemetrySpeedUnit

  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
      MetricTile(title: "Speed", value: model.speedText(unit: speedUnit))
      MetricTile(title: "Pedal", value: model.acceleratorText)
      MetricTile(title: "Steer", value: model.steeringText)
      MetricTile(title: "Gear", value: model.gear)
      MetricTile(title: "AP", value: model.autopilot)
      MetricTile(title: "Brake", value: model.brakeApplied ? "On" : "Off", warning: model.brakeApplied)
      MetricTile(title: "Signal", value: model.signalText)
      MetricTile(title: "Heading", value: model.headingText)
      MetricTile(title: "GPS", value: model.locationText)
      MetricTile(title: "G-Force", value: model.gForceText)
    }
  }
}

private struct EmptyTelemetryCard: View {
  var body: some View {
    VStack(spacing: TeslaCamTheme.Spacing.xs) {
      Text("No telemetry")
        .font(TeslaCamTheme.Typography.body.weight(.semibold))
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
      Text("Speed and route appear when metadata exists.")
        .font(TeslaCamTheme.Typography.monoSmall)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
    }
    .frame(maxWidth: .infinity, minHeight: 88)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }
}

private struct PrivacyTelemetryCard: View {
  var body: some View {
    VStack(spacing: TeslaCamTheme.Spacing.xs) {
      Text("Hidden")
        .font(TeslaCamTheme.Typography.body.weight(.semibold))
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
      Text("Privacy playback mode is active.")
        .font(TeslaCamTheme.Typography.monoSmall)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
    }
    .frame(maxWidth: .infinity, minHeight: 88)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }
}

private struct RouteMiniMapView: View {
  let route: [TelemetryRoutePoint]
  let fallback: TelemetryCoordinate?
  let currentSeconds: Double

  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14)
      context.fill(Path(roundedRect: rect, cornerRadius: TeslaCamTheme.Metrics.compactCorner), with: .color(TeslaCamTheme.Colors.surfaceElevated))
      let displayRoute = TelemetryRouteReplay.displaySamples(from: route, maxPoints: 900)
      let points = displayRoute.map(\.coordinate)
      let usable = points.isEmpty ? fallback.map { [$0] } ?? [] : points
      guard !usable.isEmpty else { return }
      let minLat = usable.map(\.latitude).min() ?? 0
      let maxLat = usable.map(\.latitude).max() ?? minLat
      let minLon = usable.map(\.longitude).min() ?? 0
      let maxLon = usable.map(\.longitude).max() ?? minLon
      let latSpan = max(0.00001, maxLat - minLat)
      let lonSpan = max(0.00001, maxLon - minLon)
      func point(_ coordinate: TelemetryCoordinate) -> CGPoint {
        CGPoint(
          x: rect.minX + CGFloat((coordinate.longitude - minLon) / lonSpan) * rect.width,
          y: rect.maxY - CGFloat((coordinate.latitude - minLat) / latSpan) * rect.height
        )
      }

      if displayRoute.count > 1 {
        var path = Path()
        for (index, item) in displayRoute.enumerated() {
          let p = point(item.coordinate)
          index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        let lineWidth = TelemetryRouteStyle.lineWidth(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        context.stroke(path, with: .color(TeslaCamTheme.Colors.accent), lineWidth: CGFloat(lineWidth))
      }

      let current = route.isEmpty ? usable.last : TelemetryRouteReplay(route: route).frame(at: currentSeconds).coordinate
      if let current {
        let p = point(current)
        context.fill(Path(CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.white))
      }
    }
    .padding(TeslaCamTheme.Spacing.s)
  }
}

private struct IPadExportOptionsPanel: View {
  @ObservedObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      PanelHeader(
        title: "Export",
        systemImage: "square.and.arrow.up"
      )

      InspectorControlGrid(columns: 3) {
        InspectorToggleChip(title: "HUD", systemImage: "speedometer", isOn: Binding(
          get: { state.exportOverlayOptions.telemetryHUD },
          set: { state.exportOverlayOptions.telemetryHUD = $0 }
        ))

        InspectorMenuChip(
          title: state.exportOverlayOptions.telemetryHUDMode.displayName,
          systemImage: "gauge",
          disabled: !state.exportOverlayOptions.telemetryHUD
        ) {
          ForEach(ExportTelemetryHUDMode.allCases) { mode in
            Button(mode.displayName) {
              state.exportOverlayOptions.telemetryHUDMode = mode
            }
          }
        }

        InspectorChoiceChip(
          title: state.exportOverlayOptions.speedUnit.displayName,
          systemImage: "ruler",
          selected: true
        ) {
          state.exportOverlayOptions.speedUnit = state.exportOverlayOptions.speedUnit == .kilometersPerHour ? .milesPerHour : .kilometersPerHour
          state.refreshTelemetryOverlay()
        }

        InspectorToggleChip(title: "Map", systemImage: "map", isOn: Binding(
          get: { state.exportOverlayOptions.routeMap },
          set: { state.exportOverlayOptions.routeMap = $0 }
        ), highlightWhenOn: false)
        InspectorToggleChip(title: "Report", systemImage: "doc.text", isOn: Binding(
          get: { state.exportOverlayOptions.includeReport },
          set: { state.exportOverlayOptions.includeReport = $0 }
        ), highlightWhenOn: false)
        InspectorToggleChip(title: "Poster", systemImage: "photo", isOn: Binding(
          get: { state.exportOverlayOptions.includeScreenshot },
          set: { state.exportOverlayOptions.includeScreenshot = $0 }
        ), highlightWhenOn: false)
      }

      InspectorCameraGrid(state: state)

      InspectorControlGrid(columns: 3) {
        InspectorActionChip(title: "Export", systemImage: "square.and.arrow.up", disabled: state.clipSets.isEmpty || state.exporter.isExporting) {
          state.exportRange()
        }
        InspectorActionChip(title: "Preview", systemImage: "play.rectangle", disabled: state.exporter.isExporting) {
          state.exportPreviewSample()
        }
        InspectorActionChip(title: "Queue", systemImage: "text.badge.plus") {
          state.queueExportRange()
        }
        InspectorActionChip(title: "Copy", systemImage: "doc.on.doc") {
          copyLayout()
        }
        InspectorActionChip(title: "Paste", systemImage: "doc.on.clipboard") {
          pasteLayout()
        }
        InspectorActionChip(title: "Clear", systemImage: "xmark", disabled: state.exporter.queuedRequests.isEmpty) {
          state.exporter.clearQueue()
        }
      }

      if !state.layoutPresetStatus.isEmpty {
        Text(state.layoutPresetStatus)
          .font(TeslaCamTheme.Typography.monoSmall)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      }
    }
    .font(TeslaCamTheme.Typography.bodySmall)
    .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }

  private func copyLayout() {
    do {
      let data = try state.currentLayoutPresetData()
      UIPasteboard.general.string = String(data: data, encoding: .utf8)
      state.layoutPresetStatus = "Layout copied"
    } catch {
      state.layoutPresetStatus = "Copy failed"
    }
  }

  private func pasteLayout() {
    guard let string = UIPasteboard.general.string, let data = string.data(using: .utf8) else {
      state.layoutPresetStatus = "No layout"
      return
    }
    do {
      try state.applyLayoutPreset(data: data)
    } catch {
      state.layoutPresetStatus = "Paste failed"
    }
  }
}

private struct IPadExportStatusPanel: View {
  @ObservedObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      PanelHeader(
        title: "Selection",
        systemImage: "tray.and.arrow.down"
      )

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
        MiniFact(title: "Range", value: formatHMS(state.selectedTrimDuration))
        MiniFact(title: "Clips", value: "\(state.selectedSetsForExport.count)")
        MiniFact(title: "Queue", value: "\(state.exporter.queuedRequests.count)")
        MiniFact(title: "Preset", value: presetShortName)
      }

      HStack(spacing: TeslaCamTheme.Spacing.s) {
        Image(systemName: state.exportWarningsPreview.isEmpty ? "checkmark.shield" : "exclamationmark.triangle")
          .font(TeslaCamTheme.Typography.inspectorSymbol)
          .foregroundStyle(state.exportWarningsPreview.isEmpty ? TeslaCamTheme.Colors.textSecondary : TeslaCamTheme.Colors.gapAccent)
        Text(statusLine)
          .font(TeslaCamTheme.Typography.monoSmall)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
      }
      .padding(TeslaCamTheme.Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassSurface(
        role: state.exportWarningsPreview.isEmpty ? .control : .selected,
        radius: TeslaCamTheme.Metrics.compactCorner
      )

      if let job = state.exporter.currentJob {
        VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
          HStack {
            Text(job.phaseLabel)
              .font(TeslaCamTheme.Typography.monoSmall)
              .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
              .lineLimit(1)
            Spacer(minLength: 0)
            Text(job.progressPercentText)
              .font(TeslaCamTheme.Typography.monoSmall)
              .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          }
          ProgressView(value: job.isIndeterminate ? nil : job.progress)
            .progressViewStyle(.linear)
            .tint(TeslaCamTheme.Colors.accent)
        }
      }
    }
    .padding(TeslaCamTheme.Spacing.m)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
  }

  private var presetShortName: String {
    switch state.exportPreset {
    case .maxQualityHEVC:
      return "Evidence"
    case .fastHEVC:
      return "Fast"
    case .socialShareHEVC:
      return "Social"
    case .proxyHEVC:
      return "Proxy"
    case .editFriendlyProRes:
      return "ProRes"
    }
  }

  private var statusLine: String {
    if let warning = state.exportWarningsPreview.first {
      return warning
    }
    return "Ready. HUD exports speed and drive data."
  }
}

private struct MiniFact: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      Text(value)
        .font(TeslaCamTheme.Typography.miniMetricValue)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, TeslaCamTheme.Spacing.s)
    .frame(height: 38)
    .glassSurface(role: .control, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}

private struct InspectorControlGrid<Content: View>: View {
  let columns: Int
  @ViewBuilder let content: () -> Content

  var body: some View {
    GlassEffectGroup(spacing: TeslaCamTheme.Spacing.xs) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: TeslaCamTheme.Spacing.xs), count: columns),
        spacing: TeslaCamTheme.Spacing.xs
      ) {
        content()
      }
    }
  }
}

private struct InspectorToggleChip: View {
  let title: String
  let systemImage: String
  @Binding var isOn: Bool
  var highlightWhenOn: Bool = true

  var body: some View {
    InspectorChoiceChip(
      title: title,
      systemImage: systemImage,
      selected: highlightWhenOn && isOn
    ) {
      isOn.toggle()
    }
  }
}

private struct InspectorCameraGrid: View {
  @ObservedObject var state: AppState

  var body: some View {
    InspectorControlGrid(columns: 3) {
      ForEach(state.camerasDetected, id: \.self) { camera in
        InspectorChoiceChip(
          title: camera.shortName,
          systemImage: "video",
          selected: false
        ) {
          let isEnabled = state.activeExportCameras.contains(camera)
          state.toggleExportCamera(camera, isEnabled: !isEnabled)
        }
        .accessibilityLabel(camera.displayName)
        .accessibilityValue(state.activeExportCameras.contains(camera) ? "Included" : "Excluded")
        .accessibilityHint("Toggles whether this camera appears in the export.")
        .accessibilityIdentifier("camera-\(camera.rawValue)")
      }
    }
  }
}

private struct InspectorActionChip: View {
  let title: String
  let systemImage: String
  var role: SurfaceRole = .control
  var disabled: Bool = false
  let action: () -> Void

  var body: some View {
    InspectorChipButton(
      title: title,
      systemImage: systemImage,
      role: role,
      disabled: disabled,
      action: action
    )
  }
}

private struct InspectorChoiceChip: View {
  let title: String
  let systemImage: String
  let selected: Bool
  let action: () -> Void

  var body: some View {
    InspectorChipButton(
      title: title,
      systemImage: systemImage,
      role: selected ? .selected : .control,
      disabled: false,
      action: action
    )
  }
}

private struct InspectorMenuChip<Content: View>: View {
  let title: String
  let systemImage: String
  var disabled: Bool = false
  @ViewBuilder let content: () -> Content

  var body: some View {
    Menu {
      content()
    } label: {
      InspectorChipLabel(title: title, systemImage: systemImage, role: .control, disabled: disabled)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }
}

private struct InspectorChipButton: View {
  let title: String
  let systemImage: String
  let role: SurfaceRole
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      InspectorChipLabel(title: title, systemImage: systemImage, role: role, disabled: disabled)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }
}

private struct InspectorChipLabel: View {
  let title: String
  let systemImage: String
  let role: SurfaceRole
  let disabled: Bool

  var body: some View {
    HStack(alignment: .center, spacing: TeslaCamTheme.Spacing.tightGap) {
      Image(systemName: systemImage)
        .font(TeslaCamTheme.Typography.inspectorSymbol)
      Text(title)
        .font(TeslaCamTheme.Typography.inspectorChip)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .foregroundStyle(TeslaCamTheme.Colors.textPrimary.opacity(disabled ? 0.35 : 0.94))
    .padding(.horizontal, TeslaCamTheme.Spacing.s)
    .frame(maxWidth: .infinity)
    .frame(height: 28)
    .glassSurface(role: disabled ? .control : role, radius: TeslaCamTheme.Metrics.compactCorner, interactive: !disabled)
    .contentShape(Rectangle())
    .opacity(disabled ? 0.55 : 1)
  }
}
#endif

private struct OnboardingScreen: View {
  @ObservedObject var state: AppState

  var body: some View {
    #if os(iOS)
    VStack {
      Spacer()

      GridPanel(role: .overlay, padding: TeslaCamTheme.Spacing.xxl, radius: TeslaCamTheme.Metrics.cardCorner) {
        VStack(spacing: TeslaCamTheme.Spacing.l) {
          RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous)
            .fill(TeslaCamTheme.Colors.accentSoft)
            .frame(width: 64, height: 64)
            .overlay(
              Image(systemName: "archivebox")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
            )

          VStack(spacing: TeslaCamTheme.Spacing.s) {
            Text("Drop Tesla folder. Get timeline.")
              .font(TeslaCamTheme.Typography.panelTitle)
              .multilineTextAlignment(.center)
              .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

            Text("Scans nested clips, keeps true time, shows gaps, exports one native timeline.")
              .font(TeslaCamTheme.Typography.body)
              .multilineTextAlignment(.center)
              .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
              .frame(maxWidth: 460)
          }

          HStack(spacing: TeslaCamTheme.Spacing.s) {
            MetricTile(title: "Mode", value: "Local")
            MetricTile(title: "Export", value: "Native")
            MetricTile(title: "HUD", value: "Speed")
          }
          .frame(maxWidth: 460)

          HStack(spacing: TeslaCamTheme.Spacing.s) {
            CommandChip(title: "Choose", systemImage: "folder", role: .selected, disabled: state.exporter.isExporting) {
              state.chooseFolder()
            }
            .accessibilityIdentifier("choose-folder")

            CommandChip(title: "Demo", systemImage: "play.rectangle", disabled: state.exporter.isExporting) {
              state.loadDemoTimeline()
            }
            .accessibilityIdentifier("load-demo")
          }
        }
      }
      .frame(maxWidth: 560)

      Spacer()
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    .accessibilityIdentifier("onboarding-screen")
    #else
    VStack {
      Spacer()

      VStack(spacing: TeslaCamTheme.Spacing.section) {
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.controlCorner, style: .continuous)
          .fill(TeslaCamTheme.Colors.surfaceElevated)
          .frame(width: 72, height: 72)
          .overlay(
            Image(systemName: "archivebox")
              .font(.system(size: 28, weight: .medium))
              .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          )

        VStack(spacing: TeslaCamTheme.Spacing.m) {
          Text("Drop Tesla folder.\nGet timeline.")
            .font(TeslaCamTheme.Typography.heroTitle)
            .multilineTextAlignment(.center)
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

          Text("TeslaCam scans nested folders, keeps true clock time, shows real gaps, and exports one native timeline.")
            .font(TeslaCamTheme.Typography.panelSubtitle)
            .multilineTextAlignment(.center)
            .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
            .frame(maxWidth: 520)
        }

        HStack(spacing: TeslaCamTheme.Spacing.m) {
          Button("Choose Folder") { state.chooseFolder() }
            .buttonStyle(PrimaryButtonStyle(fixedWidth: 220))
            .disabled(state.exporter.isExporting)
            .accessibilityIdentifier("choose-folder")

          Button("Demo") { state.loadDemoTimeline() }
            .buttonStyle(QuickActionButtonStyle())
            .disabled(state.exporter.isExporting)
            .accessibilityIdentifier("load-demo")
        }
      }

      Spacer()
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    .accessibilityIdentifier("onboarding-screen")
    #endif
  }
}

private struct IndexingScreen: View {
  @ObservedObject var state: AppState

  var body: some View {
    #if os(iOS)
    VStack {
      Spacer()

      GridPanel(role: .overlay, padding: TeslaCamTheme.Spacing.xxl, radius: TeslaCamTheme.Metrics.cardCorner) {
        VStack(spacing: TeslaCamTheme.Spacing.l) {
          PanelHeader(
            title: "Building Timeline",
            systemImage: "timeline.selection"
          )

          ProgressView()
            .progressViewStyle(.linear)
            .tint(TeslaCamTheme.Colors.accent)

          VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
            ForEach(ScanStage.allCases) { stage in
              StageRow(
                title: stage.title,
                completed: stage.rawValue < state.scanStage.rawValue,
                active: stage == state.scanStage
              )
            }
          }

          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
            MetricTile(title: "Sources", value: "\(max(1, state.sourceURLs.count))")
            MetricTile(title: "Clips", value: "\(state.scanDiscoveredClipCount)")
            MetricTile(title: "Range", value: state.scanDateRangeSummary)
            MetricTile(
              title: "Duration",
              value: state.totalDuration > 0 ? state.scanDurationSummary : "Scanning"
            )
          }

          RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
            .fill(TeslaCamTheme.Colors.surface)
            .frame(height: 48)
            .overlay(TimelinePreviewBars(active: true).padding(.horizontal, TeslaCamTheme.Spacing.l))
            .glassSurface(role: .control, radius: TeslaCamTheme.Metrics.compactCorner)
        }
      }
      .frame(maxWidth: 560)

      Spacer()
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    .accessibilityIdentifier("indexing-screen")
    #else
    VStack {
      Spacer()

      VStack(spacing: TeslaCamTheme.Spacing.section) {
        VStack(spacing: TeslaCamTheme.Spacing.m) {
          Text("Building Your Timeline")
            .font(TeslaCamTheme.Typography.panelTitle)
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          Text("Organizing clips automatically")
            .font(TeslaCamTheme.Typography.body)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        }

        ProgressView()
          .progressViewStyle(.linear)
          .tint(TeslaCamTheme.Colors.accent)
          .frame(width: TeslaCamTheme.Layout.narrowPanelWidth)

        VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
          ForEach(ScanStage.allCases) { stage in
            StageRow(
              title: stage.title,
              completed: stage.rawValue < state.scanStage.rawValue,
              active: stage == state.scanStage
            )
          }
        }
        .frame(width: TeslaCamTheme.Layout.narrowPanelWidth, alignment: .leading)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.cardGap) {
          StatCard(title: "Sources", value: "\(max(1, state.sourceURLs.count))")
          StatCard(title: "Clips", value: "\(state.scanDiscoveredClipCount)")
          StatCard(title: "Date Range", value: state.scanDateRangeSummary)
          StatCard(
            title: "Duration",
            value: state.totalDuration > 0 ? state.scanDurationSummary : (state.indexStatus.isEmpty ? "Scanning" : state.indexStatus)
          )
        }
        .frame(width: TeslaCamTheme.Layout.narrowPanelWidth)

        VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
          Text("Timeline Preview".uppercased())
            .font(TeslaCamTheme.Typography.label)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)

          RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
            .fill(TeslaCamTheme.Colors.surface)
            .frame(height: 48)
            .overlay(TimelinePreviewBars(active: true).padding(.horizontal, TeslaCamTheme.Spacing.l))
        }
        .frame(width: TeslaCamTheme.Layout.narrowPanelWidth)
      }

      Spacer()
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    .accessibilityIdentifier("indexing-screen")
    #endif
  }
}

private struct LoadedStatusBar: View {
  @ObservedObject var state: AppState

  var body: some View {
    ZStack {
      HStack {
        Button("Choose Folder") {
          state.chooseFolder()
        }
        .buttonStyle(QuickActionButtonStyle())
        .accessibilityIdentifier("choose-folder-loaded")

        Spacer()
      }

      Text("TeslaCam")
        .font(TeslaCamTheme.Typography.sectionTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    .frame(height: TeslaCamTheme.Layout.toolbarHeight)
    .background(TeslaCamTheme.Colors.chromeBar)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(TeslaCamTheme.Colors.stroke)
        .frame(height: 1)
    }
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Color.white.opacity(0.03))
        .frame(height: 1)
    }
  }
}

private struct PreviewPanelCard: View {
  @ObservedObject var state: AppState
  @ObservedObject var playbackUI: PlaybackUIState
  let maxAvailableHeight: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let height = previewHeight(for: proxy.size.width)

      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous)
          .fill(TeslaCamTheme.Colors.surface)
          .overlay(
            MetalPlayerView(
              playback: state.playback,
              cameraOrder: state.activePreviewCameras,
              layoutRequest: state.layoutRequest,
              previewLayoutMode: state.previewLayoutMode,
              focusedCamera: state.focusedCamera,
              naturalSizes: state.currentPreviewNaturalSizes
            )
              .clipShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous))
          )

        VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
          Text(state.privacyMode ? "Privacy" : overlayDate)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          Text(state.privacyMode ? "Hidden" : overlayTime)
            .font(TeslaCamTheme.Typography.monoDetail)
            .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
        }
        .padding(.horizontal, TeslaCamTheme.Metrics.chipPaddingHorizontal)
        .padding(.vertical, TeslaCamTheme.Metrics.chipPaddingVertical)
        .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurfaceStrong, radius: TeslaCamTheme.Metrics.compactCorner)
        .padding(TeslaCamTheme.Spacing.l)

        HStack(spacing: TeslaCamTheme.Spacing.s) {
          ForEach(state.camerasDetected, id: \.self) { camera in
            Text(camera.shortName)
              .font(TeslaCamTheme.Typography.label)
              .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
          }
        }
        .padding(TeslaCamTheme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .topTrailing)

        if !state.privacyMode, !playbackUI.telemetryText.isEmpty {
          Text(playbackUI.telemetryText)
            .font(TeslaCamTheme.Typography.monoSmall)
            .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
            .lineLimit(3)
            .padding(.horizontal, TeslaCamTheme.Metrics.chipPaddingHorizontal)
            .padding(.vertical, TeslaCamTheme.Metrics.chipPaddingVertical)
            .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurfaceStrong, radius: TeslaCamTheme.Metrics.compactCorner)
            .padding(TeslaCamTheme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }

        if state.currentGapRange != nil {
          Text("No recording in this span")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
            .padding(.horizontal, TeslaCamTheme.Spacing.l)
            .padding(.vertical, TeslaCamTheme.Spacing.m)
            .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurfaceStrong, radius: TeslaCamTheme.Metrics.compactCorner)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
      }
      .frame(width: proxy.size.width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.cardCorner, style: .continuous)
          .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
    }
    .frame(maxWidth: .infinity)
    .frame(height: maxAvailableHeight)
  }

  private var overlayDate: String {
    let parts = playbackUI.overlayText.split(separator: " ")
    if let first = parts.first {
      return String(first)
    }
    return "Loaded"
  }

  private var overlayTime: String {
    let parts = playbackUI.overlayText.split(separator: " ")
    if parts.count >= 2 {
      return String(parts[1])
    }
    return "00:00:00"
  }

  private var previewHeightFactor: CGFloat {
    switch state.camerasDetected.count {
    case 0...4:
      return 0.75
    case 5...6:
      return 0.66
    default:
      return 0.58
    }
  }

  private func previewHeight(for width: CGFloat) -> CGFloat {
    min(maxAvailableHeight, max(320, width * previewHeightFactor))
  }
}

private struct TimelineExportCard: View {
  @ObservedObject var state: AppState
  @ObservedObject var playback: MultiCamPlaybackController
  @ObservedObject var playbackUI: PlaybackUIState
  let timelineMarkers: [Date]
  let isSingleDayTimeline: Bool

  var body: some View {
    let minDate = state.minDate ?? Date()
    let maxDate = state.maxDate ?? Date()

    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {

      // ── Row 1: Playback bar ──────────────────────────────
      HStack(spacing: TeslaCamTheme.Spacing.m) {
        Button {
          state.togglePlay()
        } label: {
          Label(
            playback.isPlaying ? "Pause" : "Play",
            systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
          )
          .labelStyle(.iconOnly)
        }
        #if os(iOS)
        .compactButtonStyle(role: .selected, size: .icon)
        #else
        .buttonStyle(IconButtonStyle(prominent: true))
        #endif
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        .accessibilityValue(playback.isPlaying ? "playing" : "paused")
        .accessibilityIdentifier("toggle-playback")

        Text(playbackSummaryText)
          .font(TeslaCamTheme.Typography.monoDetail)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)

        Spacer()

        Text(formatHMS(state.selectedTrimDuration))
          .font(TeslaCamTheme.Typography.monoDetail)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)

        Text("·")
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)

        Text("\(state.selectedSetsForExport.count) spans")
          .font(TeslaCamTheme.Typography.monoDetail)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      }

      // ── Row 2: Timeline track ────────────────────────────
      TimelineSelectionTrack(
        currentSeconds: playbackSecondsBinding,
        selectedStartSeconds: $state.trimStartSeconds,
        selectedEndSeconds: $state.trimEndSeconds,
        gapRanges: state.timelineGapRanges,
        totalDuration: max(state.totalDuration, 1),
        onSeekStart: { state.beginSeek() },
        onSeekChange: { state.liveSeek(to: $0) },
        onSeekEnd: { state.endSeek() },
        onDragStart: { state.beginTrimDrag() },
        onDragChange: { start, end in state.updateTrimRange(startSeconds: start, endSeconds: end) },
        onDragEnd: { start, end in state.endTrimDrag(startSeconds: start, endSeconds: end) }
      )
      .frame(height: 72)

      HStack(spacing: TeslaCamTheme.Spacing.l) {
        Text(tickLabel(for: state.minDate))
        ForEach(timelineMarkers, id: \.self) { marker in
          Text(tickLabel(for: marker))
            .frame(maxWidth: .infinity)
        }
        Text(tickLabel(for: state.maxDate))
      }
      .font(TeslaCamTheme.Typography.monoDetail)
      .foregroundStyle(TeslaCamTheme.Colors.textTertiary)

      // ── Row 3: Controls grid — From / Preset / To ────────
      #if os(iOS)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
        RangeControlCard(title: "From") {
          DatePicker(
            "",
            selection: Binding(
              get: { state.selectedStart },
              set: { state.updateTrimStart(from: $0) }
            ),
            in: minDate...maxDate,
            displayedComponents: [.date, .hourAndMinute]
          )
          .labelsHidden()
          .datePickerStyle(.compact)
        }

        RangeControlCard(title: "To") {
          DatePicker(
            "",
            selection: Binding(
              get: { state.selectedEnd },
              set: { state.updateTrimEnd(from: $0) }
            ),
            in: minDate...maxDate,
            displayedComponents: [.date, .hourAndMinute]
          )
          .labelsHidden()
          .datePickerStyle(.compact)
        }

        RangeControlCard(title: "Preset") {
          Picker("", selection: $state.exportPreset) {
            ForEach(ExportPreset.allCases) { preset in
              Text(preset.displayName).tag(preset)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }
      }
      .frame(minHeight: TeslaCamTheme.Metrics.controlHeight)
      #else
      HStack(alignment: .top, spacing: TeslaCamTheme.Spacing.m) {
        RangeControlCard(title: "From") {
          DatePicker(
            "",
            selection: Binding(
              get: { state.selectedStart },
              set: { state.updateTrimStart(from: $0) }
            ),
            in: minDate...maxDate,
            displayedComponents: [.date, .hourAndMinute]
          )
          .labelsHidden()
          #if os(macOS)
          .datePickerStyle(.field)
          #else
          .datePickerStyle(.compact)
          #endif
        }

        RangeControlCard(title: "Preset") {
          Picker("", selection: $state.exportPreset) {
            ForEach(ExportPreset.allCases) { preset in
              Text(preset.displayName).tag(preset)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        RangeControlCard(title: "To") {
          DatePicker(
            "",
            selection: Binding(
              get: { state.selectedEnd },
              set: { state.updateTrimEnd(from: $0) }
            ),
            in: minDate...maxDate,
            displayedComponents: [.date, .hourAndMinute]
          )
          .labelsHidden()
          #if os(macOS)
          .datePickerStyle(.field)
          #else
          .datePickerStyle(.compact)
          #endif
        }
      }
      .frame(minHeight: TeslaCamTheme.Metrics.controlHeight)
      #endif

      // ── Row 4: Camera toggles ────────────────────────────
      CameraToggleRow(state: state)

      ExportConfidenceStrip(
        duplicateSummaryText: state.duplicateSummaryText,
        partialSelectedSetCount: state.partialSelectedSetCount,
        hiddenCameraNames: state.hiddenExportCameraNames,
        gapCount: state.timelineGapRanges.count
      )

      // ── Row 5: Quick range + Duplicate + Export ───────────
      #if os(iOS)
      HStack(alignment: .top, spacing: TeslaCamTheme.Spacing.s) {
        HStack(spacing: TeslaCamTheme.Spacing.s) {
          Button("All") { state.setFullRange() }
            .compactButtonStyle(role: .control, size: .chip)
            .accessibilityLabel("Whole Timeline")
            .accessibilityIdentifier("range-whole-timeline")
          Button("1m") { state.setCurrentMinuteRange() }
            .compactButtonStyle(role: .control, size: .chip)
            .accessibilityLabel("Current Minute")
            .accessibilityIdentifier("range-current-minute")
          Button("5m") { state.setRecentRange(minutes: 5) }
            .compactButtonStyle(role: .control, size: .chip)
            .accessibilityLabel("Last 5m")
            .accessibilityIdentifier("range-last-5m")
          Button("15m") { state.setRecentRange(minutes: 15) }
            .compactButtonStyle(role: .control, size: .chip)
            .accessibilityLabel("Last 15m")
            .accessibilityIdentifier("range-last-15m")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
          Text("Dupes")
            .font(TeslaCamTheme.Typography.label)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          Picker(
            "",
            selection: Binding(
              get: { state.duplicatePolicy },
              set: { state.updateDuplicatePolicy($0) }
            )
          ) {
            ForEach(DuplicateClipPolicy.allCases) { policy in
              Text(policy.displayName).tag(policy)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .accessibilityHint("Changes how clips with the same timestamp and camera are resolved.")
        }

        Button {
          state.exportRange()
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
        }
        .compactButtonStyle(role: .selected, size: .command)
        .disabled(state.clipSets.isEmpty || state.exporter.isExporting)
        .accessibilityLabel("Export Video")
        .accessibilityIdentifier("export-video")
      }
      .frame(minHeight: TeslaCamTheme.Metrics.controlHeight)
      #else
      HStack(alignment: .top, spacing: TeslaCamTheme.Spacing.m) {
        // Quick range row
        HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
          Button("All") { state.setFullRange() }
            .buttonStyle(QuickActionButtonStyle())
            .accessibilityLabel("Whole Timeline")
            .accessibilityIdentifier("range-whole-timeline")
          Button("1m") { state.setCurrentMinuteRange() }
            .buttonStyle(QuickActionButtonStyle())
            .accessibilityLabel("Current Minute")
            .accessibilityIdentifier("range-current-minute")
          Button("5m") { state.setRecentRange(minutes: 5) }
            .buttonStyle(QuickActionButtonStyle())
            .accessibilityLabel("Last 5m")
            .accessibilityIdentifier("range-last-5m")
          Button("15m") { state.setRecentRange(minutes: 15) }
            .buttonStyle(QuickActionButtonStyle())
            .accessibilityLabel("Last 15m")
            .accessibilityIdentifier("range-last-15m")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Duplicate handling
        HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
          Text("Dupes")
            .font(TeslaCamTheme.Typography.label)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          Picker(
            "",
            selection: Binding(
              get: { state.duplicatePolicy },
              set: { state.updateDuplicatePolicy($0) }
            )
          ) {
            ForEach(DuplicateClipPolicy.allCases) { policy in
              Text(policy.displayName).tag(policy)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
          .accessibilityHint("Changes how clips with the same timestamp and camera are resolved.")
        }

        // Export button
        Button("Export Video") { state.exportRange() }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(state.clipSets.isEmpty || state.exporter.isExporting)
          .accessibilityLabel("Export Video")
          .accessibilityIdentifier("export-video")
          .frame(maxWidth: 200)
      }
      .frame(minHeight: TeslaCamTheme.Metrics.controlHeight)
      #endif

      // ── Info banners (only if relevant) ──────────────────
      if !state.duplicateSummaryText.isEmpty {
        ExportInfoBanner(
          title: "Duplicates",
          message: state.duplicateSummaryText,
          systemImage: "square.on.square"
        )
      }

      if let healthSummary = state.healthSummary {
        ExportInfoBanner(
          title: "Coverage",
          message: coverageSummary(for: healthSummary),
          systemImage: "waveform.path.ecg"
        )
      }

      ForEach(state.exportWarningsPreview, id: \.self) { warning in
        ExportInfoBanner(
          title: "Export warning",
          message: warning,
          systemImage: "exclamationmark.triangle.fill"
        )
      }
    }
    .padding(TeslaCamTheme.Metrics.cardPadding)
    #if os(iOS)
    .glassSurface(role: .panel, radius: TeslaCamTheme.Metrics.cardCorner)
    #else
    .teslaCamCard()
    #endif
  }

  private var playbackSecondsBinding: Binding<Double> {
    Binding(
      get: { playbackUI.currentSeconds },
      set: { playbackUI.currentSeconds = $0 }
    )
  }

  private var playbackSummaryText: String {
    "\(formatHMS(playbackUI.currentSeconds)) / \(formatHMS(state.totalDuration))"
  }

  private var trimRangeSummary: String {
    formattedTimelineDate(state.selectedStart) + " - " + formattedTimelineDate(state.selectedEnd)
  }

  private func tickLabel(for date: Date?) -> String {
    guard let date else { return "" }
    if isSingleDayTimeline {
      return TeslaCamFormatters.timelineSameDay.string(from: date)
    }
    let span = (state.maxDate ?? date).timeIntervalSince(state.minDate ?? date)
    if span <= 172_800 {
      return TeslaCamFormatters.timelineTwoDay.string(from: date)
    }
    return TeslaCamFormatters.timelineMultiDay.string(from: date)
  }

  private func formattedTimelineDate(_ date: Date) -> String {
    TeslaCamFormatters.selectedRange.string(from: date)
  }

  private func coverageSummary(for summary: ExportHealthSummary) -> String {
    var parts = [
      "\(summary.totalMinutes)m timeline",
      "\(summary.gapCount) gap\(summary.gapCount == 1 ? "" : "s")",
      "\(summary.partialSetCount) partial span\(summary.partialSetCount == 1 ? "" : "s")"
    ]

    if summary.hasMixedCoverage {
      parts.append("mixed 4- and 6-camera coverage")
    }

    if !summary.missingCoverageSummary.isEmpty {
      parts.append(summary.missingCoverageSummary)
    }

    return parts.joined(separator: " • ")
  }
}

private struct CameraToggleRow: View {
  @ObservedObject var state: AppState

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: TeslaCamTheme.Spacing.s) {
        ForEach(state.camerasDetected, id: \.self) { camera in
          Button {
            let isEnabled = state.activeExportCameras.contains(camera)
            state.toggleExportCamera(camera, isEnabled: !isEnabled)
          } label: {
            HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
              Image(systemName: state.activeExportCameras.contains(camera) ? "checkmark.square.fill" : "square")
                .font(TeslaCamTheme.Typography.label)
              Text(camera.shortName)
                .font(TeslaCamTheme.Typography.label)
                .lineLimit(1)
            }
            .foregroundStyle(state.activeExportCameras.contains(camera) ? TeslaCamTheme.Colors.textPrimary : TeslaCamTheme.Colors.textSecondary)
            .padding(.horizontal, TeslaCamTheme.Metrics.chipPaddingHorizontal)
            .padding(.vertical, TeslaCamTheme.Metrics.chipPaddingVertical)
            .frame(minWidth: 52, maxWidth: 96, minHeight: 34)
            .glassSurface(
              role: state.activeExportCameras.contains(camera) ? .selected : .control,
              radius: TeslaCamTheme.Metrics.compactCorner,
              interactive: true
            )
          }
          .buttonStyle(.plain)
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityLabel(camera.displayName)
          .accessibilityValue(state.activeExportCameras.contains(camera) ? "Included" : "Excluded")
          .accessibilityHint("Toggles whether this camera appears in the export.")
          .accessibilityIdentifier("camera-\(camera.rawValue)")
        }
      }
      .fixedSize(horizontal: true, vertical: false)
    }
  }
}

private struct ExportConfidenceStrip: View {
  let duplicateSummaryText: String
  let partialSelectedSetCount: Int
  let hiddenCameraNames: [String]
  let gapCount: Int

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      ExportConfidenceChip(
        title: "Gaps",
        value: "\(gapCount)",
        systemImage: gapCount == 0 ? "checkmark.square" : "waveform.path.ecg"
      )

      ExportConfidenceChip(
        title: "Partial",
        value: "\(partialSelectedSetCount)",
        systemImage: partialSelectedSetCount == 0 ? "checkmark.square" : "rectangle.split.2x1"
      )

      ExportConfidenceChip(
        title: "Hidden",
        value: hiddenCameraNames.isEmpty ? "0" : "\(hiddenCameraNames.count)",
        systemImage: hiddenCameraNames.isEmpty ? "eye" : "eye.slash"
      )

      if !duplicateSummaryText.isEmpty {
        ExportConfidenceChip(
          title: "Dupes",
          value: duplicateSummaryText,
          systemImage: "square.on.square"
        )
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilitySummary)
    .animation(.easeInOut(duration: 0.18), value: partialSelectedSetCount)
    .animation(.easeInOut(duration: 0.18), value: hiddenCameraNames)
  }

  private var accessibilitySummary: String {
    var parts = ["\(gapCount) gaps", "\(partialSelectedSetCount) partial spans"]
    if !hiddenCameraNames.isEmpty {
      parts.append("Hidden cameras: \(hiddenCameraNames.joined(separator: ", "))")
    }
    if !duplicateSummaryText.isEmpty {
      parts.append("Duplicates: \(duplicateSummaryText)")
    }
    return parts.joined(separator: ". ")
  }
}

private struct ExportConfidenceChip: View {
  let title: String
  let value: String
  let systemImage: String

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
      Image(systemName: systemImage)
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
        Text(title.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        Text(value)
          .font(TeslaCamTheme.Typography.label)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, TeslaCamTheme.Metrics.chipPaddingHorizontal)
    .padding(.vertical, TeslaCamTheme.Metrics.chipPaddingVertical)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}


private struct ExportActionCard: View {
  @ObservedObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
      Text("Export".uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)

      Text(state.selectedRangeDescription)
        .font(TeslaCamTheme.Typography.monoSmall)
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
        .lineLimit(2)

      Button("Export Video") { state.exportRange() }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(state.clipSets.isEmpty || state.exporter.isExporting)
        .accessibilityLabel("Export Video")
        .accessibilityIdentifier("export-video")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .frame(minHeight: TeslaCamTheme.Metrics.controlHeight, alignment: .topLeading)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.controlCorner)
  }
}

private struct ExportCameraChip: View {
  let title: String
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
        Image(systemName: enabled ? "checkmark.square.fill" : "square")
          .font(.system(size: 12, weight: .semibold))
        Text(title)
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(enabled ? TeslaCamTheme.Colors.textPrimary : TeslaCamTheme.Colors.textSecondary)
      .padding(.horizontal, TeslaCamTheme.Metrics.chipPaddingHorizontal)
      .padding(.vertical, TeslaCamTheme.Metrics.chipPaddingVertical)
      .frame(minHeight: 36)
      .background(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .fill(enabled ? TeslaCamTheme.Colors.surfaceElevated : TeslaCamTheme.Colors.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .stroke(enabled ? TeslaCamTheme.Colors.accent.opacity(0.7) : TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(enabled ? "Included" : "Excluded")
  }
}

private struct ExportInfoBanner: View {
  let title: String
  let message: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: TeslaCamTheme.Spacing.s) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
        Text(title.uppercased())
          .font(TeslaCamTheme.Typography.label)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        Text(message)
          .font(TeslaCamTheme.Typography.bodySmall)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
      }

      Spacer(minLength: 0)
    }
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.controlCorner)
  }
}

private struct RangeControlCard<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
      Text(title.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.m)
    .padding(.vertical, TeslaCamTheme.Spacing.s)
    .frame(maxWidth: .infinity, minHeight: TeslaCamTheme.Metrics.controlHeight, alignment: .leading)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.controlCorner)
  }
}

private struct ExportOverlayCard: View {
  @ObservedObject var state: AppState
  let job: ExportJobSnapshot

  var body: some View {
    #if os(iOS)
    ZStack {
      TeslaCamTheme.Colors.overlayScrim
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.l) {
        PanelHeader(
          title: title,
          systemImage: job.isTerminal ? "checkmark.square" : "hourglass"
        )
        .accessibilityIdentifier("export-overlay-title")

        ProgressView(value: max(0, min(job.progress, 1)))
          .tint(TeslaCamTheme.Colors.accent)
          .opacity(job.isTerminal ? 0.75 : 1)

        HStack(spacing: TeslaCamTheme.Spacing.s) {
          MetricTile(title: "Progress", value: job.progressPercentText)
          MetricTile(title: "State", value: job.phaseLabel)
        }

        Text(detail)
          .font(TeslaCamTheme.Typography.bodySmall)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
          .lineLimit(2)

        HStack(spacing: TeslaCamTheme.Spacing.s) {
          if job.isTerminal {
            if job.phase == .completed {
              CommandChip(title: "Reveal", systemImage: "arrow.up.forward.app", role: .selected) {
                state.exporter.revealOutput(for: job)
              }
              .accessibilityLabel("Reveal File")
            } else {
              CommandChip(title: "Log", systemImage: "doc.text", role: .selected) {
                state.exporter.revealLog()
              }
              .accessibilityLabel("Show Log")
            }

            CommandChip(title: "Done", systemImage: "checkmark") {
              state.dismissExportStatus()
            }
            .accessibilityLabel("Done")
            .accessibilityIdentifier("dismiss-export-status")
          } else {
            CommandChip(title: "Cancel", systemImage: "xmark", role: .selected) {
              state.cancelExport()
            }
            .accessibilityLabel("Cancel Export")
          }
        }
      }
      .padding(TeslaCamTheme.Spacing.xxl)
      .frame(maxWidth: 420)
      .glassSurface(role: .overlay, radius: TeslaCamTheme.Metrics.cardCorner)
      .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    }
    .allowsHitTesting(true)
    .accessibilityIdentifier("export-overlay")
    .zIndex(20)
    #else
    ZStack {
      TeslaCamTheme.Colors.overlayScrim
        .ignoresSafeArea()

      VStack(spacing: TeslaCamTheme.Spacing.xxl) {
        Text(title)
          .font(TeslaCamTheme.Typography.panelTitle)
          .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          .accessibilityIdentifier("export-overlay-title")

        Text(job.phaseLabel)
          .font(TeslaCamTheme.Typography.panelSubtitle.weight(.medium))
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)

        ProgressView(value: max(0, min(job.progress, 1)))
          .tint(TeslaCamTheme.Colors.accent)
          .scaleEffect(x: 1, y: 2.6, anchor: .center)
          .frame(maxWidth: TeslaCamTheme.Layout.overlayContentWidth)
          .opacity(job.isTerminal ? 0.75 : 1)

        HStack {
          Text(detail)
            .font(TeslaCamTheme.Typography.body)
            .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
            .lineLimit(2)

          Spacer()

          Text(job.progressPercentText)
            .font(TeslaCamTheme.Typography.numericBody)
            .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        }
        .frame(maxWidth: TeslaCamTheme.Layout.overlayContentWidth)

        if job.isTerminal {
          VStack(spacing: TeslaCamTheme.Spacing.m) {
            if job.phase == .completed {
              Button("Reveal File") {
                state.exporter.revealOutput(for: job)
              }
              .buttonStyle(PrimaryButtonStyle(fixedWidth: 240))
              .accessibilityLabel("Reveal File")
            } else {
              Button("Show Log") {
                state.exporter.revealLog()
              }
              .buttonStyle(PrimaryButtonStyle(fixedWidth: 240))
              .accessibilityLabel("Show Log")
            }

            Button("Done") {
              state.dismissExportStatus()
            }
            .buttonStyle(QuickActionButtonStyle())
            .accessibilityLabel("Done")
            .accessibilityIdentifier("dismiss-export-status")
          }
        } else {
          Button("Cancel Export") {
            state.cancelExport()
          }
          .buttonStyle(PrimaryButtonStyle(fixedWidth: 240))
          .accessibilityLabel("Cancel Export")
        }
      }
      .padding(TeslaCamTheme.Spacing.section)
      .frame(maxWidth: TeslaCamTheme.Layout.overlayCardWidth)
      .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurfaceStrong, radius: TeslaCamTheme.Metrics.cardCorner)
      .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    }
    .allowsHitTesting(true)
    .accessibilityIdentifier("export-overlay")
    .zIndex(20)
    #endif
  }

  private var title: String {
    switch job.phase {
    case .completed:
      return "Export Complete"
    case .failed:
      return "Export Failed"
    case .cancelled:
      return "Export Cancelled"
    default:
      return "Exporting Video"
    }
  }

  private var detail: String {
    if let reason = job.failureReason, job.isTerminal {
      return reason
    }
    return job.detailText
  }
}

private struct DuplicateResolverSheet: View {
  @ObservedObject var state: AppState

  var body: some View {
    #if os(iOS)
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.l) {
      PanelHeader(
        title: "Resolve Duplicates",
        systemImage: "square.on.square"
      )

      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
        duplicateChoiceButton("Merge by Time", subtitle: "One ordered timeline.") {
          state.chooseDuplicatePolicy(.mergeByTime)
        }
        duplicateChoiceButton("Keep All", subtitle: "Preserve every duplicate.") {
          state.chooseDuplicatePolicy(.keepAll)
        }
        duplicateChoiceButton("Prefer Newest", subtitle: "Use newest file on collision.") {
          state.chooseDuplicatePolicy(.preferNewest)
        }
      }

      HStack {
        Spacer()
        CommandChip(title: "Keep", systemImage: "checkmark") {
          state.dismissDuplicateResolver()
        }
        .accessibilityLabel("Keep Current")
        .accessibilityIdentifier("duplicate-keep-current")
      }
    }
    .padding(TeslaCamTheme.Spacing.xxl)
    .frame(maxWidth: 460)
    .glassSurface(role: .overlay, radius: TeslaCamTheme.Metrics.cardCorner)
    .padding(TeslaCamTheme.Spacing.xxl)
    .background(TeslaCamSceneBackground())
    #else
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.l) {
      Text("Resolve Duplicates")
        .font(TeslaCamTheme.Typography.panelTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

      Text(state.duplicateResolverMessage.isEmpty ? "Multiple clips share the same timeline position." : state.duplicateResolverMessage)
        .font(TeslaCamTheme.Typography.body)
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)

      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
        duplicateChoiceButton("Merge by Time", subtitle: "Keep one ordered timeline and merge matching timestamps.") {
          state.chooseDuplicatePolicy(.mergeByTime)
        }
        duplicateChoiceButton("Keep All", subtitle: "Preserve every duplicate as separate timeline entries.") {
          state.chooseDuplicatePolicy(.keepAll)
        }
        duplicateChoiceButton("Prefer Newest", subtitle: "Use the newest file when timestamps collide.") {
          state.chooseDuplicatePolicy(.preferNewest)
        }
      }

      HStack {
        Spacer()
        Button("Keep Current") {
          state.dismissDuplicateResolver()
        }
        .buttonStyle(QuickActionButtonStyle())
        .accessibilityLabel("Keep Current")
        .accessibilityIdentifier("duplicate-keep-current")
      }
    }
    .padding(TeslaCamTheme.Spacing.xxl)
    .frame(width: TeslaCamTheme.Layout.duplicateSheetWidth)
    .background(TeslaCamSceneBackground())
    #endif
  }

  private func duplicateChoiceButton(_ title: String, subtitle: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
        Text(title)
          .font(TeslaCamTheme.Typography.body.weight(.semibold))
          .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        Text(subtitle)
          .font(TeslaCamTheme.Typography.bodySmall)
          .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
      #if os(iOS)
      .glassSurface(role: .control, radius: TeslaCamTheme.Metrics.compactCorner, interactive: true)
      #else
      .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.controlCorner)
      #endif
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityIdentifier("duplicate-choice-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
  }
}

private struct StatCard: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      Text(title.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      Text(value)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(TeslaCamTheme.Metrics.cardPadding)
    .teslaCamCard()
  }
}

private struct StageRow: View {
  let title: String
  let completed: Bool
  let active: Bool

  var body: some View {
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      Rectangle()
        .fill(active ? TeslaCamTheme.Colors.accent : Color.white.opacity(0.2))
        .frame(width: 6, height: 6)

      Text(title)
        .font(TeslaCamTheme.Typography.body.weight(active ? .semibold : .regular))
        .foregroundStyle(completed || active ? TeslaCamTheme.Colors.textPrimary : TeslaCamTheme.Colors.textTertiary)

      Spacer()

      if completed {
        Image(systemName: "checkmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      } else if active {
        Text("...")
          .font(.system(size: 14, weight: .bold, design: .monospaced))
          .foregroundStyle(TeslaCamTheme.Colors.accent)
      }
    }
  }
}

private struct TimelinePreviewBars: View {
  let active: Bool

  var body: some View {
    HStack(alignment: .center, spacing: TeslaCamTheme.Spacing.xs) {
      ForEach(0..<48, id: \.self) { index in
        Rectangle()
          .fill(TeslaCamTheme.Colors.accent.opacity(active ? 0.95 : 0.5))
          .frame(width: 4, height: CGFloat(12 + ((index * 7) % 18)))
      }
    }
  }
}

private struct TimelineSelectionTrack: View {
  @Binding var currentSeconds: Double
  @Binding var selectedStartSeconds: Double
  @Binding var selectedEndSeconds: Double
  let gapRanges: [TimelineGapRange]
  let totalDuration: Double
  let onSeekStart: () -> Void
  let onSeekChange: (Double) -> Void
  let onSeekEnd: () -> Void
  let onDragStart: () -> Void
  let onDragChange: (Double, Double) -> Void
  let onDragEnd: (Double, Double) -> Void

  @State private var dragAnchor: DragAnchor?
  @State private var isSeeking = false

  var body: some View {
    GeometryReader { proxy in
      let fullWidth = proxy.size.width
      let safeDuration = max(totalDuration, 1)
      let laneHeight: CGFloat = 44
      let laneY: CGFloat = 12
      let trackInset: CGFloat = 16
      let trackWidth = max(fullWidth - (trackInset * 2), 1)
      let startX = trackInset + trackWidth * CGFloat(max(0, min(1, selectedStartSeconds / safeDuration)))
      let endX = trackInset + trackWidth * CGFloat(max(0, min(1, selectedEndSeconds / safeDuration)))
      let playheadX = trackInset + trackWidth * CGFloat(max(0, min(1, currentSeconds / safeDuration)))
      let selectionWidth = max(endX - startX, 8)

      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .fill(TeslaCamTheme.Colors.surface)
          .frame(width: trackWidth, height: laneHeight)
          .offset(x: trackInset, y: laneY)
          .contentShape(Rectangle())
          .gesture(backgroundSeekGesture(originX: trackInset, width: trackWidth))

        ForEach(Array(gapRanges.enumerated()), id: \.offset) { _, gap in
          let gapStartX = trackInset + trackWidth * CGFloat(max(0, min(1, gap.startSeconds / safeDuration)))
          let gapEndX = trackInset + trackWidth * CGFloat(max(0, min(1, gap.endSeconds / safeDuration)))
          let gapWidth = max(gapEndX - gapStartX, 2)

          TimelineGapBand(showLabel: gap.duration > max(600, safeDuration * 0.12))
            .frame(width: gapWidth, height: laneHeight)
            .offset(x: gapStartX, y: laneY)
            .allowsHitTesting(false)
        }
      let isFullRange = selectedStartSeconds <= 0.01 && selectedEndSeconds >= totalDuration - 0.01

        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .fill(TeslaCamTheme.Colors.accentSoft)
          .frame(width: selectionWidth, height: laneHeight)
          .overlay(
            RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
              .stroke(TeslaCamTheme.Colors.accent, lineWidth: 1.2)
          )
          .offset(x: startX, y: laneY)
          .contentShape(Rectangle())
          .gesture(selectionDrag(width: trackWidth))
          .allowsHitTesting(!isFullRange)

        handle
          .offset(x: clampedHandleX(centerX: startX, trackInset: trackInset, trackWidth: trackWidth), y: laneY - 1)
          .contentShape(Rectangle())
          .gesture(handleDrag(kind: .start, originX: trackInset, width: trackWidth))

        handle
          .offset(x: clampedHandleX(centerX: endX, trackInset: trackInset, trackWidth: trackWidth), y: laneY - 1)
          .contentShape(Rectangle())
          .gesture(handleDrag(kind: .end, originX: trackInset, width: trackWidth))

        playhead
          .offset(x: clampedPlayheadX(centerX: playheadX, trackInset: trackInset, trackWidth: trackWidth), y: laneY - 1)
          .contentShape(Rectangle())
          .gesture(playheadSeekGesture(originX: trackInset, width: trackWidth))
      }
    }
    .accessibilityIdentifier("merged-timeline-track")
  }

  private var handle: some View {
    ZStack {
      Color.clear.frame(width: 20, height: 44)
      Rectangle()
        .fill(TeslaCamTheme.Colors.controlKnob)
        .frame(width: 6, height: 26)
        .overlay(
          Rectangle()
            .stroke(TeslaCamTheme.Colors.controlKnobStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
    }
  }

  private var playhead: some View {
    ZStack(alignment: .center) {
      Color.clear.frame(width: 16, height: 44)
      Rectangle()
        .fill(TeslaCamTheme.Colors.accent)
        .frame(width: 2, height: 34)
    }
  }

  private func clampedHandleX(centerX: CGFloat, trackInset: CGFloat, trackWidth: CGFloat) -> CGFloat {
    max(trackInset, min(trackInset + trackWidth - 20, centerX - 10))
  }

  private func clampedPlayheadX(centerX: CGFloat, trackInset: CGFloat, trackWidth: CGFloat) -> CGFloat {
    max(trackInset, min(trackInset + trackWidth - 16, centerX - 8))
  }

  private func seconds(forX x: CGFloat, originX: CGFloat, width: CGFloat) -> Double {
    let clamped = max(0, min(width, x - originX))
    let fraction = Double(max(0, min(1, clamped / max(width, 1))))
    return totalDuration * fraction
  }

  private func updateSeek(from x: CGFloat, originX: CGFloat, width: CGFloat) {
    let seconds = seconds(forX: x, originX: originX, width: width)
    currentSeconds = seconds
    onSeekChange(seconds)
  }

  private func backgroundSeekGesture(originX: CGFloat, width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard dragAnchor == nil else { return }
        if !isSeeking {
          isSeeking = true
          onSeekStart()
        }
        updateSeek(from: value.location.x, originX: originX, width: width)
      }
      .onEnded { value in
        guard isSeeking else { return }
        updateSeek(from: value.location.x, originX: originX, width: width)
        onSeekEnd()
        isSeeking = false
      }
  }

  private func playheadSeekGesture(originX: CGFloat, width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if !isSeeking {
          isSeeking = true
          onSeekStart()
        }
        updateSeek(from: value.location.x, originX: originX, width: width)
      }
      .onEnded { value in
        updateSeek(from: value.location.x, originX: originX, width: width)
        onSeekEnd()
        isSeeking = false
      }
  }

  private func handleDrag(kind: HandleKind, originX: CGFloat, width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !isSeeking else { return }
        if dragAnchor == nil {
          dragAnchor = DragAnchor(kind: kind, startSeconds: selectedStartSeconds, endSeconds: selectedEndSeconds)
          onDragStart()
        }
        var start = selectedStartSeconds
        var end = selectedEndSeconds
        let grabbed = seconds(forX: value.location.x, originX: originX, width: width)
        switch kind {
        case .start:
          start = min(grabbed, selectedEndSeconds)
        case .end:
          end = max(grabbed, selectedStartSeconds)
        case .selection:
          break
        }
        onDragChange(start, end)
      }
      .onEnded { _ in
        onDragEnd(selectedStartSeconds, selectedEndSeconds)
        dragAnchor = nil
      }
  }

  private func selectionDrag(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !isSeeking else { return }
        if dragAnchor == nil {
          dragAnchor = DragAnchor(kind: .selection, startSeconds: selectedStartSeconds, endSeconds: selectedEndSeconds)
          onDragStart()
        }
        guard let dragAnchor else { return }
        let delta = Double(value.translation.width / max(width, 1)) * totalDuration
        let range = dragAnchor.endSeconds - dragAnchor.startSeconds
        var start = dragAnchor.startSeconds + delta
        start = max(0, min(start, totalDuration - range))
        let end = min(totalDuration, start + range)
        onDragChange(start, end)
      }
      .onEnded { _ in
        onDragEnd(selectedStartSeconds, selectedEndSeconds)
        dragAnchor = nil
      }
  }

  private enum HandleKind {
    case start
    case end
    case selection
  }

  private struct DragAnchor {
    let kind: HandleKind
    let startSeconds: Double
    let endSeconds: Double
  }
}

private struct TimelineGapBand: View {
  let showLabel: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
        .fill(TeslaCamTheme.Colors.gapFill)

      Canvas { context, size in
        var path = Path()
        var x: CGFloat = -size.height
        while x < size.width {
          path.move(to: CGPoint(x: x, y: size.height))
          path.addLine(to: CGPoint(x: x + size.height, y: 0))
          x += 12
        }
        context.stroke(path, with: .color(TeslaCamTheme.Colors.gapAccent.opacity(0.22)), lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous))

      VStack(spacing: 0) {
        Rectangle()
          .fill(TeslaCamTheme.Colors.gapAccent.opacity(0.85))
          .frame(height: 2)
        Spacer()
        Rectangle()
          .fill(TeslaCamTheme.Colors.gapAccent.opacity(0.35))
          .frame(height: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous))

      if showLabel {
        Text("Gap")
          .font(TeslaCamTheme.Typography.label)
          .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          .padding(.horizontal, TeslaCamTheme.Spacing.s)
          .padding(.vertical, TeslaCamTheme.Spacing.xs)
          .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurface, radius: TeslaCamTheme.Metrics.compactCorner)
      }
    }
  }
}

private struct PrimaryButtonStyle: ButtonStyle {
  var fixedWidth: CGFloat? = nil

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, TeslaCamTheme.Spacing.l)
      .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
      .frame(width: fixedWidth)
      .frame(minHeight: TeslaCamTheme.Metrics.controlHeight)
      .background(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.controlCorner, style: .continuous)
          .fill(TeslaCamTheme.Colors.accent.opacity(configuration.isPressed ? 0.82 : 1))
      )
      .contentShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.controlCorner, style: .continuous))
  }
}

private struct IconButtonStyle: ButtonStyle {
  var prominent: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(prominent ? .white : TeslaCamTheme.Colors.textPrimary)
      .frame(width: 44, height: 44)
      .background(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .fill(prominent ? TeslaCamTheme.Colors.surfaceElevated : TeslaCamTheme.Colors.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
      .opacity(configuration.isPressed ? 0.82 : 1)
      .contentShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous))
  }
}

private struct QuickActionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(TeslaCamTheme.Typography.label)
      .foregroundStyle(TeslaCamTheme.Colors.textPrimary.opacity(configuration.isPressed ? 0.78 : 0.95))
      .padding(.vertical, TeslaCamTheme.Spacing.s)
      .padding(.horizontal, TeslaCamTheme.Spacing.m)
      .frame(minHeight: 32)
      .background(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .fill(TeslaCamTheme.Colors.surfaceElevated.opacity(configuration.isPressed ? 1 : 0.86))
      )
      .overlay(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous))
  }
}
