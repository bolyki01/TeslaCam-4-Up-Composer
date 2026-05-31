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
    #if os(iOS)
    static let background = Color(red: 0.045, green: 0.047, blue: 0.055)
    static let backgroundGlow = Color(red: 0.18, green: 0.36, blue: 0.78).opacity(0.22)
    static let backgroundWarmGlow = Color(red: 0.90, green: 0.34, blue: 0.22).opacity(0.10)
    static let surface = Color.white.opacity(0.055)
    static let surfaceElevated = Color.white.opacity(0.09)
    static let chromeBar = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.12)
    static let accent = Color(red: 0.34, green: 0.58, blue: 0.98)
    static let accentSoft = accent.opacity(0.24)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.50)
    static let gapFill = Color(red: 0.18, green: 0.13, blue: 0.18)
    static let gapAccent = Color(red: 0.95, green: 0.42, blue: 0.30)
    static let overlayScrim = Color.black.opacity(0.56)
    static let overlaySurface = Color.black.opacity(0.32)
    static let overlaySurfaceStrong = Color.black.opacity(0.54)
    static let controlKnob = Color.white.opacity(0.90)
    static let controlKnobStroke = Color.white.opacity(0.24)
    #else
    static let background = Color(red: 0.045, green: 0.047, blue: 0.055)
    static let backgroundGlow = Color(red: 0.22, green: 0.45, blue: 0.92).opacity(0.16)
    static let backgroundWarmGlow = Color(red: 0.93, green: 0.38, blue: 0.28).opacity(0.08)
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
    #endif
  }

  enum Metrics {
    /// Primary action button height. Honors Apple HIG 44pt minimum tap target.
    static let controlHeight: CGFloat = 44
    /// Compact / icon button height. 44 on iOS, slightly tighter is acceptable on macOS but we keep 44 for parity.
    static let compactControlHeight: CGFloat = 44
    /// Standard chrome strip height (toolbars, status bars).
    static let toolbarHeight: CGFloat = 52

    static let cardCorner: CGFloat = 10
    static let controlCorner: CGFloat = 10
    static let compactCorner: CGFloat = 10

    /// Padding inside a primary content card (e.g. TimelineExportCard, PreviewPanelCard).
    static let cardPadding: CGFloat = 20
    /// Padding inside a secondary / compact card (e.g. StatCard, RangeControlCard, TelemetryMetric).
    static let cardPaddingCompact: CGFloat = 14
    /// Padding inside a small inline chip (chips, info banners).
    static let chipPaddingHorizontal: CGFloat = 12
    static let chipPaddingVertical: CGFloat = 8

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
    static let metricValue = Font.system(size: 13, weight: .semibold, design: .monospaced)
    static let miniMetricValue = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let inspectorChip = Font.system(size: 11, weight: .semibold)
    static let inspectorSymbol = Font.system(size: 12, weight: .semibold)
  }
}

enum SurfaceRole: CaseIterable {
  case panel
  case rail
  case overlay
  case control
  case selected

  var fill: Color {
    switch self {
    case .panel:
      return TeslaCamTheme.Colors.surface
    case .rail:
      return TeslaCamTheme.Colors.surface
    case .overlay:
      return TeslaCamTheme.Colors.overlaySurfaceStrong
    case .control:
      return TeslaCamTheme.Colors.surfaceElevated
    case .selected:
      return TeslaCamTheme.Colors.accentSoft
    }
  }

  var stroke: Color {
    switch self {
    case .selected:
      return TeslaCamTheme.Colors.accent.opacity(0.52)
    default:
      return TeslaCamTheme.Colors.stroke
    }
  }

  var glassTint: Color? {
    switch self {
    case .selected:
      return TeslaCamTheme.Colors.accent.opacity(0.18)
    case .overlay:
      #if os(iOS)
      return Color.white.opacity(0.30)
      #else
      return Color.black.opacity(0.18)
      #endif
    case .control:
      return TeslaCamTheme.Colors.surfaceElevated
    case .panel, .rail:
      return nil
    }
  }
}

enum CompactControlSize: CaseIterable {
  case icon
  case chip
  case command

  var visualWidth: CGFloat {
    switch self {
    case .icon:
      return 36
    case .chip:
      return 72
    case .command:
      return 120
    }
  }

  var visualHeight: CGFloat {
    switch self {
    case .icon:
      return 34
    case .chip:
      return 34
    case .command:
      return 36
    }
  }

  var hitTargetWidth: CGFloat { 44 }
  var hitTargetHeight: CGFloat { 44 }

  var maxWidth: CGFloat {
    switch self {
    case .icon:
      return 44
    case .chip:
      return 120
    case .command:
      return 160
    }
  }
}

struct IPadGridMetrics: Equatable {
  enum LayoutMode {
    case threeZone
  }

  let containerWidth: CGFloat

  var layoutMode: LayoutMode {
    .threeZone
  }

  var gutter: CGFloat { 12 }
  var outerPadding: CGFloat { 12 }

