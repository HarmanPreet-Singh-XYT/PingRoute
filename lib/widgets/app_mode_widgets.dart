import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/app_metrics.dart';

/// Copies [text] and confirms with an info bar.
Future<void> copyWithToast(
  BuildContext context,
  String text,
  String what,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on Object {
    if (!context.mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Copy failed'),
        content: Text('Could not copy $what to the clipboard.'),
        severity: InfoBarSeverity.error,
      ),
    );
    return;
  }
  if (!context.mounted) return;
  displayInfoBar(
    context,
    duration: const Duration(seconds: 2),
    builder: (context, close) =>
        InfoBar(title: Text('$what copied'), severity: InfoBarSeverity.success),
  );
}

enum MetricTone { neutral, good, warn, bad }

/// A metric card: icon + label, a big value, a caption and an optional
/// trend line. A coloured edge signals status; clicking copies the value.
class MetricTile extends StatefulWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.valueColor,
    this.tooltip,
    this.icon,
    this.tone = MetricTone.neutral,
    this.trend,
    this.width = 164,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;
  final String? tooltip;
  final IconData? icon;
  final MetricTone tone;

  /// Recent values drawn as a small line in the corner.
  final List<double>? trend;
  final double width;

  @override
  State<MetricTile> createState() => _MetricTileState();
}

class _MetricTileState extends State<MetricTile> {
  bool _hovered = false;

  Color? _toneColor(AppColors colors) => switch (widget.tone) {
    MetricTone.neutral => null,
    MetricTone.good => colors.latencyGood,
    MetricTone.warn => colors.latencyWarn,
    MetricTone.bad => colors.latencyBad,
  };

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final tone = _toneColor(colors);
    final trend = widget.trend;

    final card = Semantics(
      button: true,
      label:
          '${widget.label}: ${widget.value}'
          '${widget.caption == null ? '' : ', ${widget.caption}'}',
      hint: 'Click to copy the value',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => copyWithToast(context, widget.value, widget.label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.width,
            constraints: const BoxConstraints(minHeight: 82),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _hovered
                  ? colors.panelBackgroundAlt
                  : colors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? colors.accent : colors.borderColor,
              ),
            ),
            child: Stack(
              children: [
                if (tone != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: ColoredBox(color: tone),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (widget.icon != null) ...[
                            Icon(
                              widget.icon,
                              size: 11,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              widget.label,
                              style: type.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.value,
                        style: type.title.copyWith(
                          fontSize: 20,
                          color: widget.valueColor ?? colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.caption != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            widget.caption!,
                            style: type.caption.copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trend != null && trend.length >= 2)
                  Positioned(
                    right: 10,
                    top: 10,
                    width: 54,
                    height: 22,
                    child: CustomPaint(
                      painter: _TrendPainter(
                        values: List.of(trend),
                        color: tone ?? colors.chartLine,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? card
        : Tooltip(message: widget.tooltip!, child: card);
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final span = (hi - lo) < 1e-9 ? 1.0 : hi - lo;
    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final y = size.height - 2 - ((values[i] - lo) / span) * (size.height - 4);
      i == 0 ? path.moveTo(0, y) : path.lineTo(i * step, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values.length != values.length ||
      old.values.last != values.last ||
      old.color != color;
}

/// Small pill such as `HTTPS ×12`.
class CountChip extends StatelessWidget {
  const CountChip({super.key, required this.label, this.count, this.color});

  final String label;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final tint = color ?? colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count == null ? label : '$label ×$count',
        style: type.caption.copyWith(
          color: color == null ? colors.textPrimary : tint,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class HealthBadge extends StatelessWidget {
  const HealthBadge({super.key, required this.health, this.showLabel = true});

  final EndpointHealth health;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final tint = health.color(colors);
    return Tooltip(
      message: health.description,
      child: Semantics(
        label: 'Health: ${health.label}',
        excludeSemantics: true,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: showLabel ? 8 : 5,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              if (showLabel) ...[
                const SizedBox(width: 5),
                Text(
                  health.label,
                  style: type.caption.copyWith(
                    color: tint == colors.textSecondary ? null : tint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Download (accent) and upload (secondary) throughput over time.
class ThroughputChart extends StatelessWidget {
  const ThroughputChart({super.key, required this.samples, this.height = 48});

  final List<RateSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ThroughputPainter(
          samples: List.of(samples),
          inColor: colors.chartLine,
          outColor: colors.latencyWarn,
          gridColor: colors.chartGrid,
        ),
      ),
    );
  }
}

class _ThroughputPainter extends CustomPainter {
  _ThroughputPainter({
    required this.samples,
    required this.inColor,
    required this.outColor,
    required this.gridColor,
  });

  final List<RateSample> samples;
  final Color inColor;
  final Color outColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = gridColor,
    );
    if (samples.length < 2) return;
    final peak = samples.fold<double>(
      1,
      (m, s) => math.max(m, math.max(s.inBps, s.outBps)),
    );
    final step = size.width / (samples.length - 1);

    Path line(double Function(RateSample) pick) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final y =
            size.height - 2 - (pick(samples[i]) / peak) * (size.height - 4);
        i == 0 ? path.moveTo(0, y) : path.lineTo(i * step, y);
      }
      return path;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line((s) => s.outBps), stroke..color = outColor);
    canvas.drawPath(line((s) => s.inBps), stroke..color = inColor);
  }

  @override
  bool shouldRepaint(_ThroughputPainter old) =>
      old.samples.length != samples.length ||
      (samples.isNotEmpty &&
          (old.samples.isEmpty || old.samples.last != samples.last));
}

/// First letter of an app's name in a rounded square.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.size = 28});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderColor),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: type.bodyStrong.copyWith(fontSize: size * 0.5),
      ),
    );
  }
}

/// Section label used between blocks.
class BlockTitle extends StatelessWidget {
  const BlockTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final type = appTypography(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Text(text, style: type.subtitle),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
