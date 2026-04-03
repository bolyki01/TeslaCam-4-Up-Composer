import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @EnvironmentObject var state: AppState
  @State private var showRangeSheet = false
  @State private var showLogSheet = false
  @State private var isDropTarget = false

  var body: some View {
    ZStack {
      background
      VStack(spacing: 12) {
        topBar
        if state.isIndexing {
          ProgressView(state.indexStatus)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        mainArea
      }
      .padding(16)
    }
    .frame(minWidth: 1200, minHeight: 820)
    .environment(\.colorScheme, .dark)
    .onAppear { state.onAppear() }
    .onChange(of: state.exporter.lastError) { _, msg in
      if !msg.isEmpty {
        state.errorMessage = msg
        state.showError = true
      }
    }
    .alert("Error", isPresented: $state.showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(state.errorMessage)
    }
    .sheet(isPresented: $showRangeSheet) {
      RangeSheet()
        .environmentObject(state)
    }
    .sheet(isPresented: $showLogSheet) {
      LogSheet(exporter: state.exporter)
    }
    .sheet(isPresented: Binding(
      get: { state.exporter.isStatusPresented },
      set: { state.exporter.isStatusPresented = $0 }
    )) {
      ExportStatusSheet(exporter: state.exporter)
    }
    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleFileDrop(providers:))
  }

  private var background: some View {
    LinearGradient(
      colors: [Color(red: 0.06, green: 0.07, blue: 0.1), Color(red: 0.09, green: 0.1, blue: 0.15)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .overlay(
      RadialGradient(
        colors: [Color.white.opacity(0.08), Color.clear],
        center: .topTrailing,
        startRadius: 0,
        endRadius: 500
      )
    )
    .ignoresSafeArea()
  }

  private var topBar: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("TeslaCam")
          .font(.system(size: 20, weight: .bold))
        if let minDate = state.minDate, let maxDate = state.maxDate {
          Text("Range: \(formatDateTime(minDate))  ->  \(formatDateTime(maxDate))")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.7))
        } else {
          Text("Select TeslaCam files/folders to begin")
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.7))
        }
        if let health = state.healthSummary {
          Text(healthSummaryLine(health))
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.6))
        }
      }

      Spacer(minLength: 12)

      if !state.sourceSummary.isEmpty {
        Text(state.sourceSummary)
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.white.opacity(0.75))
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 420)
      }

      Spacer(minLength: 12)

      Button("Choose Sources") { state.chooseFolder() }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(state.exporter.isExporting)

      Button("Rescan") {
        if !state.sourceURLs.isEmpty {
          state.indexSources(state.sourceURLs)
        }
      }
      .buttonStyle(SecondaryButtonStyle())
      .disabled(state.sourceURLs.isEmpty || state.exporter.isExporting)
    }
    .padding(12)
    .background(Color.black.opacity(0.35))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    )
    .cornerRadius(12)
  }

  private var mainArea: some View {
    ZStack(alignment: .bottom) {
      videoGrid
      controlBar
    }
  }

  private var videoGrid: some View {
    GeometryReader { geo in
      ZStack(alignment: .topLeading) {
        MetalPlayerView(playback: state.playback, cameraOrder: state.camerasDetected)
          .frame(width: geo.size.width, height: geo.size.height)
          .clipped()
          .cornerRadius(16)

        VStack(alignment: .leading, spacing: 8) {
          if !state.overlayText.isEmpty {
            Text("Recorded: \(state.overlayText)")
              .font(.system(size: 13, weight: .semibold, design: .monospaced))
              .foregroundColor(.white)
              .padding(.vertical, 6)
              .padding(.horizontal, 10)
              .background(Color.black.opacity(0.65))
              .cornerRadius(8)
          }
          if !state.telemetryText.isEmpty {
            Text(state.telemetryText)
              .font(.system(size: 12, weight: .semibold, design: .monospaced))
              .foregroundColor(.white.opacity(0.9))
              .padding(.vertical, 6)
              .padding(.horizontal, 10)
              .background(Color.black.opacity(0.6))
              .cornerRadius(8)
          }
        }
        .padding(12)

        if let job = state.exporter.currentJob, !job.isTerminal {
          ExportOverlayCard(job: job)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }

        if state.clipSets.isEmpty && !state.isIndexing {
          VStack(spacing: 10) {
            Text("No clips loaded")
              .font(.system(size: 18, weight: .semibold))
            Text("Choose or drop TeslaCam files/folders to start playback")
              .font(.system(size: 12))
              .foregroundColor(.white.opacity(0.7))
          }
          .padding(18)
          .background(Color.black.opacity(0.5))
          .cornerRadius(12)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Color.black.opacity(0.9))
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
      .cornerRadius(16)
    }
  }

  private var controlBar: some View {
    VStack(spacing: 10) {
      HStack(spacing: 12) {
        Button(state.playback.isPlaying ? "Pause" : "Play") { state.togglePlay() }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(state.clipSets.isEmpty)

        Button("Restart") { state.restart() }
          .buttonStyle(SecondaryButtonStyle())
          .disabled(state.clipSets.isEmpty)

        Text("\(formatHMS(state.currentSeconds)) / \(formatHMS(state.totalDuration))")
          .font(.system(size: 11))
          .foregroundColor(.white.opacity(0.7))

        Spacer()

        if let job = state.exporter.currentJob {
          VStack(alignment: .trailing, spacing: 2) {
            Text(job.phaseLabel)
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(.white.opacity(0.9))
            Text(job.progressPercentText)
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.white.opacity(0.7))
          }
        }

        Button("Range") { showRangeSheet = true }
          .buttonStyle(SecondaryButtonStyle())
          .disabled(state.exporter.isExporting)

        Button("Status") { state.exporter.isStatusPresented = true }
          .buttonStyle(SecondaryButtonStyle())
          .disabled(state.exporter.currentJob == nil)

        Button("Log") { showLogSheet = true }
          .buttonStyle(SecondaryButtonStyle())

        Button(state.exporter.isExporting ? "Exporting..." : "Export") {
          state.exportRange()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(state.clipSets.isEmpty || state.exporter.isExporting)
      }

      Slider(value: $state.currentSeconds, in: 0...state.totalDuration, onEditingChanged: { editing in
        if editing { state.beginSeek() } else { state.endSeek() }
      })
      .controlSize(.large)
      .disabled(state.clipSets.isEmpty)
      .frame(maxWidth: .infinity)
      .onChange(of: state.currentSeconds) { _, newValue in
        state.liveSeek(to: newValue)
      }
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(Color.black.opacity(0.6))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
    .cornerRadius(16)
    .padding(.bottom, 12)
    .padding(.horizontal, 24)
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
              let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
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

  private func healthSummaryLine(_ health: ExportHealthSummary) -> String {
    var parts = ["\(health.totalMinutes) min", "\(health.gapCount) gap(s)", "\(health.partialSetCount) partial minute(s)"]
    if health.hasMixedCoverage {
      parts.append("mixed 4/6-cam coverage")
    }
    return parts.joined(separator: "  •  ")
  }
}

private struct ExportOverlayCard: View {
  let job: ExportJobSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(job.phase.displayName)
        .font(.system(size: 12, weight: .bold))
      ProgressView(value: job.progress)
        .frame(width: 220)
      Text(job.phaseLabel)
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.8))
      Text(job.detailText)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white.opacity(0.65))
    }
    .padding(12)
    .background(Color.black.opacity(0.7))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
    .cornerRadius(12)
  }
}

