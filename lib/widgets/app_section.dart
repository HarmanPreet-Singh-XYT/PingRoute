import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../dialogs/ip_info_dialog.dart';
import '../models/app_metrics.dart';
import '../models/app_mode_settings.dart';
import '../models/app_session.dart';
import '../models/flow_session.dart';
import 'app_mode_widgets.dart';
import 'endpoint_row.dart';

typedef OpenEndpointAsTab = void Function(String ip, FlowSession? flow);

/// Everything about one tracked application: overview, controls, endpoints
/// and an activity log.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.appId,
    required this.controller,
    required this.onOpenAsTab,
  });

  final String appId;
  final AppsController controller;
  final OpenEndpointAsTab onOpenAsTab;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final view = controller.viewFor(appId);
    final snapshot = controller.snapshotFor(appId);
    final all = controller.endpointsFor(appId);
    final shown = controller.filteredEndpointsFor(appId);
    final settings = controller.settings;
    final pinned = controller.pinnedIds.contains(appId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: controller.nameFor(appId), size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(controller.nameFor(appId), style: type.title),
                    Text(
                      snapshot == null
                          ? 'Not running or no network activity'
                          : [
                              '${snapshot.processCount} process'
                                  '${snapshot.processCount == 1 ? '' : 'es'}',
                              if (snapshot.uptime != null)
                                'running ${formatDuration(snapshot.uptime!)}',
                            ].join(' · '),
                      style: type.caption,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: controller.trackSelectedOnly
                    ? 'Stop tracking this app'
                    : (pinned ? 'Unpin app' : 'Pin app to keep it tracked'),
                child: IconButton(
                  icon: Icon(
                    controller.trackSelectedOnly
                        ? FluentIcons.cancel
                        : (pinned ? FluentIcons.pinned_solid : FluentIcons.pin),
                    size: 14,
                    color: pinned ? colors.accent : colors.textSecondary,
                  ),
                  onPressed: () => controller.trackSelectedOnly
                      ? controller.toggleTracked(appId)
                      : controller.togglePin(appId),
                ),
              ),
              Tooltip(
                message: view.collapsed ? 'Expand section' : 'Collapse section',
                child: IconButton(
                  icon: Icon(
                    view.collapsed
                        ? FluentIcons.chevron_down
                        : FluentIcons.chevron_up,
                    size: 12,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => controller.updateView(
                    appId,
                    (v) => v.collapsed = !v.collapsed,
                  ),
                ),
              ),
            ],
          ),
          if (!view.collapsed) ...[
            _SummaryBlock(appId: appId, controller: controller),
            BlockTitle('Endpoints'),
            _Toolbar(
              appId: appId,
              controller: controller,
              total: all.length,
              shown: shown.length,
              anyExpanded: all.any((e) => e.isExpanded),
            ),
            const SizedBox(height: 10),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  snapshot == null
                      ? 'This app is not running or has no network activity right now.'
                      : 'Looking for connections…',
                  style: type.caption,
                ),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No endpoints match these filters.',
                  style: type.caption,
                ),
              )
            else
              for (final ep in shown)
                EndpointRow(
                  key: ValueKey('${ep.appId}_${ep.ip}'),
                  endpoint: ep,
                  density: settings.density,
                  lossAlertPercent: settings.lossAlertPercent,
                  onToggleExpanded: () => controller.toggleExpanded(ep),
                  onOpenAsTab: () =>
                      onOpenAsTab(ep.ip, controller.takeFlow(ep)),
                  onShowIpInfo: () =>
                      showIpInfoDialog(context, ep.ip, name: ep.hostname),
                ),
            _ActivityLog(appId: appId, controller: controller),
          ],
        ],
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.appId, required this.controller});

  final String appId;
  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    // Ping samples land on the endpoints, not the controller.
    final endpoints = controller.endpointsFor(appId);

    return ListenableBuilder(
      listenable: Listenable.merge([controller, ...endpoints]),
      builder: (context, _) {
        final s = controller.summaryFor(appId);
        final history = controller.rateHistoryFor(appId);
        final lossAlert = controller.settings.lossAlertPercent;

        final latencyTrend = controller.latencyTrendFor(appId);
        MetricTone toneFor(int? ms) => ms == null
            ? MetricTone.neutral
            : (ms > kBadLatencyMs
                  ? MetricTone.bad
                  : (ms > kWarnLatencyMs ? MetricTone.warn : MetricTone.good));

        final tiles = <Widget>[
          MetricTile(
            icon: FluentIcons.network_tower,
            label: 'Endpoints',
            value: '${s.activeCount}',
            caption: s.endpointCount > s.activeCount
                ? '${s.endpointCount - s.activeCount} closed'
                : (s.newLastMinute > 0
                      ? '${s.newLastMinute} new this minute'
                      : 'active now'),
          ),
          MetricTile(
            icon: FluentIcons.link,
            label: 'Connections',
            value: '${s.connectionCount}',
            caption: s.udpConnections > 0
                ? '${s.tcpConnections} TCP · ${s.udpConnections} UDP'
                : 'TCP',
          ),
          MetricTile(
            icon: FluentIcons.timer,
            label: 'Avg latency',
            value: s.avgMs == null ? '—' : '${s.avgMs} ms',
            tone: toneFor(s.avgMs),
            trend: latencyTrend,
            caption: '${s.pingedCount} of ${s.activeCount} measured',
            tooltip: 'Mean of each endpoint’s average latency.',
          ),
          MetricTile(
            icon: FluentIcons.up,
            label: 'Fastest',
            value: s.fastestMs == null ? '—' : '${s.fastestMs} ms',
            tone: toneFor(s.fastestMs),
            caption: s.fastestIp,
          ),
          MetricTile(
            icon: FluentIcons.down,
            label: 'Slowest',
            value: s.slowestMs == null ? '—' : '${s.slowestMs} ms',
            tone: toneFor(s.slowestMs),
            caption: s.slowestIp,
          ),
          MetricTile(
            icon: FluentIcons.error_badge,
            label: 'Packet loss',
            value: formatPercent(s.lossPercent),
            tone: s.pingedCount == 0 && s.lossPercent == 0
                ? MetricTone.neutral
                : (s.lossPercent >= lossAlert
                      ? MetricTone.bad
                      : (s.lossPercent > 0
                            ? MetricTone.warn
                            : MetricTone.good)),
            caption: s.jitterMs == null
                ? 'jitter —'
                : 'jitter ${s.jitterMs!.toStringAsFixed(1)} ms',
          ),
          MetricTile(
            icon: FluentIcons.warning,
            label: 'Needs attention',
            value: '${s.problemCount}',
            tone: s.problemCount > 0 ? MetricTone.bad : MetricTone.good,
            caption: s.problemCount == 0 ? 'all healthy' : 'poor or degraded',
          ),
          if (s.trafficAvailable) ...[
            MetricTile(
              icon: FluentIcons.download,
              label: 'Download',
              value: formatRate(s.inRate),
              trend: [for (final r in history) r.inBps],
              caption: '${formatBytes(s.sessionIn)} since tracking',
            ),
            MetricTile(
              icon: FluentIcons.upload,
              label: 'Upload',
              value: formatRate(s.outRate),
              trend: [for (final r in history) r.outBps],
              caption: '${formatBytes(s.sessionOut)} since tracking',
            ),
          ],
          if (s.processCount > 0) ...[
            MetricTile(
              icon: FluentIcons.processing,
              label: 'CPU',
              value: formatPercent(s.cpuPercent),
              caption: 'all processes',
            ),
            MetricTile(
              icon: FluentIcons.hard_drive,
              label: 'Memory',
              value: formatKilobytes(s.rssKb),
              caption: 'resident',
            ),
          ],
        ];

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: tiles),
              if (s.trafficAvailable && history.length >= 2) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Throughput', style: type.caption),
                    const SizedBox(width: 10),
                    Container(width: 8, height: 3, color: colors.chartLine),
                    const SizedBox(width: 4),
                    Text('download', style: type.caption),
                    const SizedBox(width: 10),
                    Container(width: 8, height: 3, color: colors.latencyWarn),
                    const SizedBox(width: 4),
                    Text('upload', style: type.caption),
                  ],
                ),
                const SizedBox(height: 4),
                ThroughputChart(samples: history),
              ],
              if (s.stateCounts.isNotEmpty || s.serviceCounts.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final e in s.serviceCounts.take(6))
                      CountChip(
                        label: e.key,
                        count: e.value,
                        color: colors.accent,
                      ),
                    for (final e in sortedCounts(s.stateCounts))
                      CountChip(label: e.key, count: e.value),
                    if (s.ipv6Count > 0 || s.ipv4Count > 0)
                      CountChip(
                        label: 'IPv4 ${s.ipv4Count} · IPv6 ${s.ipv6Count}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.appId,
    required this.controller,
    required this.total,
    required this.shown,
    required this.anyExpanded,
  });

  final String appId;
  final AppsController controller;
  final int total;
  final int shown;
  final bool anyExpanded;

  @override
  Widget build(BuildContext context) {
    final type = appTypography(context);
    final view = controller.viewFor(appId);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextBox(
            placeholder: 'Filter by IP, host or service',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.filter, size: 12),
            ),
            onChanged: (v) => controller.updateView(appId, (s) => s.query = v),
          ),
        ),
        Text('Sort by', style: type.caption),
        ComboBox<EndpointSort>(
          value: controller.sortFor(appId),
          items: [
            for (final s in EndpointSort.values)
              ComboBoxItem(value: s, child: Text(s.label)),
          ],
          onChanged: (v) {
            if (v != null) controller.updateView(appId, (s) => s.sort = v);
          },
        ),
        ToggleButton(
          checked: view.activeOnly,
          onChanged: (v) =>
              controller.updateView(appId, (s) => s.activeOnly = v),
          child: const Text('Active only'),
        ),
        ToggleButton(
          checked: view.problemsOnly,
          onChanged: (v) =>
              controller.updateView(appId, (s) => s.problemsOnly = v),
          child: const Text('Problems only'),
        ),
        if (anyExpanded)
          Button(
            onPressed: () => controller.collapseAll(appId),
            child: const Text('Collapse all'),
          ),
        Text(
          shown == total ? '$total endpoints' : 'Showing $shown of $total',
          style: type.caption,
        ),
      ],
    );
  }
}

class _ActivityLog extends StatelessWidget {
  const _ActivityLog({required this.appId, required this.controller});

  final String appId;
  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final view = controller.viewFor(appId);
    final events = controller.eventsFor(appId);
    final time = DateFormat('HH:mm:ss');

    Color tint(ActivityKind k) => switch (k) {
      ActivityKind.connected || ActivityKind.recovered => colors.latencyGood,
      ActivityKind.degraded => colors.latencyBad,
      ActivityKind.closed => colors.textSecondary,
      ActivityKind.started => colors.accent,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.updateView(
              appId,
              (v) => v.activityOpen = !v.activityOpen,
            ),
            child: Row(
              children: [
                Icon(
                  view.activityOpen
                      ? FluentIcons.chevron_down
                      : FluentIcons.chevron_right,
                  size: 10,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text('Activity (${events.length})', style: type.subtitle),
              ],
            ),
          ),
          if (view.activityOpen) ...[
            const SizedBox(height: 8),
            if (events.isEmpty)
              Text('Nothing has changed yet.', style: type.caption)
            else
              for (final e in events.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(time.format(e.time), style: type.caption),
                      ),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: tint(e.kind),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.message,
                          style: type.caption.copyWith(
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
