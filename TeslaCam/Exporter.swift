import Foundation
import Combine
import AppKit

final class ExportController: ObservableObject {
  @Published var isExporting: Bool = false
  @Published var log: String = ""
  @Published var lastError: String = ""
  @Published var progress: Double = 0
  @Published var progressLabel: String = ""
  @Published var isProgressIndeterminate: Bool = true

  private let fm = FileManager.default
  private var progressTimer: DispatchSourceTimer?
  private lazy var logFileURL: URL = {
    let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = base.appendingPathComponent("TeslaCam", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("export.log")
  }()

  private enum ExportError: LocalizedError {
    case processLaunchFailed(String)

    var errorDescription: String? {
      switch self {
      case .processLaunchFailed(let detail):
        return "Failed to launch composer: \(detail)"
      }
    }
  }

  func export(sets: [ClipSet], outputURL: URL, useSixCam: Bool) {
    guard !isExporting else { return }
    guard let scriptURL = bundledScriptURL(useSixCam: useSixCam) else {
      lastError = "Composer script not found."
      return
    }

    isExporting = true
    log = ""
    lastError = ""
    progress = 0
    progressLabel = ""
    isProgressIndeterminate = true
    resetLogFile()
    appendLog("Log file: \(logFileURL.path)\n")
    appendLog("Export start: \(Date())\n")
    appendLog("Output: \(outputURL.path)\n")
    appendLog("Script: \(scriptURL.path)\n")

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent("teslacam_export_\(UUID().uuidString)")
        let inputDir = tempRoot.appendingPathComponent("input")
        let workDir = tempRoot.appendingPathComponent("parts")
        try self.fm.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try self.fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        try self.populateInputFolder(sets: sets, inputDir: inputDir)
        let ffmpegPaths = self.bundledFfmpegPaths()

        DispatchQueue.main.async {
          self.startProgress(expectedParts: sets.count, partsDir: workDir)
        }

        let runnableScript = scriptURL
        DispatchQueue.main.async {
          self.appendLog("Runnable script: \(runnableScript.path)\n")
          let exists = self.fm.fileExists(atPath: runnableScript.path)
          let readable = self.fm.isReadableFile(atPath: runnableScript.path)
          let exec = self.fm.isExecutableFile(atPath: runnableScript.path)
          self.appendLog("Runnable exists: \(exists) readable: \(readable) executable: \(exec)\n")
        }

        try self.runComposer(script: runnableScript, inputDir: inputDir, outputURL: outputURL, workDir: workDir, ffmpegPaths: ffmpegPaths)
      } catch {
        DispatchQueue.main.async {
          let detail = (error as NSError)
          self.appendLog("Export failed: \(error.localizedDescription) [\(detail.domain) \(detail.code)]\n")
          self.lastError = "Export failed: \(error.localizedDescription)"
          self.isExporting = false
          self.stopProgress()
        }
      }
    }
  }

  private func populateInputFolder(sets: [ClipSet], inputDir: URL) throws {
    for set in sets {
      for (camera, src) in set.files {
        let ext = src.pathExtension.isEmpty ? "mp4" : src.pathExtension
        let name = "\(set.timestamp)-\(camera.rawValue).\(ext)"
        let dest = inputDir.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) { continue }
        if !fm.isReadableFile(atPath: src.path) { continue }
        // Use hard links for speed; fallback to copy
        do {
          try fm.linkItem(at: src, to: dest)
        } catch {
          try fm.copyItem(at: src, to: dest)
        }
      }
    }
  }

  private func runComposer(script: URL, inputDir: URL, outputURL: URL, workDir: URL, ffmpegPaths: (ffmpeg: String, ffprobe: String)?) throws {
    guard fm.fileExists(atPath: script.path) else {
      throw ExportError.processLaunchFailed("Script missing at \(script.path)")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [script.path, inputDir.path, outputURL.path]
    process.qualityOfService = .userInitiated

    var env = ProcessInfo.processInfo.environment
    env["PRESET"] = "HEVC_MAX"
    env["VT_Q"] = "16"
    env["GOP"] = "36"
    env["FFLOGLEVEL"] = "info"
    env["WORKDIR"] = workDir.path
    if let paths = ffmpegPaths {
      let existing = env["PATH"] ?? ""
      let binDir = URL(fileURLWithPath: paths.ffmpeg).deletingLastPathComponent().path
      env["PATH"] = binDir + ":" + existing
      env["FFMPEG"] = paths.ffmpeg
      env["FFPROBE"] = paths.ffprobe
      DispatchQueue.main.async {
        self.appendLog("Using bundled ffmpeg: \(binDir)\n")
        self.appendLog("FFMPEG=\(paths.ffmpeg)\n")
        self.appendLog("FFPROBE=\(paths.ffprobe)\n")
        self.appendLog("PATH=\(env["PATH"] ?? "")\n")
      }
    } else {
      DispatchQueue.main.async {
        self.appendLog("Using system ffmpeg from PATH\n")
        self.appendLog("PATH=\(env["PATH"] ?? "")\n")
      }
    }
    process.environment = env

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = nil

    let handle = pipe.fileHandleForReading
    handle.readabilityHandler = { [weak self] h in
      let data = h.availableData
      if data.isEmpty { return }
      if let str = String(data: data, encoding: .utf8) {
        DispatchQueue.main.async {
          self?.appendLog(str)
        }
      }
    }

    do {
      try process.run()
    } catch {
      let detail = (error as NSError)
      DispatchQueue.main.async {
        self.appendLog("Process launch failed: \(detail.domain) \(detail.code) \(detail.localizedDescription)\n")
      }
      throw ExportError.processLaunchFailed(detail.localizedDescription)
    }
    process.waitUntilExit()

    DispatchQueue.main.async {
      handle.readabilityHandler = nil
      if process.terminationStatus == 0 {
        self.appendLog("\nDone: \(outputURL.path)\n")
        self.isExporting = false
        self.stopProgress()
      } else {
        self.appendLog("\nComposer exited with status \(process.terminationStatus) reason \(process.terminationReason.rawValue).\n")
        self.lastError = "Composer exited with status \(process.terminationStatus)."
        self.isExporting = false
        self.stopProgress()
      }
    }
  }

  private func appendLog(_ text: String) {
    let maxLen = 60000
    log.append(text)
    if log.count > maxLen {
      log = String(log.suffix(maxLen))
    }
    appendLogToFile(text)
  }

  private func resetLogFile() {
    if fm.fileExists(atPath: logFileURL.path) {
      try? fm.removeItem(at: logFileURL)
    }
    fm.createFile(atPath: logFileURL.path, contents: nil)
  }

  private func appendLogToFile(_ text: String) {
    guard let data = text.data(using: .utf8) else { return }
    guard fm.fileExists(atPath: logFileURL.path) else {
      fm.createFile(atPath: logFileURL.path, contents: data)
      return
    }
    if let handle = try? FileHandle(forWritingTo: logFileURL) {
      do {
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        // ignore file logging errors
      }
      try? handle.close()
    }
  }

  private func bundledScriptURL(useSixCam: Bool) -> URL? {
    let name = useSixCam ? "teslacam_6up_all_max" : "teslacam_4up_all_max"
    #if SWIFT_PACKAGE
    return Bundle.module.url(forResource: name, withExtension: "sh")
    #else
    return Bundle.main.url(forResource: name, withExtension: "sh")
    #endif
  }

  private func bundledFfmpegPaths() -> (ffmpeg: String, ffprobe: String)? {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    if let dir = bundle.resourceURL?.appendingPathComponent("ffmpeg_bin") {
      let ffmpeg = dir.appendingPathComponent("ffmpeg")
      let ffprobe = dir.appendingPathComponent("ffprobe")
      if fm.fileExists(atPath: ffmpeg.path), fm.fileExists(atPath: ffprobe.path) {
        return (ffmpeg.path, ffprobe.path)
      }
    }
    if let ffmpeg = bundle.url(forResource: "ffmpeg", withExtension: nil),
       let ffprobe = bundle.url(forResource: "ffprobe", withExtension: nil) {
      return (ffmpeg.path, ffprobe.path)
    }
    return nil
  }

  private func startProgress(expectedParts: Int, partsDir: URL) {
    stopProgress()
    progress = 0
    if expectedParts <= 0 {
      isProgressIndeterminate = true
      progressLabel = ""
      return
    }
    isProgressIndeterminate = false
    progressLabel = "0 / \(expectedParts)"
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .milliseconds(500))
    timer.setEventHandler { [weak self] in
      guard let self = self else { return }
      let count = (try? self.fm.contentsOfDirectory(at: partsDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "mp4" }.count) ?? 0
      DispatchQueue.main.async {
        let capped = min(count, expectedParts)
        self.progress = expectedParts > 0 ? Double(capped) / Double(expectedParts) : 0
        self.progressLabel = "\(capped) / \(expectedParts)"
      }
    }
    timer.resume()
    progressTimer = timer
  }

  private func stopProgress() {
    progressTimer?.cancel()
    progressTimer = nil
    progressLabel = ""
    progress = 0
    isProgressIndeterminate = true
  }
}
