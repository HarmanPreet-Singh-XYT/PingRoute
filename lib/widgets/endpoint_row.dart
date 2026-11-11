import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/app_metrics.dart';
import '../models/app_mode_settings.dart';
import '../models/app_session.dart';
import '../models/flow_session.dart';
import 'app_mode_widgets.dart';

/// One remote endpoint of an application. Collapsed it shows identity, health
/// and a live latency sparkline; expanded it shows full statistics and runs a
/// traceroute in place.
class EndpointRow extends StatelessWidget {
  const EndpointRow({
    super.key,
    required this.endpoint,
    required this.density,
    required this.lossAlertPercent,
    required this.onToggleExpanded,
    required this.onOpenAsTab,
    required this.onShowIpInfo,
  });

  final EndpointState endpoint;
  final RowDensity density;
  final int lossAlertPercent;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenAsTab;
  final VoidCallback onShowIpInfo;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ListenableBuilder(
      listenable: endpoint,
      builder: (context, _) {
        final expanded = endpoint.isExpanded;
        final health = endpoint.health(lossAlertPercent);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: expanded ? colors.accent : colors.borderColor,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: health.color(colors)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      endpoint: endpoint,
                      colors: colors,
                      type: type,
                      compact: density == RowDensity.compact,
                      health: health,
                      onTap: onToggleExpanded,
                    ),
                    if (expanded)
                      _ExpandedBody(
                        endpoint: endpoint,
                        colors: colors,
                        type: type,
                        health: health,
                        onCollapse: onToggleExpanded,
                        onOpenAsTab: onOpenAsTab,
                        onShowIpInfo: onShowIpInfo,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.endpoint,
    required this.colors,
    required this.type,
    required this.compact,
    required this.health,
    required this.onTap,
  });

  final EndpointState endpoint;
  final AppColors colors;
  final AppTypography type;
  final bool compact;
  final EndpointHealth health;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ep = endpoint;
    final last = ep.last;
    final idle = !ep.isActive;
    final latencyText = idle
        ? 'closed'
        : last == null
        ? (ep.isExpanded ? 'tracing' : (ep.isPinging ? '…' : '—'))
        : last < 0
        ? 'timeout'
        : '$last ms';
    final latencyTint = (last != null && last >= 0 && !idle)
        ? latencyColor(colors, last)
        : colors.textSecondary;

    final ports = (ep.ports.toList()..sort()).take(3).join(', ');
    final subtitle = [
      if (ep.hostname != null) ep.hostname!,
      if (ports.isNotEmpty) 'port $ports',
    ].join(' · ');

