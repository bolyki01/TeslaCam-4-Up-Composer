import Foundation

struct SeiMetadata: Hashable {
  enum Gear: Int {
    case park = 0
    case drive = 1
    case reverse = 2
    case neutral = 3
  }

  enum AutopilotState: Int {
    case none = 0
    case selfDriving = 1
    case autosteer = 2
    case tacc = 3
  }

  var version: UInt32 = 0
  var gearState: Gear = .park
  var frameSeqNo: UInt64 = 0
  var vehicleSpeedMps: Float = 0
  var acceleratorPedalPosition: Float = 0
  var steeringWheelAngle: Float = 0
  var blinkerLeft: Bool = false
  var blinkerRight: Bool = false
  var brakeApplied: Bool = false
  var autopilotState: AutopilotState = .none
  var latitudeDeg: Double = 0
  var longitudeDeg: Double = 0
  var headingDeg: Double = 0
  var linearAccelX: Double = 0
  var linearAccelY: Double = 0
  var linearAccelZ: Double = 0
}

struct TelemetryFrame: Hashable {
  let timestampMs: Double
  let sei: SeiMetadata
}

struct TelemetryTimeline {
  let frames: [TelemetryFrame]

  func closest(to timeMs: Double) -> TelemetryFrame? {
    guard !frames.isEmpty else { return nil }
    var lo = 0
    var hi = frames.count - 1
    while lo < hi {
      let mid = (lo + hi) / 2
      if frames[mid].timestampMs < timeMs {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo == 0 { return frames[0] }
    let prev = frames[lo - 1]
    let curr = frames[lo]
    return (abs(prev.timestampMs - timeMs) <= abs(curr.timestampMs - timeMs)) ? prev : curr
  }
}

final class TelemetryParser {
  static func parseTimeline(url: URL) throws -> TelemetryTimeline {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let mp4 = DashcamMP4(data: data)
    let frames = try mp4.parseSeiFrames()
    return TelemetryTimeline(frames: frames)
  }
}

// MARK: - MP4 parsing and SEI extraction

private final class DashcamMP4 {
  private let data: Data

  init(data: Data) {
    self.data = data
  }

  func parseSeiFrames() throws -> [TelemetryFrame] {
    let config = try getConfig()
    let mdat = try findMdat()
    var frames: [TelemetryFrame] = []
    frames.reserveCapacity(1024)

    var cursor = mdat.offset
    let end = mdat.offset + mdat.size

    var pendingSei: SeiMetadata? = nil
    var currentTime: Double = 0
    var frameIndex = 0

    while cursor + 4 <= end {
      let len = Int(readUInt32BE(at: cursor))
      cursor += 4
      if len < 1 || cursor + len > end { break }

      let type = data[cursor] & 0x1F
      let nal = data.subdata(in: cursor..<(cursor + len))

      if type == 6 {
        pendingSei = decodeSei(nal: nal)
      } else if type == 5 || type == 1 {
        let duration = (frameIndex < config.durations.count) ? config.durations[frameIndex] : 33.333
        if let sei = pendingSei {
          frames.append(TelemetryFrame(timestampMs: currentTime, sei: sei))
        }
        currentTime += duration
        frameIndex += 1
        pendingSei = nil
      }

      cursor += len
    }

    return frames
  }

  private func getConfig() throws -> MP4Config {
    let moov = try findBox(start: 0, end: data.count, name: "moov")
    let trak = try findBox(start: moov.start, end: moov.end, name: "trak")
    let mdia = try findBox(start: trak.start, end: trak.end, name: "mdia")
    let minf = try findBox(start: mdia.start, end: mdia.end, name: "minf")
    let stbl = try findBox(start: minf.start, end: minf.end, name: "stbl")
    let stsd = try findBox(start: stbl.start, end: stbl.end, name: "stsd")
    let avc1 = try findBox(start: stsd.start + 8, end: stsd.end, name: "avc1")
    let avcC = try findBox(start: avc1.start + 78, end: avc1.end, name: "avcC")

    let o = avcC.start
    _ = readUInt8(at: o + 1) // profile

    // Extract SPS/PPS length (unused but matches JS config layout)
    var p = o + 6
    let spsLen = Int(readUInt16BE(at: p))
    p += 2 + spsLen + 1
    let _ = Int(readUInt16BE(at: p))

    let mdhd = try findBox(start: mdia.start, end: mdia.end, name: "mdhd")
    let mdhdVersion = readUInt8(at: mdhd.start)
    let timescale: UInt32
    if mdhdVersion == 1 {
      timescale = readUInt32BE(at: mdhd.start + 20)
    } else {
      timescale = readUInt32BE(at: mdhd.start + 12)
    }

    let stts = try findBox(start: stbl.start, end: stbl.end, name: "stts")
    let entryCount = Int(readUInt32BE(at: stts.start + 4))
    var durations: [Double] = []
    durations.reserveCapacity(2048)

    var pos = stts.start + 8
    for _ in 0..<entryCount {
      let count = Int(readUInt32BE(at: pos))
      let delta = Int(readUInt32BE(at: pos + 4))
      let ms = (Double(delta) / Double(timescale)) * 1000.0
      if count > 0 {
        for _ in 0..<count {
          durations.append(ms)
        }
      }
      pos += 8
    }

    return MP4Config(durations: durations)
  }

  private func findMdat() throws -> (offset: Int, size: Int) {
    let mdat = try findBox(start: 0, end: data.count, name: "mdat")
    return (offset: mdat.start, size: mdat.size)
  }

  private func findBox(start: Int, end: Int, name: String) throws -> (start: Int, end: Int, size: Int) {
    var pos = start
    while pos + 8 <= end {
      var size = Int(readUInt32BE(at: pos))
      let type = readAscii(at: pos + 4, len: 4)
      let headerSize = (size == 1) ? 16 : 8

      if size == 1 {
        let high = UInt64(readUInt32BE(at: pos + 8))
        let low = UInt64(readUInt32BE(at: pos + 12))
        size = Int((high << 32) | low)
      } else if size == 0 {
        size = end - pos
      }

      if type == name {
        let contentStart = pos + headerSize
        let contentEnd = pos + size
        return (start: contentStart, end: contentEnd, size: size - headerSize)
      }
      pos += size
    }
    throw NSError(domain: "DashcamMP4", code: 1, userInfo: [NSLocalizedDescriptionKey: "Box not found: \(name)"])
  }

  private func decodeSei(nal: Data) -> SeiMetadata? {
    if nal.count < 4 { return nil }
    var i = 3
    while i < nal.count && nal[i] == 0x42 { i += 1 }
    if i <= 3 || i + 1 >= nal.count { return nil }
    if nal[i] != 0x69 { return nil }
    let payload = nal.subdata(in: (i + 1)..<(nal.count - 1))
    let stripped = stripEmulationBytes(data: payload)
    return ProtoSeiDecoder.decode(stripped)
  }

  private func stripEmulationBytes(data: Data) -> Data {
    var out = [UInt8]()
    out.reserveCapacity(data.count)
    var zeros = 0
    for byte in data {
      if zeros >= 2 && byte == 0x03 {
        zeros = 0
        continue
      }
      out.append(byte)
      zeros = (byte == 0) ? (zeros + 1) : 0
    }
    return Data(out)
  }

  private func readUInt8(at offset: Int) -> UInt8 {
    return data[offset]
  }

  private func readUInt16BE(at offset: Int) -> UInt16 {
    let b0 = UInt16(data[offset]) << 8
    let b1 = UInt16(data[offset + 1])
    return b0 | b1
  }

  private func readUInt32BE(at offset: Int) -> UInt32 {
    let b0 = UInt32(data[offset]) << 24
    let b1 = UInt32(data[offset + 1]) << 16
    let b2 = UInt32(data[offset + 2]) << 8
    let b3 = UInt32(data[offset + 3])
    return b0 | b1 | b2 | b3
  }

  private func readAscii(at offset: Int, len: Int) -> String {
    guard offset + len <= data.count else { return "" }
    return String(bytes: data[offset..<(offset + len)], encoding: .ascii) ?? ""
  }
}

private struct MP4Config {
  let durations: [Double]
}

// MARK: - Minimal protobuf decoder for SeiMetadata

private enum ProtoSeiDecoder {
  static func decode(_ data: Data) -> SeiMetadata? {
    var reader = ProtoReader(data: data)
    var msg = SeiMetadata()

    while !reader.isAtEnd {
      guard let key = reader.readVarint() else { break }
      let field = Int(key >> 3)
      let wire = Int(key & 0x7)

      switch field {
      case 1:
        if let v = reader.readVarint() { msg.version = UInt32(truncatingIfNeeded: v) } else { return nil }
      case 2:
        if let v = reader.readVarint() { msg.gearState = SeiMetadata.Gear(rawValue: Int(v)) ?? .park } else { return nil }
      case 3:
        if let v = reader.readVarint() { msg.frameSeqNo = v } else { return nil }
      case 4:
        if let v = reader.readFixed32() { msg.vehicleSpeedMps = Float(bitPattern: v) } else { return nil }
      case 5:
        if let v = reader.readFixed32() { msg.acceleratorPedalPosition = Float(bitPattern: v) } else { return nil }
      case 6:
        if let v = reader.readFixed32() { msg.steeringWheelAngle = Float(bitPattern: v) } else { return nil }
      case 7:
        if let v = reader.readVarint() { msg.blinkerLeft = v != 0 } else { return nil }
      case 8:
        if let v = reader.readVarint() { msg.blinkerRight = v != 0 } else { return nil }
      case 9:
        if let v = reader.readVarint() { msg.brakeApplied = v != 0 } else { return nil }
      case 10:
        if let v = reader.readVarint() { msg.autopilotState = SeiMetadata.AutopilotState(rawValue: Int(v)) ?? .none } else { return nil }
      case 11:
        if let v = reader.readFixed64() { msg.latitudeDeg = Double(bitPattern: v) } else { return nil }
      case 12:
        if let v = reader.readFixed64() { msg.longitudeDeg = Double(bitPattern: v) } else { return nil }
      case 13:
        if let v = reader.readFixed64() { msg.headingDeg = Double(bitPattern: v) } else { return nil }
      case 14:
        if let v = reader.readFixed64() { msg.linearAccelX = Double(bitPattern: v) } else { return nil }
      case 15:
        if let v = reader.readFixed64() { msg.linearAccelY = Double(bitPattern: v) } else { return nil }
      case 16:
        if let v = reader.readFixed64() { msg.linearAccelZ = Double(bitPattern: v) } else { return nil }
      default:
        if !reader.skipField(wireType: wire) { return nil }
      }
    }

    return msg
  }
}

private struct ProtoReader {
  private let data: Data
  private var offset: Int = 0

  init(data: Data) {
    self.data = data
  }

  var isAtEnd: Bool { offset >= data.count }

  mutating func readVarint() -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while offset < data.count {
      let byte = data[offset]
      offset += 1
      result |= UInt64(byte & 0x7F) << shift
      if (byte & 0x80) == 0 { return result }
      shift += 7
      if shift > 63 { return nil }
    }
    return nil
  }

  mutating func readFixed32() -> UInt32? {
    guard offset + 4 <= data.count else { return nil }
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1]) << 8
    let b2 = UInt32(data[offset + 2]) << 16
    let b3 = UInt32(data[offset + 3]) << 24
    offset += 4
    return b0 | b1 | b2 | b3
  }

  mutating func readFixed64() -> UInt64? {
    guard offset + 8 <= data.count else { return nil }
    var value: UInt64 = 0
    for i in 0..<8 {
      value |= UInt64(data[offset + i]) << (UInt64(i) * 8)
    }
    offset += 8
    return value
  }

  mutating func skipField(wireType: Int) -> Bool {
    switch wireType {
    case 0:
      return readVarint() != nil
    case 1:
      guard offset + 8 <= data.count else { return false }
      offset += 8
      return true
    case 2:
      guard let len = readVarint() else { return false }
      let l = Int(len)
      guard offset + l <= data.count else { return false }
      offset += l
      return true
    case 5:
      guard offset + 4 <= data.count else { return false }
      offset += 4
      return true
    default:
      return false
    }
  }
}
