import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
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
    .environment(\.colorScheme, .dark)
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
private struct IPadLoadedScreen: View {
  @ObservedObject var state: AppState
  @ObservedObject var playbackUI: PlaybackUIState

  var body: some View {
    GeometryReader { proxy in
      HStack(alignment: .top, spacing: TeslaCamTheme.Spacing.cardGap) {
        IPadEventRail(state: state)
          .frame(width: min(300, max(240, proxy.size.width * 0.22)))

        ScrollView(.vertical, showsIndicators: false) {
          VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.cardGap) {
            PreviewPanelCard(
              state: state,
              playbackUI: playbackUI,
              maxAvailableHeight: max(330, proxy.size.height * 0.50)
            )

            IPadLayoutToolbar(state: state)

            CameraTrackStrip(
              track: state.cameraTrack,
              duration: max(1, state.totalDuration),
              currentSeconds: state.currentSeconds
            )
            .frame(height: 56)
            .teslaCamCard()

            TimelineExportCard(
              state: state,
              playback: state.playback,
              playbackUI: playbackUI,
              timelineMarkers: timelineMarkers,
              isSingleDayTimeline: isSingleDayTimeline
            )
          }
        }

        IPadTelemetryRail(state: state)
          .frame(width: min(340, max(280, proxy.size.width * 0.25)))
      }
      .padding(TeslaCamTheme.Metrics.contentPadding)
    }
    .accessibilityIdentifier("loaded-screen")
  }

  private var timelineMarkers: [Date] {
    guard let min = state.minDate, let max = state.maxDate else { return [] }
    let interval = max.timeIntervalSince(min)
    guard interval > 0 else { return [] }
    return [0.25, 0.5, 0.75].map { min.addingTimeInterval(interval * $0) }
  }

  private var isSingleDayTimeline: Bool {
    guard let min = state.minDate, let max = state.maxDate else { return true }
    return Calendar.current.isDate(min, inSameDayAs: max)
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
          context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(TeslaCamTheme.Colors.accent))
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
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
      HStack {
        Text("Events")
          .font(TeslaCamTheme.Typography.sectionTitle)
          .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        Spacer()
        Button {
          state.reloadSources()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(IconButtonStyle())
        .disabled(!state.canReloadSources)
      }

      Text(sourceTitle)
        .font(TeslaCamTheme.Typography.monoSmall)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
        .lineLimit(2)

      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
          ForEach(state.eventSummaries) { event in
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
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .teslaCamCard()
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
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
      .background(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .fill(active ? TeslaCamTheme.Colors.accentSoft : TeslaCamTheme.Colors.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
          .stroke(active ? TeslaCamTheme.Colors.accent.opacity(0.55) : TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
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
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      Picker("View", selection: $state.previewLayoutMode) {
        ForEach(PreviewLayoutMode.allCases) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Picker("Grid", selection: $state.layoutRequest) {
        ForEach(CameraLayoutRequest.allCases) { request in
          Text(request.displayName).tag(request)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 260)

      Picker("Focus", selection: Binding(
        get: { state.focusedCamera ?? state.activePreviewCameras.first ?? .front },
        set: { state.setFocusedCamera($0) }
      )) {
        ForEach(state.camerasDetected, id: \.self) { camera in
          Text(camera.shortName).tag(camera)
        }
      }
      .pickerStyle(.menu)
      .frame(width: 112)

      Picker("Rate", selection: Binding(
        get: { state.playbackRate },
        set: { state.setPlaybackRate($0) }
      )) {
        ForEach(AppState.allowedPlaybackRates, id: \.self) { rate in
          Text(rateText(rate)).tag(rate)
        }
      }
      .pickerStyle(.menu)
      .frame(width: 96)

      Toggle("Privacy", isOn: $state.privacyMode)
        .toggleStyle(.switch)
        .font(TeslaCamTheme.Typography.sectionTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
        .frame(width: 124)

      Button {
        state.addCameraTrackCut()
      } label: {
        Label("Cut", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
      }
      .buttonStyle(QuickActionButtonStyle())

      Button {
        state.clearCameraTrack()
      } label: {
        Label("\(state.cameraTrack.keyframes.count)", systemImage: "timeline.selection")
      }
      .buttonStyle(QuickActionButtonStyle())
      .disabled(state.cameraTrack.isEmpty)
    }
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .teslaCamCard()
  }

  private func rateText(_ rate: Double) -> String {
    rate == 1.0 ? "1x" : String(format: "%.2gx", rate)
  }
}

private struct IPadTelemetryRail: View {
  @ObservedObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
      Text("Telemetry")
        .font(TeslaCamTheme.Typography.sectionTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

      if state.privacyMode {
        PrivacyTelemetryCard()
      } else if let telemetry = state.telemetryModel {
        TelemetryGrid(model: telemetry)
      } else {
        EmptyTelemetryCard()
      }

      TelemetryEventLanes(
        markers: state.privacyMode ? [] : state.telemetryEventMarkers,
        duration: max(1, state.playback.currentDuration)
      )
      .frame(height: 116)
      .teslaCamCard()

      RouteMiniMapView(
        route: state.privacyMode ? [] : state.telemetryRoute,
        fallback: state.privacyMode ? nil : state.currentEvent?.coordinate,
        currentSeconds: state.currentSeconds - state.timelineStartOffsetForCurrentClip
      )
      .frame(height: 232)
      .teslaCamCard()

      ClipHealthPanel(facts: state.clipHealthFacts)

      IPadExportOptionsPanel(state: state)
    }
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .teslaCamCard()
  }
}

private struct TelemetryEventLanes: View {
  let markers: [TelemetryEventMarker]
  let duration: Double

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      Text("Events")
        .font(TeslaCamTheme.Typography.sectionTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

      Canvas { context, size in
        let laneKinds: [TelemetryEventKind] = [.brake, .accelerator, .steering, .autopilot, .gForce]
        let rowHeight = max(10, (size.height - 10) / CGFloat(laneKinds.count))
        for (index, kind) in laneKinds.enumerated() {
          let y = CGFloat(index) * rowHeight + rowHeight * 0.5
          var base = Path()
          base.move(to: CGPoint(x: 0, y: y))
          base.addLine(to: CGPoint(x: size.width, y: y))
          context.stroke(base, with: .color(TeslaCamTheme.Colors.stroke), lineWidth: 1)

          for marker in markers where marker.kind == kind {
            let x = CGFloat(min(1, max(0, marker.seconds / duration))) * size.width
            let rect = CGRect(
              x: x - 2,
              y: y - rowHeight * 0.35,
              width: 4,
              height: rowHeight * 0.7
            )
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(TeslaCamTheme.Colors.accent.opacity(0.45 + 0.45 * marker.intensity)))
          }
        }
      }
    }
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
  }
}

private struct ClipHealthPanel: View {
  let facts: [ClipHealthFact]

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.s) {
      Text("Health")
        .font(TeslaCamTheme.Typography.sectionTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TeslaCamTheme.Spacing.s) {
        ForEach(facts) { fact in
          VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
            Text(fact.title.uppercased())
              .font(TeslaCamTheme.Typography.label)
              .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
            Text(fact.value)
              .font(.system(size: 14, weight: .semibold, design: .monospaced))
              .foregroundStyle(fact.severity == .warning ? TeslaCamTheme.Colors.gapAccent : TeslaCamTheme.Colors.textPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(TeslaCamTheme.Spacing.m)
          .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
        }
      }
    }
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}

private struct TelemetryGrid: View {
  let model: TelemetryDisplayModel

  var body: some View {
    VStack(spacing: TeslaCamTheme.Spacing.s) {
      HStack(spacing: TeslaCamTheme.Spacing.s) {
        TelemetryMetric(title: "Speed", value: model.speedText)
        TelemetryMetric(title: "Pedal", value: model.acceleratorText)
      }
      HStack(spacing: TeslaCamTheme.Spacing.s) {
        TelemetryMetric(title: "Steer", value: model.steeringText)
        TelemetryMetric(title: "Gear", value: model.gear)
      }
      HStack(spacing: TeslaCamTheme.Spacing.s) {
        TelemetryMetric(title: "AP", value: model.autopilot)
        TelemetryMetric(title: "Brake", value: model.brakeApplied ? "On" : "Off")
      }
      TelemetryMetric(title: "GPS", value: model.locationText)
    }
  }
}

private struct TelemetryMetric: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.xs) {
      Text(title.uppercased())
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      Text(value)
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(TeslaCamTheme.Spacing.m)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}

private struct EmptyTelemetryCard: View {
  var body: some View {
    Text("No telemetry")
      .font(TeslaCamTheme.Typography.body)
      .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      .frame(maxWidth: .infinity, minHeight: 96)
      .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}

private struct PrivacyTelemetryCard: View {
  var body: some View {
    Text("Hidden")
      .font(TeslaCamTheme.Typography.body)
      .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      .frame(maxWidth: .infinity, minHeight: 96)
      .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
  }
}

private struct RouteMiniMapView: View {
  let route: [TelemetryRoutePoint]
  let fallback: TelemetryCoordinate?
  let currentSeconds: Double

  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14)
      context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(TeslaCamTheme.Colors.surfaceElevated))
      let points = route.map(\.coordinate)
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

      if route.count > 1 {
        var path = Path()
        for (index, item) in route.enumerated() {
          let p = point(item.coordinate)
          index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        context.stroke(path, with: .color(TeslaCamTheme.Colors.accent), lineWidth: 3)
      }

      let current = route.last { $0.seconds <= currentSeconds }?.coordinate ?? usable.last
      if let current {
        let p = point(current)
        context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.white))
      }
    }
  }
}