    return Semantics(
      button: true,
      expanded: ep.isExpanded,
      label: 'Endpoint ${ep.ip}, ${health.label}, $latencyText',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final showSpark = w >= 560;
            final showBadge = w >= 440;
            final showRate = w >= 760 && ep.rate >= 1;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: compact ? 6 : 10,
              ),
              child: Row(
                children: [
                  Icon(
                    ep.isExpanded
                        ? FluentIcons.chevron_down
                        : FluentIcons.chevron_right,
                    size: 10,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                ep.ip,
                                style: type.bodyStrong.copyWith(
                                  color: idle
                                      ? colors.textSecondary
                                      : colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (ep.primaryService != null) ...[
                              const SizedBox(width: 8),
                              CountChip(label: ep.primaryService!),
                            ],
                            if (ep.connectionCount > 1) ...[
                              const SizedBox(width: 6),
                              Text(
                                '×${ep.connectionCount}',
                                style: type.caption,
                              ),
                            ],
                          ],
                        ),
                        if (subtitle.isNotEmpty && !compact)
                          Text(
                            subtitle,
                            style: type.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (showRate)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '↓ ${formatRate(ep.inRate)}  ↑ ${formatRate(ep.outRate)}',
                        style: type.caption,
                      ),
                    ),
                  if (showBadge)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: HealthBadge(health: health),
                    ),
                  if (showSpark)
                    SizedBox(
                      width: 96,
                      height: 24,
                      child: CustomPaint(
                        painter: SparklinePainter(
                          values: ep.history,
                          sampleCount: ep.sent,
                          lineColor: colors.chartLine,
                          lossColor: colors.latencyBad,
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 68,
                    child: Text(
                      latencyText,
                      textAlign: TextAlign.right,
                      style: type.bodyStrong.copyWith(
                        color: latencyTint,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.endpoint,
    required this.colors,
    required this.type,
    required this.health,
    required this.onCollapse,
    required this.onOpenAsTab,
    required this.onShowIpInfo,
  });

  final EndpointState endpoint;
  final AppColors colors;
  final AppTypography type;
  final EndpointHealth health;
  final VoidCallback onCollapse;
  final VoidCallback onOpenAsTab;
  final VoidCallback onShowIpInfo;

  @override
  Widget build(BuildContext context) {
    final ep = endpoint;
    final flow = ep.flow!;
    final time = DateFormat('HH:mm:ss');
    final hasTraffic =
        ep.bytesIn + ep.bytesOut + ep.sessionIn + ep.sessionOut > 0;

    String ms(num? v) => v == null ? '—' : '${v.round()} ms';

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.dividerColor)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: onOpenAsTab,
                child: const Text('Open as tab'),
              ),
              Button(onPressed: onShowIpInfo, child: const Text('IP info')),
              Button(
                onPressed: () => copyWithToast(context, ep.ip, 'IP address'),
                child: const Text('Copy IP'),
              ),
              if (ep.hostname != null)
                Button(
                  onPressed: () =>
                      copyWithToast(context, ep.hostname!, 'Hostname'),
                  child: const Text('Copy hostname'),
                ),
              Button(onPressed: onCollapse, child: const Text('Collapse')),
              HealthBadge(health: health),
            ],
          ),
          const SizedBox(height: 14),
          if (ep.history.length >= 2) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Latency, last ${ep.history.length} pings',
                    style: type.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'min ${ms(ep.minMs)} · max ${ms(ep.maxMs)}',
                    style: type.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 52,
              child: CustomPaint(
                size: Size.infinite,
                painter: SparklinePainter(
                  values: ep.history,
                  sampleCount: ep.sent,
                  lineColor: colors.chartLine,
                  lossColor: colors.latencyBad,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 28,
            runSpacing: 14,
            children: [
              _InfoGroup(
                title: 'Latency',
                rows: [
                  (
                    'Last',
                    ep.last == null
                        ? '—'
                        : (ep.last! < 0 ? 'timeout' : '${ep.last} ms'),
                  ),
                  ('Average', ms(ep.averageMs)),
                  ('Min / Max', '${ms(ep.minMs)} / ${ms(ep.maxMs)}'),
                  ('Jitter', ms(ep.jitterMs)),
                  (
                    'Measured by',
                    ep.probe == ProbeMethod.tcp
                        ? 'TCP connect :${ep.tcpPort}'
                        : 'ICMP ping',
                  ),
                  (
                    'Packet loss',
                    '${formatPercent(ep.lossPercent)} of ${ep.sent}',
                  ),
                ],
              ),
              _InfoGroup(
                title: 'Connection',
                rows: [
                  ('Address', ep.ip),
                  ('Hostname', ep.hostname ?? '—'),
                  ('Service', ep.primaryService ?? '—'),
                  ('Remote ports', (ep.ports.toList()..sort()).join(', ')),
                  ('Protocol', (ep.protocols.toList()..sort()).join(', ')),
                  (
                    'States',
                    ep.states.isEmpty
                        ? '—'
                        : ep.states.entries
                              .map((e) => '${e.key} ×${e.value}')
                              .join(', '),
                  ),
                  ('IP version', ep.isIpv6 ? 'IPv6' : 'IPv4'),
                ],
              ),
              _InfoGroup(
                title: 'Timing',
                rows: [
                  ('First seen', time.format(ep.firstSeen)),
                  ('Last seen', time.format(ep.lastSeen)),
                  ('Observed for', formatDuration(ep.observedFor)),
                  ('Connections', '${ep.connectionCount}'),
                ],
              ),
              if (hasTraffic)
                _InfoGroup(
                  title: 'Traffic',
                  rows: [
                    ('Download', formatRate(ep.inRate)),
                    ('Upload', formatRate(ep.outRate)),
                    ('Since tracking ↓', formatBytes(ep.sessionIn)),
                    ('Since tracking ↑', formatBytes(ep.sessionOut)),
                    (
                      'Socket total ↓/↑',
                      '${formatBytes(ep.bytesIn)} / ${formatBytes(ep.bytesOut)}',
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Route', style: type.subtitle),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: flow,
            builder: (context, _) =>
                _HopTable(flow: flow, colors: colors, type: type),
          ),
        ],
      ),
    );
  }
}

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    return SizedBox(
      width: 230,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: type.subtitle),
          const SizedBox(height: 4),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 92, child: Text(label, style: type.caption)),
                  Expanded(
                    child: Text(
                      value,
                      style: type.caption.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HopTable extends StatelessWidget {
  const _HopTable({
    required this.flow,
    required this.colors,
    required this.type,
  });

  final FlowSession flow;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    if (flow.isLoading && flow.ipStats.isEmpty) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Tracing route…', style: type.caption),
        ],
      );
    }
    if (flow.ipStats.isEmpty) {
      return Text(
        'No route data. This host may block traceroute probes.',
        style: type.caption,
      );
    }

    Widget cell(String text, {double? width, TextStyle? style}) {
      final child = Text(
        text,
        style: style ?? type.caption.copyWith(color: colors.textPrimary),
        overflow: TextOverflow.ellipsis,
      );
      return width == null
          ? Expanded(child: child)
          : SizedBox(width: width, child: child);
    }

    final headStyle = type.caption.copyWith(fontWeight: FontWeight.w600);
    return Column(
      children: [
        Row(
          children: [
            cell('Hop', width: 36, style: headStyle),
            cell('Host', style: headStyle),
            cell('Avg', width: 64, style: headStyle),
            cell('Loss', width: 56, style: headStyle),
          ],
        ),
        Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        for (final hop in flow.ipStats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                cell('${hop['hop'] ?? ''}', width: 36),
                cell(_hopLabel(hop)),
                cell(_ms(hop['avg']), width: 64),
                cell('${hop['pl'] ?? 0}%', width: 56),
              ],
            ),
          ),
      ],
    );
  }

  static String _hopLabel(Map<String, dynamic> hop) {
    final ip = hop['ip']?.toString() ?? '';
    final name = hop['name']?.toString() ?? '';
    if (ip.isEmpty || ip == '*') return '*';
    return name.isNotEmpty && name != ip ? '$name ($ip)' : ip;
  }

  static String _ms(Object? value) =>
      value is int && value >= 0 ? '$value ms' : '—';
}

