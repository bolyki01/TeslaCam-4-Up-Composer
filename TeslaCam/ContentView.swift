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
        Text("TeslaCam Pro")
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

      Button("Rescan") {
        if !state.sourceURLs.isEmpty {
          state.indexSources(state.sourceURLs)
        }
      }
      .buttonStyle(SecondaryButtonStyle())
      .disabled(state.sourceURLs.isEmpty)
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

        Button("Range") { showRangeSheet = true }
          .buttonStyle(SecondaryButtonStyle())

        Button("Log") { showLogSheet = true }
          .buttonStyle(SecondaryButtonStyle())

        Button(state.exporter.isExporting ? "Exporting..." : "Export") {
          state.exportRange()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(state.clipSets.isEmpty || state.exporter.isExporting)

        if state.exporter.isExporting {
          if state.exporter.isProgressIndeterminate {
            ProgressView()
              .progressViewStyle(.circular)
          } else {
            ProgressView(value: state.exporter.progress)
              .frame(width: 140)
            Text(state.exporter.progressLabel)
              .font(.system(size: 11))
              .foregroundColor(.white.opacity(0.7))
          }
        }
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
}

private struct RangeSheet: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Export Range")
        .font(.system(size: 20, weight: .bold))

      let min = state.minDate ?? Date()
      let max = state.maxDate ?? Date()

      DatePicker("Start", selection: $state.selectedStart, in: min...max, displayedComponents: [.date, .hourAndMinute])
        .onChange(of: state.selectedStart) { _, _ in state.normalizeRange() }
      DatePicker("End", selection: $state.selectedEnd, in: min...max, displayedComponents: [.date, .hourAndMinute])
        .onChange(of: state.selectedEnd) { _, _ in state.normalizeRange() }

      HStack(spacing: 12) {
        Button("Full Range") {
          if let minDate = state.minDate, let maxDate = state.maxDate {
            state.selectedStart = minDate
            state.selectedEnd = maxDate
          }
        }
        .buttonStyle(SecondaryButtonStyle())

        Button("Export Range") { state.exportRange() }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(state.clipSets.isEmpty || state.exporter.isExporting)
      }

      Spacer()
    }
    .padding(20)
    .frame(minWidth: 480, minHeight: 260)
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
          // Keep the latest output visible during long exports.
          withAnimation(.linear(duration: exporter.isExporting ? 0.08 : 0.02)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
          }
        }
      }

      Spacer()
    }
    .padding(20)
    .frame(minWidth: 640, minHeight: 420)
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
