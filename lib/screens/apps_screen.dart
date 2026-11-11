import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../dialogs/app_mode_settings_dialog.dart';
import '../models/app_session.dart';
import '../services/app_connection_service.dart';
import '../services/app_report.dart';
import '../widgets/app_mode_widgets.dart';
import '../widgets/app_overview.dart';
import '../widgets/app_section.dart';

/// App Mode: an overview of everything talking to the network, plus a
/// per-application view of every remote endpoint with live latency.
class AppsScreen extends StatelessWidget {
  const AppsScreen({
    super.key,
    required this.controller,
    required this.onOpenAsTab,
  });

  final AppsController controller;
  final OpenEndpointAsTab onOpenAsTab;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    if (!AppConnectionService.isSupported) {
      return Center(
        child: Text(
          'App Mode is available on macOS, Windows and Linux.',
          style: type.body,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = constraints.maxWidth < 800 ? 210.0 : 270.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: railWidth,
              child: _AppRail(controller: controller),
            ),
            Container(width: 1, color: colors.borderColor),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(controller: controller),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => _Body(
                        controller: controller,
                        onOpenAsTab: onOpenAsTab,
                      ),
                    ),
                  ),
                  _StatusBar(controller: controller),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.onOpenAsTab});

  final AppsController controller;
  final OpenEndpointAsTab onOpenAsTab;

  @override
  Widget build(BuildContext context) {
    final type = appTypography(context);

    if (controller.lastPolled == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ProgressRing(),
            const SizedBox(height: 12),
            Text('Reading network connections…', style: type.caption),
          ],
        ),
      );
    }

    final banner = controller.isPaused
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: InfoBar(
              title: const Text('Paused'),
              content: const Text('Connections and pings are not updating.'),
              severity: InfoBarSeverity.warning,
              action: Button(
                onPressed: controller.resume,
                child: const Text('Resume'),
              ),
            ),
          )
        : null;

    if (controller.showOverview || controller.visibleAppIds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?banner,
          Expanded(child: AppOverview(controller: controller)),
        ],
      );
    }

    final ids = controller.visibleAppIds.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?banner,
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final id in ids)
                AppSection(
                  key: ValueKey('section_$id'),
                  appId: id,
                  controller: controller,
                  onOpenAsTab: onOpenAsTab,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tracking = controller.visibleAppIds.length;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.panelBackground,
            border: Border(bottom: BorderSide(color: colors.borderColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  controller.showOverview || tracking == 0
                      ? (controller.trackSelectedOnly
                            ? 'Tracked applications'
                            : 'All applications')
                      : (tracking == 1
                            ? controller.nameFor(controller.visibleAppIds.first)
                            : '$tracking applications'),
                  style: type.subtitle.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tooltip(
                message: controller.isPaused
                    ? 'Resume updates'
                    : 'Pause updates',
                child: IconButton(
                  icon: Icon(
                    controller.isPaused ? FluentIcons.play : FluentIcons.pause,
                    size: 14,
                  ),
                  onPressed: controller.isPaused
                      ? controller.resume
                      : controller.pause,
                ),
              ),
              Tooltip(
                message: 'Refresh now',
                child: IconButton(
                  icon: const Icon(FluentIcons.refresh, size: 14),
                  onPressed: controller.refresh,
                ),
              ),
              Tooltip(
                message: 'App Mode settings',
                child: IconButton(
                  icon: const Icon(FluentIcons.settings, size: 14),
                  onPressed: () =>
                      showAppModeSettings(context, controller.settings),
                ),
              ),
              const SizedBox(width: 4),
              DropDownButton(
                leading: const Icon(FluentIcons.download, size: 12),
                title: const Text('Export'),
                items: [
                  MenuFlyoutItem(
                    text: const Text('Copy endpoints as CSV'),
                    onPressed: () => _export(context, csv: true),
                  ),
                  MenuFlyoutItem(
                    text: const Text('Copy endpoints as JSON'),
                    onPressed: () => _export(context, csv: false),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _export(BuildContext context, {required bool csv}) {
    final endpoints = [
      for (final id in controller.visibleAppIds)
        ...controller.filteredEndpointsFor(id),
    ];
    if (endpoints.isEmpty) {
      displayInfoBar(
        context,
        builder: (context, close) => const InfoBar(
          title: Text('Nothing to export'),
          content: Text('Select or pin an app first.'),
          severity: InfoBarSeverity.warning,
        ),
      );
      return;
    }
    final records = endpointRecords(
      endpoints,
      controller.nameFor,
      controller.settings.lossAlertPercent,
    );
    copyWithToast(
      context,
      csv ? endpointsToCsv(records) : endpointsToJson(records),
      '${records.length} endpoints as ${csv ? 'CSV' : 'JSON'}',
    );
  }
}

class _AppRail extends StatelessWidget {
  const _AppRail({required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final apps = controller.apps;
        final pinned = controller.pinnedIds;
        final pinnedApps = [
          for (final id in pinned) controller.snapshotFor(id),
        ];
        final others = [
          for (final a in apps)
            if (!pinned.contains(a.id)) a,
        ];

        return Container(
          color: colors.panelBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextBox(
                  placeholder: 'Search apps',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(FluentIcons.search, size: 12),
                  ),
                  onChanged: controller.setSearch,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Checkbox(
                      checked: controller.hideSystem,
                      semanticLabel: 'Hide system apps',
                      onChanged: (v) => controller.setHideSystem(v ?? true),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            controller.setHideSystem(!controller.hideSystem),
                        child: Text(
                          'Hide system apps',
                          style: type.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _RailTile(
                title: 'Overview',
                subtitle: controller.trackSelectedOnly
                    ? '${pinned.length} app${pinned.length == 1 ? '' : 's'} tracked'
                    : '${controller.overview.appCount} apps online',
                leading: Icon(FluentIcons.home, size: 14, color: colors.accent),
                selected: controller.showOverview,
                onTap: controller.openOverview,
              ),
              if (controller.trackSelectedOnly) ...[
                _RailTile(
                  title: 'Tracked apps',
                  subtitle: pinned.isEmpty
                      ? 'tick apps below'
                      : 'details for ${pinned.length}',
                  leading: Icon(
                    FluentIcons.view_all,
                    size: 14,
                    color: pinned.isEmpty
                        ? colors.textSecondary
                        : colors.accent,
                  ),
                  selected: !controller.showOverview && pinned.isNotEmpty,
                  onTap: controller.showTracked,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Button(
                        onPressed: others.isEmpty
                            ? null
                            : () => controller.trackAll([
                                for (final a in others) a.id,
                              ]),
                        child: const Text('Tick all shown'),
                      ),
                      Button(
                        onPressed: pinned.isEmpty
                            ? null
                            : controller.clearTracked,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              ],
              Divider(
                style: DividerThemeData(horizontalMargin: EdgeInsets.zero),
              ),
              Expanded(
                child: apps.isEmpty && pinned.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          controller.lastPolled == null
                              ? 'Looking for apps…'
                              : 'No apps with network activity.',
                          style: type.caption,
                        ),
                      )
                    : ListView(
                        children: [
                          if (pinned.isNotEmpty) ...[
                            _RailLabel(
                              controller.trackSelectedOnly
                                  ? 'Tracked (${pinned.length})'
                                  : 'Pinned',
                              type,
                            ),
                            for (final id in pinned)
                              _appTile(
                                controller,
                                id,
                                pinnedApps[pinned.toList().indexOf(id)],
                              ),
                          ],
                          if (others.isNotEmpty) ...[
                            _RailLabel(
                              controller.trackSelectedOnly
                                  ? 'Available apps'
                                  : 'Applications',
                              type,
                            ),
                            for (final a in others)
                              _appTile(controller, a.id, a),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _appTile(AppsController c, String id, AppSnapshot? app) {
    final rate = c.rateFor(id);
    final total = rate.inBps + rate.outBps;
    final endpoints = app?.endpointCounts.length ?? 0;
    return _RailTile(
      title: c.nameFor(id),
      subtitle: app == null
          ? 'not running'
          : '$endpoints server${endpoints == 1 ? '' : 's'}'
                '${total >= 1 ? ' · ${formatRate(total)}' : ''}',
      leading: AppAvatar(name: c.nameFor(id)),
      selected: c.trackSelectedOnly
          ? c.isTracked(id)
          : c.selectedIds.contains(id),
      pinned: c.pinnedIds.contains(id),
      onTap: () => c.selectApp(id),
      // In choose-only mode the checkbox replaces the pin button.
      onPin: c.trackSelectedOnly ? null : () => c.togglePin(id),
      checked: c.trackSelectedOnly ? c.isTracked(id) : null,
    );
  }
}

class _RailLabel extends StatelessWidget {
  const _RailLabel(this.text, this.type);

  final String text;
  final AppTypography type;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
    child: Text(
      text.toUpperCase(),
      style: type.caption.copyWith(fontSize: 10, letterSpacing: 0.8),
    ),
  );
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.selected,
    required this.onTap,
    this.pinned = false,
    this.onPin,
    this.checked,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final bool selected;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback? onPin;

  /// Non-null in choose-only mode: shows a tick box for tracking.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
          decoration: BoxDecoration(
            color: selected ? colors.accent.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              if (checked != null) ...[
                Checkbox(
                  checked: checked,
                  semanticLabel: 'Track $title',
                  onChanged: (_) => onTap(),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(width: 28, height: 28, child: Center(child: leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: type.body.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: type.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onPin != null)
                Tooltip(
                  message: pinned ? 'Unpin' : 'Pin to keep it tracked',
                  child: IconButton(
                    icon: Icon(
                      pinned ? FluentIcons.pinned_solid : FluentIcons.pin,
                      size: 12,
                      color: pinned ? colors.accent : colors.textSecondary,
                    ),
                    onPressed: onPin,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final polled = controller.lastPolled;
        final s = controller.settings;
        final live = controller.isRunning;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colors.panelBackground,
            border: Border(top: BorderSide(color: colors.borderColor)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: live ? colors.latencyGood : colors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    controller.isPaused ? 'Paused' : (live ? 'Live' : 'Idle'),
                    'every ${s.pollIntervalSec}s',
                    '${controller.livePingerCount}/${s.maxLivePingers} pings',
                    if (controller.trackSelectedOnly)
                      '${controller.visibleAppIds.length} app(s) tracked',
                    s.includeUdp ? 'TCP + UDP (macOS)' : 'TCP only',
                    if (polled != null)
                      'updated ${DateFormat('HH:mm:ss').format(polled)}',
                    'data stays on this device',
                  ].join(' · '),
                  style: type.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
