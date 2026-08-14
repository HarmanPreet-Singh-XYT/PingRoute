import 'package:fluent_ui/fluent_ui.dart';

/// Central design-system tokens for PingRoute. Every screen should pull
/// colors and type styles from here instead of hardcoding hex values, so
/// the app stays consistent and adapts correctly between light and dark
/// appearance.
class AppColors {
  final Color pageBackground;
  final Color panelBackground;
  final Color panelBackgroundAlt;
  final Color cardBackground;
  final Color borderColor;
  final Color dividerColor;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;

  // Latency-tier semantic colors (used by the navbar legend, stat tiles,
  // and per-hop indicators).
  final Color latencyGood;
  final Color latencyWarn;
  final Color latencyBad;

  // Chart palette.
  final Color chartLine;
  final Color chartLineSecondary;
  final Color chartGrid;
  final Color chartBorder;

  const AppColors({
    required this.pageBackground,
    required this.panelBackground,
    required this.panelBackgroundAlt,
    required this.cardBackground,
    required this.borderColor,
    required this.dividerColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.latencyGood,
    required this.latencyWarn,
    required this.latencyBad,
    required this.chartLine,
    required this.chartLineSecondary,
    required this.chartGrid,
    required this.chartBorder,
  });

  // Values below are the dataviz skill's validated reference palette
  // (references/palette.md) — status colors, sequential blue ramp, and
  // chart chrome — run through scripts/validate_palette.js rather than
  // hand-picked, so contrast/CVD-safety checks are guaranteed to pass.
  static const light = AppColors(
    pageBackground: Color(0xffEFEFEA),
    panelBackground: Color(0xffFFFFFF),
    panelBackgroundAlt: Color(0xffF7F7F4),
    cardBackground: Color(0xffFFFFFF),
    borderColor: Color(0xffD5D4CC),
    dividerColor: Color(0xffDCDBCF),
    textPrimary: Color(0xff121212),
    textSecondary: Color(0xff5A5956),
    accent: Color(0xff2A78D6),
    latencyGood: Color(0xff0CA30C),
    latencyWarn: Color(0xfffab219),
    latencyBad: Color(0xffD03B3B),
    chartLine: Color(0xff2A78D6),
    chartLineSecondary: Color(0xff6DA7EC),
    chartGrid: Color(0xffDCDBCF),
    chartBorder: Color(0xffC3C2B7),
  );

  static const dark = AppColors(
    pageBackground: Color(0xff0D0D0D),
    panelBackground: Color(0xff1A1A19),
    panelBackgroundAlt: Color(0xff202020),
    cardBackground: Color(0xff1A1A19),
    borderColor: Color(0xff2C2C2A),
    dividerColor: Color(0xff2C2C2A),
    textPrimary: Color(0xffFFFFFF),
    textSecondary: Color(0xffC3C2B7),
    accent: Color(0xff3987E5),
    latencyGood: Color(0xff0CA30C),
    latencyWarn: Color(0xfffab219),
    latencyBad: Color(0xffD03B3B),
    chartLine: Color(0xff3987E5),
    chartLineSecondary: Color(0xff5598E7),
    chartGrid: Color(0xff2C2C2A),
    chartBorder: Color(0xff383835),
  );
}

/// Returns the latency-tier color for a ping value, matching the navbar's
/// legend thresholds (0-100 good, 100-200 warn, 200+ bad; unreachable/-1
/// uses the "bad" tier).
Color latencyColor(AppColors colors, int pingMs) {
  if (pingMs < 0) return colors.latencyBad;
  if (pingMs <= 100) return colors.latencyGood;
  if (pingMs <= 200) return colors.latencyWarn;
  return colors.latencyBad;
}

AppColors appColors(BuildContext context) {
  final brightness = FluentTheme.of(context).brightness;
  return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
}

class AppTypography {
  final TextStyle display;
  final TextStyle title;
  final TextStyle subtitle;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle caption;

  const AppTypography({
    required this.display,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bodyStrong,
    required this.caption,
  });

  factory AppTypography.of(Color textPrimary, Color textSecondary) {
    return AppTypography(
      display: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.5),
      title: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
      subtitle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textSecondary),
      body: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: textPrimary),
      bodyStrong: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textPrimary),
      caption: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: textSecondary),
    );
  }
}

AppTypography appTypography(BuildContext context) {
  final colors = appColors(context);
  return AppTypography.of(colors.textPrimary, colors.textSecondary);
}

FluentThemeData buildFluentTheme(Brightness brightness, [Color? systemAccent]) {
  final colors = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final accent = systemAccent != null
      ? AccentColor.swatch({
          'darkest': systemAccent,
          'darker': systemAccent,
          'dark': systemAccent,
          'normal': systemAccent,
          'light': systemAccent,
          'lighter': systemAccent,
          'lightest': systemAccent,
        })
      : Colors.blue;

  return FluentThemeData(
    brightness: brightness,
    accentColor: accent,
    scaffoldBackgroundColor: colors.pageBackground,
    cardColor: colors.cardBackground,
    micaBackgroundColor: colors.pageBackground,
    shadowColor: brightness == Brightness.light ? const Color(0x1A000000) : const Color(0x3A000000),
    typography: Typography.fromBrightness(
      brightness: brightness,
      color: colors.textPrimary,
    ),
  );
}
