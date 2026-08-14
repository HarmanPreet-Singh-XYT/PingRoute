import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'theme.dart';

enum _MetricKey { packetLoss, latency, avgLatency, jitter }

class Graph extends StatefulWidget {
  const Graph({
    super.key,
    required this.dataType,
    required this.data,
    required this.interval,
    required this.isRunning,
  });

  final String dataType;
  final Map<String, dynamic> data;
  final int interval;
  final bool isRunning;

  @override
  State<Graph> createState() => _GraphState();
}

class _GraphState extends State<Graph> {
  Timer? _timer;

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
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(Graph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRunning != widget.isRunning || oldWidget.interval != widget.interval) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.isRunning) {
      _timer = Timer.periodic(Duration(milliseconds: widget.interval.clamp(200, 10000)), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.only(right: 18, left: 8, top: 12, bottom: 6),
        child: LineChart(
          _buildChartData(_activeKey, colors),
          duration: Duration.zero,
        ),
      ),
    );
  }

  bool get _isPercent => _activeKey == _MetricKey.packetLoss;

  Widget _bottomTitles(double value, TitleMeta meta, List<String> times) {
    final style = TextStyle(fontWeight: FontWeight.w500, fontSize: 10, color: appColors(context).textSecondary);
    final index = value.toInt();
    final text = (index >= 0 && index < times.length) ? times[index] : '';
    return SideTitleWidget(axisSide: meta.axisSide, child: Text(text, style: style));
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