/// Minimal latency sparkline; lost samples render as red ticks at the base.
class SparklinePainter extends CustomPainter {
  SparklinePainter({
    required this.values,
    required this.sampleCount,
    required this.lineColor,
    required this.lossColor,
  });

  final List<int> values;
  final int sampleCount;
  final Color lineColor;
  final Color lossColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values.fold<int>(100, (m, v) => v > m ? v : m).toDouble();
    final step = values.length > 1 ? size.width / (values.length - 1) : 0.0;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final lossPaint = Paint()
      ..color = lossColor
      ..strokeWidth = 2;

    final path = Path();
    var penDown = false;
    for (var i = 0; i < values.length; i++) {
      final x = values.length > 1 ? i * step : size.width;
      final v = values[i];
      if (v < 0) {
        canvas.drawLine(
          Offset(x, size.height - 6),
          Offset(x, size.height),
          lossPaint,
        );
        penDown = false;
        continue;
      }
      final y = size.height - (v / maxValue) * (size.height - 2) - 1;
      if (penDown) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
        penDown = true;
      }
    }
    canvas.drawPath(path, linePaint);
  }

  // [values] is mutated in place, so old and new painters share the same
  // list; the monotonically increasing sample count is the change signal.
  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.sampleCount != sampleCount || old.lineColor != lineColor;
}
