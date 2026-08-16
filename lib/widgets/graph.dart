import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../core/theme.dart';

enum _MetricKey { packetLoss, latency, avgLatency, jitter }

class Graph extends StatefulWidget {
  const Graph({
    super.key,
    required this.dataType,
    required this.data,
    required this.interval,
    required this.isRunning,
    this.onSelectMetric,
    this.onTogglePills,
    this.onToggleCards,
    this.onToggleControls,
    this.onReset,
    this.showPills = true,
    this.showCards = true,
    this.showControls = true,
  });

  final String dataType;
  final Map<String, dynamic> data;
  final int interval;
  final bool isRunning;
  final ValueChanged<String>? onSelectMetric;
  final VoidCallback? onTogglePills;
  final VoidCallback? onToggleCards;
  final VoidCallback? onToggleControls;
  final VoidCallback? onReset;
  final bool showPills;
  final bool showCards;
  final bool showControls;

  @override
  State<Graph> createState() => _GraphState();
}

class _GraphState extends State<Graph> {
  final FlyoutController _flyoutController = FlyoutController();

  static const Map<_MetricKey, String> _dataKey = {
    _MetricKey.packetLoss: 'pl',
    _MetricKey.latency: 'pings',
    _MetricKey.avgLatency: 'avg',
    _MetricKey.jitter: 'jitter',
  };

