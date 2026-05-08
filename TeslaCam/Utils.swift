import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

enum TeslaCamBuildFlags {
#if DEBUG
  static let showsDebugTools = true
#else
  static let showsDebugTools = false
#endif
}

enum TeslaCamFormatters {
  private static func makeFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = format
    return formatter
  }

  static let fullDateTime = makeFormatter("yyyy-MM-dd HH:mm:ss")
  static let shortDate = makeFormatter("MMM d, yyyy")
  static let timelineSameDay = makeFormatter("HH:mm")
  static let timelineTwoDay = makeFormatter("d/MM/yy-HH:mm")
  static let timelineMultiDay = makeFormatter("d/MM/yy")
  static let selectedRange = makeFormatter("d/MM/yy-HH:mm:ss")
  static let eventTimestamp = makeFormatter("yyyy-MM-dd'T'HH:mm:ss")
}

func formatDateTime(_ date: Date) -> String {
  TeslaCamFormatters.fullDateTime.string(from: date)
}

func formatShortDate(_ date: Date) -> String {
  TeslaCamFormatters.shortDate.string(from: date)
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

func ceilToMinute(_ date: Date) -> Date {
  let floored = floorToMinute(date)
  if floored == date {
    return date
  }
  return floored.addingTimeInterval(60)
}

extension Array {
  subscript(safe index: Int) -> Element? {
    guard index >= 0 && index < count else { return nil }
    return self[index]
  }
}

#if canImport(SwiftUI)
enum TeslaCamTheme {
  enum Colors {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let backgroundGlow = Color.white.opacity(0.035)
    static let surface = Color.white.opacity(0.04)
    static let surfaceElevated = Color.white.opacity(0.065)
    static let chromeBar = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.24, green: 0.51, blue: 0.97)
    static let accentSoft = accent.opacity(0.22)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.48)
    static let gapFill = Color(red: 0.17, green: 0.12, blue: 0.12)
    static let gapAccent = Color(red: 0.93, green: 0.38, blue: 0.28)
    static let overlayScrim = Color.black.opacity(0.5)
    static let overlaySurface = Color.white.opacity(0.08)
    static let overlaySurfaceStrong = Color.black.opacity(0.36)
    static let controlKnob = Color.white.opacity(0.88)
    static let controlKnobStroke = Color.white.opacity(0.2)
  }

  enum Metrics {
    /// Primary action button height. Honors Apple HIG 44pt minimum tap target.
    static let controlHeight: CGFloat = 44
    /// Compact / icon button height. 44 on iOS, slightly tighter is acceptable on macOS but we keep 44 for parity.
    static let compactControlHeight: CGFloat = 44
    /// Standard chrome strip height (toolbars, status bars).
    static let toolbarHeight: CGFloat = 52

    static let cardCorner: CGFloat = 16
    static let controlCorner: CGFloat = 12
    static let compactCorner: CGFloat = 10

    /// Padding inside a primary content card (e.g. TimelineExportCard, PreviewPanelCard).
    static let cardPadding: CGFloat = 20
    /// Padding inside a secondary / compact card (e.g. StatCard, RangeControlCard, TelemetryMetric).
    static let cardPaddingCompact: CGFloat = 14
    /// Padding inside a small inline pill (chips, info banners).
    static let pillPaddingHorizontal: CGFloat = 12
    static let pillPaddingVertical: CGFloat = 8

    /// Outer screen-edge padding for top-level content.
    static let contentPadding: CGFloat = 24
  }

  /// 4pt grid. Use semantic helpers (`cardGap`, `rowGap`, `inlineGap`) by preference.
  enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24

    /// Gap between sibling cards in a vertical stack (or between major sections of a screen).
    static let cardGap: CGFloat = 16
    /// Gap between rows of content inside a card.
    static let rowGap: CGFloat = 12
    /// Gap between inline elements in an HStack (icon + text, button group, etc.).
    static let inlineGap: CGFloat = 8
    /// Tight gap for closely-coupled inline elements (icon+label inside a chip).
    static let tightGap: CGFloat = 6

    /// Outer screen-edge padding (matches `Metrics.contentPadding`).
    static let screen: CGFloat = 24
    /// Vertical separation between major page sections.
    static let section: CGFloat = 32
  }

  enum Layout {
    static let toolbarHeight: CGFloat = Metrics.toolbarHeight
    static let narrowPanelWidth: CGFloat = 470
    static let overlayCardWidth: CGFloat = 580
    static let overlayContentWidth: CGFloat = 520
    static let duplicateSheetWidth: CGFloat = 460
  }

  enum Typography {
    static let heroTitle = Font.system(size: 30, weight: .bold)
    static let panelTitle = Font.system(size: 22, weight: .bold)
    static let panelSubtitle = Font.system(size: 15)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 14)
    static let bodySmall = Font.system(size: 13)
    /// Eyebrow / overline label (uppercased small caps style).
    static let label = Font.system(size: 11, weight: .semibold)
    static let monoDetail = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let numericBody = Font.system(size: 15, weight: .semibold, design: .monospaced)
    static let numericLarge = Font.system(size: 18, weight: .semibold, design: .monospaced)
  }
}

struct TeslaCamSceneBackground: View {
  var body: some View {
    TeslaCamTheme.Colors.background
      .overlay(
        LinearGradient(
          colors: [TeslaCamTheme.Colors.backgroundGlow, .clear],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .ignoresSafeArea()
  }
}

private struct TeslaCamCardModifier: ViewModifier {
  let fill: Color
  let radius: CGFloat

  func body(content: Content) -> some View {
    content
      .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
  }
}

extension View {
  func teslaCamCard(
    fill: Color = TeslaCamTheme.Colors.surface,
    radius: CGFloat = TeslaCamTheme.Metrics.cardCorner
  ) -> some View {
    modifier(TeslaCamCardModifier(fill: fill, radius: radius))
  }
}
#endif