private struct IPadExportOptionsPanel: View {
  @ObservedObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: TeslaCamTheme.Spacing.rowGap) {
      Text("Export")
        .font(TeslaCamTheme.Typography.sectionTitle)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary)

      Toggle("HUD", isOn: Binding(
        get: { state.exportOverlayOptions.telemetryHUD },
        set: { state.exportOverlayOptions.telemetryHUD = $0 }
      ))
      Toggle("Map", isOn: Binding(
        get: { state.exportOverlayOptions.routeMap },
        set: { state.exportOverlayOptions.routeMap = $0 }
      ))
      Toggle("Mask", isOn: Binding(
        get: { state.exportOverlayOptions.privacyMask },
        set: { state.exportOverlayOptions.privacyMask = $0 }
      ))
      Toggle("Report", isOn: Binding(
        get: { state.exportOverlayOptions.includeReport },
        set: { state.exportOverlayOptions.includeReport = $0 }
      ))
      Toggle("Poster", isOn: Binding(
        get: { state.exportOverlayOptions.includeScreenshot },
        set: { state.exportOverlayOptions.includeScreenshot = $0 }
      ))

      HStack(spacing: TeslaCamTheme.Spacing.s) {
        Button {
          state.exportPreviewSample()
        } label: {
          Label("Preview", systemImage: "play.rectangle")
        }
        .buttonStyle(QuickActionButtonStyle())
        .disabled(state.exporter.isExporting)

        Button {
          state.queueExportRange()
        } label: {
          Label("Queue", systemImage: "text.badge.plus")
        }
        .buttonStyle(QuickActionButtonStyle())
      }

      if state.exporter.queuedRequests.count > 0 {
        HStack {
          Text("Queued \(state.exporter.queuedRequests.count)")
            .font(TeslaCamTheme.Typography.monoSmall)
            .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
          Spacer()
          Button("Clear") {
            state.exporter.clearQueue()
          }
          .buttonStyle(QuickActionButtonStyle())
        }
      }

      HStack(spacing: TeslaCamTheme.Spacing.s) {
        Button {
          copyLayout()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(QuickActionButtonStyle())

        Button {
          pasteLayout()
        } label: {
          Label("Paste", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(QuickActionButtonStyle())
      }

      if !state.layoutPresetStatus.isEmpty {
        Text(state.layoutPresetStatus)
          .font(TeslaCamTheme.Typography.monoSmall)
          .foregroundStyle(TeslaCamTheme.Colors.textTertiary)
      }
    }
    .font(TeslaCamTheme.Typography.body)
    .foregroundStyle(TeslaCamTheme.Colors.textSecondary)
    .padding(TeslaCamTheme.Metrics.cardPaddingCompact)
    .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.compactCorner)
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
#endif

private struct OnboardingScreen: View {
  @ObservedObject var state: AppState

  var body: some View {
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

        Button("Choose Folder") { state.chooseFolder() }
          .buttonStyle(PrimaryButtonStyle(fixedWidth: 340))
          .disabled(state.exporter.isExporting)
          .accessibilityIdentifier("choose-folder")
      }

      Spacer()
    }
    .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    .accessibilityIdentifier("onboarding-screen")
  }
}

