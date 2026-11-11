import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/app_metrics.dart';
import '../models/app_session.dart';
import 'app_mode_widgets.dart';

/// Machine-wide view: totals, top talkers, what needs attention, and recent
/// activity across every app.
class AppOverview extends StatelessWidget {
  const AppOverview({super.key, required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final o = controller.overview;
    final problems = controller.problemEndpoints();
    final events = controller.events.take(12).toList();
    final time = DateFormat('HH:mm:ss');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Overview', style: type.display),
        const SizedBox(height: 2),
        Text(
          controller.trackSelectedOnly
              ? 'Only the apps you chose to track.'
              : 'Everything on this computer that is talking to the network right now.',
          style: type.caption,
        ),
        const SizedBox(height: 16),
        if (o.trackedApps == 0)
          InfoBar(
            title: Text(
              controller.trackSelectedOnly
                  ? 'No apps are being tracked'
                  : 'Pick an app to monitor it',
            ),
            content: Text(
              controller.trackSelectedOnly
                  ? 'Tick one or more apps on the left. Only ticked apps are '
                        'monitored; nothing else is measured.'
                  : 'Select an app on the left to ping every server it '
                        'connects to. Pin it to keep tracking while you look '
                        'at others.',
            ),
            severity: InfoBarSeverity.info,
            isLong: true,
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MetricTile(label: 'Apps online', value: '${o.appCount}'),
            MetricTile(label: 'Remote servers', value: '${o.endpointCount}'),
            MetricTile(label: 'Connections', value: '${o.connectionCount}'),
            if (o.trafficAvailable) ...[
              MetricTile(label: 'Download', value: formatRate(o.inRate)),
              MetricTile(label: 'Upload', value: formatRate(o.outRate)),
            ],
            MetricTile(
              label: 'Apps monitored',
              value: '${o.trackedApps}',
              caption: 'latency tracked',
            ),
            MetricTile(
              label: 'Needs attention',
              value: '${problems.length}',
              valueColor: problems.isEmpty
                  ? colors.latencyGood
                  : colors.latencyBad,
              caption: 'in monitored apps',
            ),
          ],
        ),
        const BlockTitle('Top talkers'),
        if (o.talkers.isEmpty)
          Text('No apps with network activity.', style: type.caption)
        else
          Container(
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.borderColor),
            ),
            child: Column(
              children: [
                _TalkerHeader(showRate: o.trafficAvailable, type: type),
                for (final t in o.talkers.take(10))
                  _TalkerTile(
                    row: t,
                    showRate: o.trafficAvailable,
                    tracked: controller.visibleAppIds.contains(t.app.id),
                    onTap: () => controller.openApp(t.app.id),
                  ),
              ],
            ),
          ),
        if (o.serviceCounts.isNotEmpty) ...[
          const BlockTitle('Services in use'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in o.serviceCounts.take(12))
                CountChip(label: e.key, count: e.value, color: colors.accent),
            ],
          ),
        ],
        if (o.stateCounts.isNotEmpty) ...[
          const BlockTitle('Connection states'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in sortedCounts(o.stateCounts))
                CountChip(label: e.key, count: e.value),
            ],
          ),
        ],
        const BlockTitle('Needs attention'),
        if (problems.isEmpty)
          Text(
            o.trackedApps == 0
                ? 'Monitor an app to see latency and packet-loss problems here.'
                : 'No monitored endpoint is struggling.',
            style: type.caption,
          )
        else
          for (final ep in problems.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.openApp(ep.appId),
                child: Row(
                  children: [
                    HealthBadge(
                      health: ep.health(controller.settings.lossAlertPercent),
                    ),
                    const SizedBox(width: 10),
                    Text(ep.ip, style: type.bodyStrong),
                    const SizedBox(width: 8),
                    Text(controller.nameFor(ep.appId), style: type.caption),
                    const Spacer(),
                    Text(
                      '${ep.recentAverageMs?.round() ?? '–'} ms · '
                      '${formatPercent(ep.recentLossPercent)} loss',
                      style: type.caption,
                    ),
                  ],
                ),
              ),
            ),
        const BlockTitle('Recent activity'),
        if (events.isEmpty)
          Text(
            'Nothing yet. Events appear once you monitor an app.',
            style: type.caption,
          )
        else
          for (final e in events)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(time.format(e.time), style: type.caption),
                  ),
                  SizedBox(
                    width: 130,
                    child: Text(
                      e.appName,
                      style: type.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.message,
                      style: type.caption.copyWith(color: colors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _TalkerHeader extends StatelessWidget {
  const _TalkerHeader({required this.showRate, required this.type});

  final bool showRate;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    final head = type.caption.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          const SizedBox(width: 38),
          Expanded(child: Text('App', style: head)),
          SizedBox(width: 74, child: Text('Servers', style: head)),
          SizedBox(width: 84, child: Text('Connections', style: head)),
          if (showRate)
            SizedBox(width: 190, child: Text('Download / Upload', style: head)),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _TalkerTile extends StatelessWidget {
  const _TalkerTile({
    required this.row,
    required this.showRate,
    required this.tracked,
    required this.onTap,
  });

  final TalkerRow row;
  final bool showRate;
  final bool tracked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    return Semantics(
      button: true,
      label:
          '${row.app.name}, ${row.endpoints} servers, ${row.connections} connections',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.dividerColor)),
          ),
          child: Row(
            children: [
              AppAvatar(name: row.app.name, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.app.name,
                        style: type.body,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tracked) ...[
                      const SizedBox(width: 8),
                      const CountChip(label: 'monitored'),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 74,
                child: Text('${row.endpoints}', style: type.body),
              ),
              SizedBox(
                width: 84,
                child: Text('${row.connections}', style: type.body),
              ),
              if (showRate)
                SizedBox(
                  width: 190,
                  child: Text(
                    '↓ ${formatRate(row.inRate)}  ↑ ${formatRate(row.outRate)}',
                    style: type.caption,
                  ),
                ),
              Icon(
                FluentIcons.chevron_right,
                size: 10,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