  _MetricKey get _activeKey {
    switch (widget.dataType) {
      case 'pl':
        return _MetricKey.packetLoss;
      case 'jt':
        return _MetricKey.jitter;
      case 'lt':
        return _MetricKey.latency;
      default:
        return _MetricKey.avgLatency;
    }
  }

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  void _showContextMenu(TapDownDetails details) {
    _flyoutController.showFlyout(
      barrierColor: Colors.transparent,
      autoModeConfiguration: FlyoutAutoConfiguration(
        preferredMode: FlyoutPlacementMode.bottomCenter,
      ),
      builder: (context) {
        final colors = appColors(context);
        return MenuFlyout(
          items: [
            MenuFlyoutItem(
              leading: Icon(
                widget.dataType == 'lt' ? FluentIcons.check_mark : FluentIcons.speed_high,
                size: 14,
                color: widget.dataType == 'lt' ? colors.accent : colors.textSecondary,
              ),
              text: const Text('Latency (ms)'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSelectMetric?.call('lt');
              },
            ),
            MenuFlyoutItem(
              leading: Icon(
                widget.dataType == 'alt' ? FluentIcons.check_mark : FluentIcons.line_chart,
                size: 14,
                color: widget.dataType == 'alt' ? colors.accent : colors.textSecondary,
              ),
              text: const Text('Average Latency (ms)'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSelectMetric?.call('alt');
              },
            ),
            MenuFlyoutItem(
              leading: Icon(
                widget.dataType == 'jt' ? FluentIcons.check_mark : FluentIcons.heart,
                size: 14,
                color: widget.dataType == 'jt' ? colors.accent : colors.textSecondary,
              ),
              text: const Text('Jitter (ms)'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSelectMetric?.call('jt');
              },
            ),
            MenuFlyoutItem(
              leading: Icon(
                widget.dataType == 'pl' ? FluentIcons.check_mark : FluentIcons.warning,
                size: 14,
                color: widget.dataType == 'pl' ? colors.accent : colors.textSecondary,
              ),
              text: const Text('Packet Loss (%)'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onSelectMetric?.call('pl');
              },
            ),
            if (widget.onTogglePills != null ||
                widget.onToggleCards != null ||
                widget.onToggleControls != null) ...[
              const MenuFlyoutSeparator(),
              if (widget.onTogglePills != null)
                MenuFlyoutItem(
                  leading: Icon(
                    widget.showPills ? FluentIcons.radio_bullet : FluentIcons.circle_shape,
                    size: 12,
                    color: colors.accent,
                  ),
                  text: Text(widget.showPills ? 'Hide Metric Buttons' : 'Show Metric Buttons'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onTogglePills?.call();
                  },
                ),
              if (widget.onToggleCards != null)
                MenuFlyoutItem(
                  leading: Icon(
                    widget.showCards ? FluentIcons.hide : FluentIcons.view,
                    size: 14,
                    color: colors.accent,
                  ),
                  text: Text(widget.showCards ? 'Hide Summary Cards' : 'Show Summary Cards'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onToggleCards?.call();
                  },
                ),
              if (widget.onToggleControls != null)
                MenuFlyoutItem(
                  leading: Icon(
                    widget.showControls ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                    size: 14,
                    color: colors.accent,
                  ),
                  text: Text(widget.showControls ? 'Hide Target & Controls' : 'Show Target & Controls'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onToggleControls?.call();
                  },
                ),
            ],
            if (widget.onReset != null) ...[
              const MenuFlyoutSeparator(),
              MenuFlyoutItem(
                leading: Icon(FluentIcons.refresh, size: 14, color: colors.latencyWarn),
                text: const Text('Reset Telemetry Data'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onReset?.call();
                },
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return FlyoutTarget(
      controller: _flyoutController,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: _showContextMenu,
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.only(right: 18, left: 8, top: 12, bottom: 6),
            child: LineChart(
              _buildChartData(_activeKey, colors),
              duration: Duration.zero,
            ),
          ),
        ),
      ),
    );
  }

  bool get _isPercent => _activeKey == _MetricKey.packetLoss;

  Widget _bottomTitles(double value, TitleMeta meta, List<String> times) {
    final style = TextStyle(fontWeight: FontWeight.w500, fontSize: 10, color: appColors(context).textSecondary);
    final index = value.toInt();
    final text = (index >= 0 && index < times.length) ? times[index] : '';
    return SideTitleWidget(meta: meta, child: Text(text, style: style));
  }

  Widget _leftTitles(double value, TitleMeta meta, double maxY) {
    final style = TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: appColors(context).textSecondary);
    if (_isPercent) {
      if (value % 20 == 0 && value >= 0 && value <= 100) {
        return Text('${value.toInt()}%', style: style, textAlign: TextAlign.left);
      }
      return const SizedBox.shrink();
    }
    if (value >= 0 && value <= maxY) {
      return Text('${value.toInt()}ms', style: style, textAlign: TextAlign.left);
    }
    return const SizedBox.shrink();
  }

  LineChartData _buildChartData(_MetricKey key, AppColors colors) {
    final sourceKey = _dataKey[key]!;
    final List<dynamic> source = (widget.data[sourceKey] as List<dynamic>?) ?? const [];

    final points = <FlSpot>[];
    final times = <String>[];
    double maxY = _isPercent ? 100.0 : 20.0;

    for (int i = 0; i < source.length; i++) {
      final entry = source[i];
      final rawVal = entry['value'];
      final double val = rawVal is num ? rawVal.toDouble() : (double.tryParse('$rawVal') ?? 0.0);
      final double clampedVal = val < 0 ? 0.0 : val;

      points.add(FlSpot(i.toDouble(), clampedVal));
      times.add(entry['time']?.toString() ?? '');

      if (!_isPercent && clampedVal > maxY) {
        maxY = clampedVal + 15;
      }
    }

    final double maxX = (points.isNotEmpty ? points.length - 1 : 10).toDouble();
    const double minX = 0;
    final double horizontalInterval = _isPercent ? 20.0 : (maxY / 4).clamp(1.0, 1000.0);
    final double titleInterval = (points.length / 5).clamp(1.0, 10.0);

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: horizontalInterval,
        getDrawingHorizontalLine: (value) => FlLine(color: colors.chartGrid, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: titleInterval,
            getTitlesWidget: (value, meta) => _bottomTitles(value, meta, times),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: horizontalInterval,
            getTitlesWidget: (value, meta) => _leftTitles(value, meta, maxY),
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: colors.chartBorder, width: 1),
      ),
      minX: minX,
      maxX: maxX > 0 ? maxX : 1,
      minY: 0,
      maxY: maxY,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => colors.cardBackground,
          tooltipBorder: BorderSide(color: colors.borderColor, width: 1),
          tooltipBorderRadius: BorderRadius.circular(8),
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final idx = spot.x.toInt();
              final timeStr = (idx >= 0 && idx < times.length) ? times[idx] : '';
              final suffix = _isPercent ? '%' : ' ms';
              return LineTooltipItem(
                timeStr.isNotEmpty ? '$timeStr\n${spot.y.toStringAsFixed(1)}$suffix' : '${spot.y.toStringAsFixed(1)}$suffix',
                TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          show: points.isNotEmpty,
          spots: points,
          isCurved: points.length > 2,
          color: colors.chartLine,
          barWidth: 2.2,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: points.length <= 15,
            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
              radius: 2.5,
              color: colors.chartLine,
              strokeWidth: 1,
              strokeColor: colors.panelBackground,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.chartLine.withValues(alpha: 0.25),
                colors.chartLine.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