private struct IndexingScreen: View {
  @ObservedObject var state: AppState

  var body: some View {
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
              focusedCamera: state.focusedCamera
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
        .padding(.horizontal, TeslaCamTheme.Metrics.pillPaddingHorizontal)
        .padding(.vertical, TeslaCamTheme.Metrics.pillPaddingVertical)
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
            .lineLimit(2)
            .padding(.horizontal, TeslaCamTheme.Metrics.pillPaddingHorizontal)
            .padding(.vertical, TeslaCamTheme.Metrics.pillPaddingVertical)
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
        .buttonStyle(IconButtonStyle(prominent: true))
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

      // ── Row 4: Camera toggles ────────────────────────────
      CameraToggleRow(state: state)

      ExportConfidenceStrip(
        duplicateSummaryText: state.duplicateSummaryText,
        partialSelectedSetCount: state.partialSelectedSetCount,
        hiddenCameraNames: state.hiddenExportCameraNames,
        gapCount: state.timelineGapRanges.count
      )

      // ── Row 5: Quick range + Duplicate + Export ───────────
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
    .teslaCamCard()
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
    HStack(spacing: TeslaCamTheme.Spacing.s) {
      ForEach(state.camerasDetected, id: \.self) { camera in
        Button {
          let isEnabled = state.activeExportCameras.contains(camera)
          state.toggleExportCamera(camera, isEnabled: !isEnabled)
        } label: {
          HStack(spacing: TeslaCamTheme.Spacing.tightGap) {
            Image(systemName: state.activeExportCameras.contains(camera) ? "checkmark.circle.fill" : "circle")
              .font(TeslaCamTheme.Typography.label)
            Text(camera.shortName)
              .font(TeslaCamTheme.Typography.label)
              .lineLimit(1)
          }
          .foregroundStyle(state.activeExportCameras.contains(camera) ? TeslaCamTheme.Colors.textPrimary : TeslaCamTheme.Colors.textSecondary)
          .padding(.horizontal, TeslaCamTheme.Metrics.pillPaddingHorizontal)
          .padding(.vertical, TeslaCamTheme.Metrics.pillPaddingVertical)
          .frame(maxWidth: .infinity, minHeight: 36)
          .background(
            RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
              .fill(state.activeExportCameras.contains(camera) ? TeslaCamTheme.Colors.surfaceElevated : TeslaCamTheme.Colors.surface)
          )
          .overlay(
            RoundedRectangle(cornerRadius: TeslaCamTheme.Metrics.compactCorner, style: .continuous)
              .stroke(state.activeExportCameras.contains(camera) ? TeslaCamTheme.Colors.accent.opacity(0.5) : TeslaCamTheme.Colors.stroke, lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(camera.displayName)
        .accessibilityValue(state.activeExportCameras.contains(camera) ? "Included" : "Excluded")
        .accessibilityHint("Toggles whether this camera appears in the export.")
        .accessibilityIdentifier("camera-\(camera.rawValue)")
      }
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
        systemImage: gapCount == 0 ? "checkmark.circle" : "waveform.path.ecg"
      )

      ExportConfidenceChip(
        title: "Partial",
        value: "\(partialSelectedSetCount)",
        systemImage: partialSelectedSetCount == 0 ? "checkmark.circle" : "rectangle.split.2x1"
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
    .padding(.horizontal, TeslaCamTheme.Metrics.pillPaddingHorizontal)
    .padding(.vertical, TeslaCamTheme.Metrics.pillPaddingVertical)
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
        Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 12, weight: .semibold))
        Text(title)
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(enabled ? TeslaCamTheme.Colors.textPrimary : TeslaCamTheme.Colors.textSecondary)
      .padding(.horizontal, TeslaCamTheme.Metrics.pillPaddingHorizontal)
      .padding(.vertical, TeslaCamTheme.Metrics.pillPaddingVertical)
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
      .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurfaceStrong, radius: TeslaCamTheme.Metrics.cardCorner + 4)
      .padding(.horizontal, TeslaCamTheme.Spacing.screen)
    }
    .allowsHitTesting(true)
    .accessibilityIdentifier("export-overlay")
    .zIndex(20)
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
      .teslaCamCard(fill: TeslaCamTheme.Colors.surface, radius: TeslaCamTheme.Metrics.controlCorner)
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
      Circle()
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
        RoundedRectangle(cornerRadius: 2, style: .continuous)
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
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

        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(TeslaCamTheme.Colors.accentSoft)
          .frame(width: selectionWidth, height: laneHeight)
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(TeslaCamTheme.Colors.controlKnob)
        .frame(width: 6, height: 26)
        .overlay(
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .stroke(TeslaCamTheme.Colors.controlKnobStroke, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 1)
    }
  }

  private var playhead: some View {
    ZStack(alignment: .center) {
      Color.clear.frame(width: 16, height: 44)
      Capsule(style: .continuous)
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
      RoundedRectangle(cornerRadius: 8, style: .continuous)
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
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(spacing: 0) {
        Rectangle()
          .fill(TeslaCamTheme.Colors.gapAccent.opacity(0.85))
          .frame(height: 2)
        Spacer()
        Rectangle()
          .fill(TeslaCamTheme.Colors.gapAccent.opacity(0.35))
          .frame(height: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      if showLabel {
        Text("Gap")
          .font(TeslaCamTheme.Typography.label)
          .foregroundStyle(TeslaCamTheme.Colors.textPrimary)
          .padding(.horizontal, TeslaCamTheme.Spacing.s)
          .padding(.vertical, TeslaCamTheme.Spacing.xs)
          .teslaCamCard(fill: TeslaCamTheme.Colors.overlaySurface, radius: 999)
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
