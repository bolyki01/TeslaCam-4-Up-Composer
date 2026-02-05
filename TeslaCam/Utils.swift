import Foundation

func formatDateTime(_ date: Date) -> String {
  let df = DateFormatter()
  df.locale = Locale(identifier: "en_US_POSIX")
  df.timeZone = TimeZone.current
  df.dateFormat = "yyyy-MM-dd HH:mm:ss"
  return df.string(from: date)
}

func formatHMS(_ seconds: Double) -> String {
  let total = max(0, Int(seconds.rounded()))
  let h = total / 3600
  let m = (total % 3600) / 60
  let s = total % 60
  return String(format: "%02d:%02d:%02d", h, m, s)
}

func floorToMinute(_ date: Date) -> Date {
  let calendar = Calendar.current
  let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
  return calendar.date(from: comps) ?? date
}

extension Array {
  subscript(safe index: Int) -> Element? {
    guard index >= 0 && index < count else { return nil }
    return self[index]
  }
}