private struct RangeSheet: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Export Range")
        .font(.system(size: 20, weight: .bold))

      let min = state.minDate ?? Date()
      let max = state.maxDate ?? Date()

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          DatePicker("Start", selection: $state.selectedStart, in: min...max, displayedComponents: [.date, .hourAndMinute])
            .onChange(of: state.selectedStart) { _, _ in state.normalizeRange() }
          DatePicker("End", selection: $state.selectedEnd, in: min...max, displayedComponents: [.date, .hourAndMinute])
            .onChange(of: state.selectedEnd) { _, _ in state.normalizeRange() }
          HStack(spacing: 10) {
            Button("Full Range") { state.setFullRange() }
              .buttonStyle(SecondaryButtonStyle())
            Button("Current Minute") { state.setCurrentMinuteRange() }
              .buttonStyle(SecondaryButtonStyle())
            Button("Last 5 Min") { state.setRecentRange(minutes: 5) }
              .buttonStyle(SecondaryButtonStyle())
            Button("Last 15 Min") { state.setRecentRange(minutes: 15) }
              .buttonStyle(SecondaryButtonStyle())
          }
        }
      } label: {
        Text("Selection")
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Picker("Preset", selection: $state.exportPreset) {
            ForEach(ExportPreset.allCases) { preset in
              Text(preset.displayName).tag(preset)
            }
          }
          .pickerStyle(.segmented)

          VStack(alignment: .leading, spacing: 8) {
            Text("Cameras")
              .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
              ForEach(state.camerasDetected, id: \.self) { camera in
                Toggle(isOn: Binding(
                  get: { state.activeExportCameras.contains(camera) },
                  set: { state.toggleExportCamera(camera, isEnabled: $0) }
                )) {
                  Text(camera.displayName)
                    .font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.checkbox)
              }
            }
          }
        }
      } label: {
        Text("Output")
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text(state.selectedRangeDescription)
            .font(.system(size: 12, design: .monospaced))
          Text("\(state.selectedSetsForExport.count) minute(s) selected")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.8))
          ForEach(state.exportWarningsPreview, id: \.self) { warning in
            Text(warning)
              .font(.system(size: 11))
              .foregroundColor(Color.orange.opacity(0.95))
          }
          if let health = state.healthSummary, !health.missingCoverageSummary.isEmpty {
            Text("Missing coverage: \(health.missingCoverageSummary)")
              .font(.system(size: 11))
              .foregroundColor(.white.opacity(0.65))
          }
        }
      } label: {
        Text("Preflight Preview")
      }

      HStack(spacing: 12) {
        Button("Export Status") {
          state.exporter.isStatusPresented = true
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(state.exporter.currentJob == nil)

        Spacer()

        Button("Export Range") { state.exportRange() }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(state.clipSets.isEmpty || state.exporter.isExporting)
      }

      Spacer()
    }
    .padding(20)
    .frame(minWidth: 740, minHeight: 520)
  }
}