  var eventRailWidth: CGFloat {
    if containerWidth < 900 {
      return min(220, max(152, floor(containerWidth * 0.22 / 4) * 4))
    }
    return min(300, max(276, floor(containerWidth * 0.215 / 4) * 4))
  }

  var inspectorWidth: CGFloat {
    if containerWidth < 900 {
      return min(260, max(196, floor(containerWidth * 0.28 / 4) * 4))
    }
    return min(380, max(340, floor(containerWidth * 0.265 / 4) * 4))
  }

  var centerWidth: CGFloat {
    max(320, containerWidth - eventRailWidth - inspectorWidth - gutter * 2)
  }
}

struct TeslaCamSceneBackground: View {
  var body: some View {
    TeslaCamTheme.Colors.background
      .overlay(
        LinearGradient(
          colors: [Color.white.opacity(0.04), .clear],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(alignment: .topLeading) {
        Rectangle()
          .fill(TeslaCamTheme.Colors.backgroundGlow)
          .frame(width: 520, height: 520)
          .blur(radius: 80)
          .offset(x: -180, y: -220)
      }
      .overlay(alignment: .bottomTrailing) {
        Rectangle()
          .fill(TeslaCamTheme.Colors.backgroundWarmGlow)
          .frame(width: 460, height: 460)
          .blur(radius: 90)
          .offset(x: 180, y: 180)
      }
      .ignoresSafeArea()
  }
}

private struct TeslaCamCardModifier: ViewModifier {
  let fill: Color
  let radius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    #if os(iOS)
    if #available(iOS 26.0, *) {
      content
        .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .glassEffect(.regular.tint(fill), in: .rect(cornerRadius: radius))
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
        )
    } else {
      content
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
        )
    }
    #else
    content
      .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(TeslaCamTheme.Colors.stroke, lineWidth: 1)
      )
    #endif
  }
}

private struct GlassSurfaceModifier: ViewModifier {
  let role: SurfaceRole
  let radius: CGFloat
  let interactive: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    #if os(iOS)
    if #available(iOS 26.0, *) {
      if let tint = role.glassTint {
        content
          .background(role.fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
          .glassEffect(
            .regular.tint(tint).interactive(interactive),
            in: .rect(cornerRadius: radius)
          )
          .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .stroke(role.stroke, lineWidth: 1)
          )
      } else {
        content
          .background(role.fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
          .glassEffect(
            .regular.interactive(interactive),
            in: .rect(cornerRadius: radius)
          )
          .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .stroke(role.stroke, lineWidth: 1)
          )
      }
    } else {
      content
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(role.stroke, lineWidth: 1)
        )
    }
    #else
    content
      .background(role.fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .stroke(role.stroke, lineWidth: 1)
      )
    #endif
  }
}

extension View {
  func glassSurface(
    role: SurfaceRole = .panel,
    radius: CGFloat = TeslaCamTheme.Metrics.cardCorner,
    interactive: Bool = false
  ) -> some View {
    modifier(GlassSurfaceModifier(role: role, radius: radius, interactive: interactive))
  }

  func teslaCamCard(
    fill: Color = TeslaCamTheme.Colors.surface,
    radius: CGFloat = TeslaCamTheme.Metrics.cardCorner
  ) -> some View {
    modifier(TeslaCamCardModifier(fill: fill, radius: radius))
  }

  func compactButtonStyle(
    role: SurfaceRole = .control,
    size: CompactControlSize = .chip
  ) -> some View {
    buttonStyle(CompactButtonStyle(role: role, size: size))
  }

  func preferredTeslaCamColorScheme() -> some View {
    environment(\.colorScheme, .dark)
  }
}

struct GlassEffectGroup<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: () -> Content

  init(spacing: CGFloat = TeslaCamTheme.Spacing.m, @ViewBuilder content: @escaping () -> Content) {
    self.spacing = spacing
    self.content = content
  }

  @ViewBuilder
  var body: some View {
    #if os(iOS)
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) {
        content()
      }
    } else {
      content()
    }
    #else
    content()
    #endif
  }
}

struct CompactButtonStyle: ButtonStyle {
  let role: SurfaceRole
  let size: CompactControlSize

  func makeBody(configuration: Configuration) -> some View {
    ZStack {
      configuration.label
        .font(TeslaCamTheme.Typography.label)
        .foregroundStyle(TeslaCamTheme.Colors.textPrimary.opacity(configuration.isPressed ? 0.72 : 0.96))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, size == .icon ? 0 : TeslaCamTheme.Spacing.m)
        .frame(minWidth: size == .icon ? size.visualWidth : nil)
        .frame(maxWidth: size.maxWidth)
        .frame(height: size.visualHeight)
        .glassSurface(
          role: role,
          radius: TeslaCamTheme.Metrics.compactCorner,
          interactive: true
        )
    }
    .frame(minWidth: size.hitTargetWidth, minHeight: size.hitTargetHeight)
    .opacity(configuration.isPressed ? 0.82 : 1)
    .contentShape(Rectangle())
  }
}
#endif
