import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../core/theme.dart';
import '../models/flow_session.dart';

class TimelineChart extends StatefulWidget {
  const TimelineChart({
    super.key,
    required this.deepStats,
    required this.events,
    required this.selectedHop,
    required this.interval,
    required this.isRunning,
    this.timelineHistory = const [],
  });

  final List<Map<String, dynamic>> deepStats;
  final List<TimelineEvent> events;
  final int selectedHop;
  final int interval;
  final bool isRunning;
  final List<List<Map<String, dynamic>>> timelineHistory;

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart> {
  String _focusTimePreset = '30s'; // '30s', '1m', '2m', '5m', 'all'
  double _scrubberProgress = 1.0; // 1.0 = live head

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    if (widget.deepStats.isEmpty) {
      return Center(
        child: Text(
          'No timeline telemetry available yet',
          style: type.body.copyWith(color: colors.textSecondary),
        ),
      );
    }

    final safeHopIndex = (widget.selectedHop - 1).clamp(0, widget.deepStats.length - 1);
    
    // Retrieve long-term history buffer or fallback to rolling deepStats
    final List<dynamic> sourceHistory;
    if (safeHopIndex < widget.timelineHistory.length && widget.timelineHistory[safeHopIndex].isNotEmpty) {
      sourceHistory = widget.timelineHistory[safeHopIndex];
    } else {
      final hopData = widget.deepStats[safeHopIndex];
      sourceHistory = (hopData['pings'] as List<dynamic>?) ?? [];
    }

    if (sourceHistory.isEmpty) {
      return Center(
        child: Text(
          'Collecting timeline data for Hop ${widget.selectedHop}...',
          style: type.body.copyWith(color: colors.textSecondary),
        ),
      );
    }

    // Determine viewport window size based on focus preset
    int windowSize = 25;
    if (_focusTimePreset == '30s') {
      windowSize = (30000 / widget.interval).round();
    } else if (_focusTimePreset == '1m') {
      windowSize = (60000 / widget.interval).round();
    } else if (_focusTimePreset == '2m') {
      windowSize = (120000 / widget.interval).round();
    } else if (_focusTimePreset == '5m') {
      windowSize = (300000 / widget.interval).round();
    } else if (_focusTimePreset == 'all') {
      windowSize = sourceHistory.length;
    }

    if (windowSize < 1) windowSize = 1;
    if (windowSize > sourceHistory.length) {
      windowSize = sourceHistory.length;
    }

    final maxStartIndex = (sourceHistory.length - windowSize).clamp(0, sourceHistory.length);
    final startIndex = (maxStartIndex * _scrubberProgress).round().clamp(0, maxStartIndex);
    final endIndex = (startIndex + windowSize).clamp(0, sourceHistory.length);

    final visiblePings = sourceHistory.sublist(startIndex, endIndex);

    final startTimeStr = visiblePings.isNotEmpty ? (visiblePings.first['time']?.toString() ?? '') : '';
    final endTimeStr = visiblePings.isNotEmpty ? (visiblePings.last['time']?.toString() ?? '') : '';

    // Inspect hovered/scrubbed point details
    final inspectedIndex = (startIndex + ((visiblePings.length - 1) * _scrubberProgress).round()).clamp(0, sourceHistory.length - 1);
    final inspectedPoint = sourceHistory.isNotEmpty ? sourceHistory[inspectedIndex] : null;
    final isLiveHead = _scrubberProgress >= 0.95;

    return Container(
      decoration: BoxDecoration(
        color: colors.panelBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Controls Header (Focus Time & Range display)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.panelBackgroundAlt,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: colors.borderColor)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.history, size: 13, color: colors.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Hop ${widget.selectedHop}',
                      style: type.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Live Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLiveHead
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isLiveHead ? Colors.green : Colors.orange,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isLiveHead ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLiveHead ? 'LIVE' : 'HISTORICAL',
                            style: type.caption.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isLiveHead ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLiveHead) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Jump to most recent live telemetry',
                        child: Button(
                          onPressed: () => setState(() => _scrubberProgress = 1.0),
                          child: Text('Live ⏩', style: type.caption.copyWith(fontSize: 10)),
                        ),
                      ),
                    ],
                  ],
                ),
                if (startTimeStr.isNotEmpty)
                  Text(
                    '$startTimeStr – $endTimeStr (${visiblePings.length} pts)',
                    style: type.caption.copyWith(color: colors.textSecondary, fontSize: 10),
                  ),
                ComboBox<String>(
                  value: _focusTimePreset,
                  items: const [
                    ComboBoxItem(value: '30s', child: Text('30s (Live)')),
                    ComboBoxItem(value: '1m', child: Text('1 min')),
                    ComboBoxItem(value: '2m', child: Text('2 min')),
                    ComboBoxItem(value: '5m', child: Text('5 min')),
                    ComboBoxItem(value: 'all', child: Text('All')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _focusTimePreset = val;
                        _scrubberProgress = 1.0;
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          // Main Graph Canvas with Shaded Latency Zones and Red Loss Dropouts
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 16, bottom: 4, left: 6),
              child: _buildTimelineCanvas(
                visiblePings,
                colors,
                type,
              ),
            ),
          ),

          // Bottom Timeline Scrubber Slider & Inspector Stats Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: colors.panelBackgroundAlt,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
              border: Border(top: BorderSide(color: colors.borderColor)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      sourceHistory.isNotEmpty ? sourceHistory.first['time'].toString() : '',
                      style: type.caption.copyWith(fontSize: 10, color: colors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _scrubberProgress,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) {
                          setState(() => _scrubberProgress = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sourceHistory.isNotEmpty ? sourceHistory.last['time'].toString() : '',
                      style: type.caption.copyWith(fontSize: 10, color: colors.textSecondary),
                    ),
                  ],
                ),
                if (inspectedPoint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text('Inspected (${inspectedPoint['time']}): ', style: type.caption.copyWith(fontSize: 10, color: colors.textSecondary)),
                        Text(
                          inspectedPoint['value'] == -1 ? 'LOSS (100%)' : '${inspectedPoint['value']}ms latency',
                          style: type.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: inspectedPoint['value'] == -1 ? Colors.red : colors.accent,
                          ),
                        ),
                        if (inspectedPoint['jitter'] != null)
                          Text('Jitter: ${inspectedPoint['jitter']}ms', style: type.caption.copyWith(fontSize: 10, color: colors.textSecondary)),
                        if (inspectedPoint['avg'] != null)
                          Text('Avg: ${inspectedPoint['avg']}ms', style: type.caption.copyWith(fontSize: 10, color: colors.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCanvas(
    List<dynamic> pings,
    AppColors colors,
    AppTypography type,
  ) {
    final points = <FlSpot>[];
    final times = <String>[];
    double maxObserved = 0.0;

    // Detect contiguous packet loss ranges to render red outage blocks
    final lossRanges = <(double, double)>[];
    double? currentLossStart;
    double? currentLossEnd;

    for (int i = 0; i < pings.length; i++) {
      final entry = pings[i];
      final rawVal = entry['value'];
      final double val = rawVal is num ? rawVal.toDouble() : (double.tryParse('$rawVal') ?? 0.0);
      final isLoss = val < 0;

      if (isLoss) {
        if (currentLossStart == null) {
          currentLossStart = i.toDouble();
          currentLossEnd = i.toDouble();
        } else {
          currentLossEnd = i.toDouble();
        }
        // Place spot at 0 for tooltip interaction
        points.add(FlSpot(i.toDouble(), 0.0));
      } else {
        if (currentLossStart != null && currentLossEnd != null) {
          lossRanges.add((currentLossStart, currentLossEnd));
          currentLossStart = null;
          currentLossEnd = null;
        }
        points.add(FlSpot(i.toDouble(), val));
        if (val > maxObserved) {
          maxObserved = val;
        }
      }
      times.add(entry['time']?.toString() ?? '');
    }

    if (currentLossStart != null && currentLossEnd != null) {
      lossRanges.add((currentLossStart, currentLossEnd));
    }

    // Dynamic Y-axis scale based on observed latency in view
    final double maxY = maxObserved <= 15
        ? 25.0
        : maxObserved <= 40
            ? 50.0
            : maxObserved <= 100
                ? 120.0
                : (maxObserved * 1.25).ceilToDouble();

    final double yInterval = maxY <= 30 ? 5.0 : (maxY <= 60 ? 10.0 : (maxY <= 150 ? 25.0 : 50.0));

    final double maxX = (points.isNotEmpty ? points.length - 1 : 10).toDouble();
    final double titleInterval = (points.length / 5).clamp(1.0, 20.0);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (val) => FlLine(
            color: colors.chartGrid,
            strokeWidth: 0.8,
          ),
        ),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            // Green Zone: 0 - 100ms
            HorizontalRangeAnnotation(
              y1: 0,
              y2: (maxY < 100 ? maxY : 100),
              color: Colors.green.withValues(alpha: 0.04),
            ),
            if (maxY > 100)
              HorizontalRangeAnnotation(
                y1: 100,
                y2: (maxY < 200 ? maxY : 200),
                color: Colors.orange.withValues(alpha: 0.05),
              ),
            if (maxY > 200)
              HorizontalRangeAnnotation(
                y1: 200,
                y2: maxY,
                color: Colors.red.withValues(alpha: 0.06),
              ),
          ],
          verticalRangeAnnotations: [
            // Red outage bands with clean clipping and translucency
            for (final range in lossRanges)
              VerticalRangeAnnotation(
                x1: (range.$1 - 0.4).clamp(0.0, maxX),
                x2: (range.$2 + 0.4).clamp(0.0, maxX),
                color: Colors.red.withValues(alpha: 0.35),
              ),
          ],
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(
            axisNameWidget: Text(
              'Loss %',
              style: TextStyle(
                fontSize: 9,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            axisNameSize: 14,
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: maxY > 0 ? maxY : 25,
              getTitlesWidget: (val, meta) {
                if (val >= maxY * 0.85) {
                  return Text(
                    '100%',
                    style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold),
                  );
                } else if (val <= 0) {
                  return Text(
                    '0%',
                    style: TextStyle(fontSize: 8, color: colors.textSecondary),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: titleInterval,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                final text = (index >= 0 && index < times.length) ? times[index] : '';
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(text, style: TextStyle(fontSize: 9, color: colors.textSecondary)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text(
              'Latency (ms)',
              style: TextStyle(fontSize: 9, color: colors.textSecondary),
            ),
            axisNameSize: 16,
            sideTitles: SideTitles(
              showTitles: true,
              interval: yInterval,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                if (value >= 0 && value <= maxY) {
                  return Text(
                    '${value.toInt()}ms',
                    style: TextStyle(fontSize: 9, color: colors.textSecondary),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: colors.chartBorder, width: 1),
        ),
        minX: 0,
        maxX: maxX > 0 ? maxX : 1,
        minY: 0,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => colors.cardBackground,
            tooltipBorder: BorderSide(color: colors.borderColor, width: 1),
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final timeStr = (idx >= 0 && idx < times.length) ? times[idx] : '';
                final isLoss = (idx >= 0 && idx < pings.length && (pings[idx]['value'] == null || pings[idx]['value'] < 0));
                return LineTooltipItem(
                  isLoss
                      ? '$timeStr\nPACKET LOSS (100%)'
                      : '$timeStr\n${spot.y.toStringAsFixed(1)} ms',
                  TextStyle(
                    color: isLoss ? Colors.red : colors.textPrimary,
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
            color: colors.accent,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 25,
              getDotPainter: (spot, percent, barData, index) {
                final isLoss = (index >= 0 && index < pings.length && (pings[index]['value'] == null || pings[index]['value'] < 0));
                return FlDotCirclePainter(
                  radius: isLoss ? 0.0 : 2.5,
                  color: colors.accent,
                  strokeWidth: 1,
                  strokeColor: colors.panelBackground,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.accent.withValues(alpha: 0.20),
                  colors.accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