private struct ExportStatusSheet: View {
  @ObservedObject var exporter: ExportController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Export Status")
          .font(.system(size: 20, weight: .bold))
        Spacer()
        Button("Close") { dismiss() }
          .buttonStyle(SecondaryButtonStyle())
      }

      if let job = exporter.currentJob {
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Text(job.phaseLabel)
              .font(.system(size: 15, weight: .semibold))
            ProgressView(value: job.progress)
              .tint(Color(red: 0.18, green: 0.45, blue: 0.95))
            HStack {
              Text(job.progressPercentText)
              Spacer()
              Text(job.detailText)
              Spacer()
              Text("Elapsed: \(formatHMS(job.elapsedTime))")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.75))

            if let failure = job.failureReason {
              Text("\((job.failureCategory ?? .unknown).displayName): \(failure)")
                .font(.system(size: 11))
                .foregroundColor(job.isCancelled ? .yellow : .red.opacity(0.9))
            }

            HStack(spacing: 10) {
              if exporter.isExporting {
                Button("Cancel Export") { exporter.cancelExport() }
                  .buttonStyle(PrimaryButtonStyle())
              }
              Button("Reveal Log") { exporter.revealLog() }
                .buttonStyle(SecondaryButtonStyle())
              Button("Reveal Output") { exporter.revealOutput(for: job) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!job.canRevealOutput)
              Button("Reveal Working Files") { exporter.revealWorkingFiles(for: job) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!job.canRevealWorkingFiles)
              Button("Retry") { exporter.retry(job) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(exporter.isExporting || !job.canRetry)
            }
          }
        } label: {
          Text("Current Job")
        }
      } else {
        Text("No export has been started in this session.")
          .font(.system(size: 12))
          .foregroundColor(.white.opacity(0.7))
      }

      GroupBox {
        ScrollView {
          Text(exporter.log.isEmpty ? "No export log yet." : exporter.log)
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(minHeight: 220)
      } label: {
        Text("Live Log")
      }

      if !exporter.exportHistory.isEmpty {
        GroupBox {
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(exporter.exportHistory) { job in
                HStack(alignment: .top, spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(job.outputURL.lastPathComponent)
                      .font(.system(size: 12, weight: .semibold))
                    Text(job.request.selectedRangeText)
                      .font(.system(size: 11))
                      .foregroundColor(.white.opacity(0.7))
                    Text("\(job.phase.displayName) • \(formatHMS(job.elapsedTime))")
                      .font(.system(size: 11, design: .monospaced))
                      .foregroundColor(.white.opacity(0.6))
                  }
                  Spacer()
                  Button("Reveal") { exporter.revealOutput(for: job) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!job.canRevealOutput)
                  Button("Retry") { exporter.retry(job) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(exporter.isExporting || !job.canRetry)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
              }
            }
          }
          .frame(minHeight: 150)
        } label: {
          Text("Recent Exports")
        }
      }
    }
    .padding(20)
    .frame(minWidth: 820, minHeight: 720)
  }
}

private struct LogSheet: View {
  @ObservedObject var exporter: ExportController
  @State private var followTail = true
  private let bottomAnchorID = "log-bottom-anchor"

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Export Log")
          .font(.system(size: 20, weight: .bold))
        Spacer()
        Button("Reveal Log") { exporter.revealLog() }
          .buttonStyle(SecondaryButtonStyle())
        if let job = exporter.currentJob {
          Button("Reveal Output") { exporter.revealOutput(for: job) }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!job.canRevealOutput)
          Button("Reveal Working Files") { exporter.revealWorkingFiles(for: job) }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!job.canRevealWorkingFiles)
        }
        Toggle("Follow Tail", isOn: $followTail)
          .toggleStyle(.switch)
          .font(.system(size: 12, weight: .semibold))
      }

      ScrollViewReader { proxy in
        ScrollView {
          Text(exporter.log.isEmpty ? "No export yet." : exporter.log)
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
          Color.clear
            .frame(height: 1)
            .id(bottomAnchorID)
        }
        .frame(minHeight: 280)
        .onAppear {
          if followTail {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
          }
        }
        .onChange(of: exporter.log) { _, _ in
          guard followTail else { return }
          withAnimation(.linear(duration: exporter.isExporting ? 0.08 : 0.02)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
          }
        }
      }

      Spacer()
    }
    .padding(20)
    .frame(minWidth: 760, minHeight: 460)
  }
}

private struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .padding(.vertical, 8)
      .padding(.horizontal, 14)
      .background(Color(red: 0.18, green: 0.45, blue: 0.95))
      .foregroundColor(.white)
      .cornerRadius(10)
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}

private struct SecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .padding(.vertical, 8)
      .padding(.horizontal, 14)
      .background(Color.white.opacity(0.08))
      .foregroundColor(.white)
      .cornerRadius(10)
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}
