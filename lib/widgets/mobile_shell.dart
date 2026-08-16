import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../dialogs/ip_info_dialog.dart';
import '../dialogs/snapshot_dialog.dart';
import '../models/flow_session.dart';
import '../models/snapshot.dart';
import '../models/target_directory.dart';
import 'graph.dart';
import 'navbar.dart';
import 'shared_widgets.dart';
import 'timeline_chart.dart';

/// Tabbed presentation for narrow (phone) screens: splits data into
/// Overview / Hops / Graph / Timeline with a bottom navigation bar, and supports
/// switching between parallel active flow sessions, sorting/searching hops,
/// hop context actions, and full telemetry inspection.
class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.flows,
    required this.currentFlowIndex,
    required this.onFlowSelected,
    required this.onAddFlow,
    required this.onCloseFlow,
    required this.showSettings,
    this.onExport,
    this.onReset,
    this.onOpenInNewTab,
    this.onToggleStatistics,
    this.onDuplicateFlow,
    this.onCloseOtherFlows,
    this.onSaveSnapshot,
    this.onOpenSnapshot,
  });

  final List<FlowSession> flows;
  final int currentFlowIndex;
  final ValueChanged<int> onFlowSelected;
  final VoidCallback onAddFlow;
  final ValueChanged<int> onCloseFlow;
  final VoidCallback showSettings;
  final ValueChanged<FlowSession>? onExport;
  final VoidCallback? onReset;
  final ValueChanged<String>? onOpenInNewTab;
  final VoidCallback? onToggleStatistics;
  final ValueChanged<FlowSession>? onDuplicateFlow;
  final ValueChanged<int>? onCloseOtherFlows;
  final ValueChanged<FlowSession>? onSaveSnapshot;
  final ValueChanged<Snapshot>? onOpenSnapshot;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tabIndex = 0;
  int? _selectedHop;
  String _dataType = 'lt';

  void _openHop(int hop) {
    setState(() {
      _selectedHop = hop;
      _tabIndex = 2; // Graph Tab
    });
  }

  void _openHopTimeline(int hop) {
    setState(() {
      _selectedHop = hop;
      _tabIndex = 3; // Timeline Tab
    });
  }

  void _showTabOptions(BuildContext context, int index, FlowSession flow) {
    showDialog(
      context: context,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (context) {
        final colors = appColors(context);
        final type = appTypography(context);

        return ContentDialog(
          title: Text(flow.title, style: type.subtitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(FluentIcons.copy, size: 16, color: colors.accent),
                title: Text('Copy Target (${flow.ip})', style: type.body),
                onPressed: () {
                  Navigator.of(context).pop();
                  Clipboard.setData(ClipboardData(text: flow.ip));
                  displayInfoBar(
                    context,
                    builder: (_, __) => InfoBar(
                      title: const Text('Target Copied'),
                      content: Text('"${flow.ip}" copied to clipboard.'),
                      severity: InfoBarSeverity.success,
                    ),
                  );
                },
              ),
              if (widget.onDuplicateFlow != null)
                ListTile(
                  leading: Icon(FluentIcons.add, size: 16, color: colors.accent),
                  title: Text('Duplicate Tab', style: type.body),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDuplicateFlow!(flow);
                  },
                ),
              if (widget.onSaveSnapshot != null)
                ListTile(
                  leading: Icon(FluentIcons.camera, size: 16, color: colors.accent),
                  title: Text('Save Snapshot', style: type.body),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onSaveSnapshot!(flow);
                  },
                ),
              if (widget.onExport != null)
                ListTile(
                  leading: Icon(FluentIcons.share, size: 16, color: colors.accent),
                  title: Text('Export & Share Report', style: type.body),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onExport!(flow);
                  },
                ),
              if (widget.flows.length > 1 && widget.onCloseOtherFlows != null)
                ListTile(
                  leading: Icon(FluentIcons.clear, size: 16, color: colors.latencyBad),
                  title: Text('Close Other Tabs', style: type.body),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onCloseOtherFlows!(index);
                  },
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    final safeIndex = widget.currentFlowIndex.clamp(0, widget.flows.length - 1);
    final currentSession = widget.flows[safeIndex];

    final defaultHop = currentSession.deepStats.isNotEmpty ? currentSession.deepStats.length : 1;
    final effectiveSelectedHop = (_selectedHop ?? defaultHop).clamp(
      1,
      currentSession.deepStats.isNotEmpty ? currentSession.deepStats.length : 1,
    );

    final pages = [
      _OverviewTab(
        target: currentSession.title,
        isRunning: currentSession.isRunning,
        ipStats: currentSession.ipStats,
        deepStats: currentSession.deepStats,
        isSuccess: currentSession.success,
        isLoading: currentSession.isLoading,
        colors: colors,
        type: type,
        interval: currentSession.interval,
        onSelectHop: _openHop,
        onToggleStatistics: widget.onToggleStatistics,
      ),
      _HopsTab(
        data: currentSession.tracerouteResult,
        ipStats: currentSession.ipStats,
        deepStats: currentSession.deepStats,
        isLoading: currentSession.isLoading,
        isSuccess: currentSession.success,
        colors: colors,
        type: type,
        onSelectHop: _openHop,
        onSelectHopTimeline: _openHopTimeline,
        onOpenInNewTab: widget.onOpenInNewTab,
        onToggleStatistics: widget.onToggleStatistics,
      ),
      _GraphTab(
        ipStats: currentSession.ipStats,
        deepStats: currentSession.deepStats,
        isSuccess: currentSession.success,
        isLoading: currentSession.isLoading,
        selectedHop: effectiveSelectedHop,
        onSelectHop: (h) => setState(() => _selectedHop = h),
        dataType: _dataType,
        onSelectDataType: (t) => setState(() => _dataType = t),
        interval: currentSession.interval,
        isRunning: currentSession.isRunning,
        totalPackets: currentSession.packetSent,
        colors: colors,
        type: type,
        onToggleStatistics: widget.onToggleStatistics,
      ),
      _TimelineTab(
        deepStats: currentSession.deepStats,
        events: currentSession.timelineEvents,
        timelineHistory: currentSession.timelineHistory,
        selectedHop: effectiveSelectedHop,
        onSelectHop: (h) => setState(() => _selectedHop = h),
        interval: currentSession.interval,
        isRunning: currentSession.isRunning,
        isLoading: currentSession.isLoading,
        isSuccess: currentSession.success,
        colors: colors,
        type: type,
      ),
      _SnapshotsTab(
        onOpenSnapshot: widget.onOpenSnapshot,
        colors: colors,
        type: type,
      ),
    ];

    return SafeArea(
      child: Column(
        children: [
          // Flow session selector bar for mobile
          Container(
            height: 44,
            color: colors.panelBackground,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.flows.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final flow = widget.flows[index];
                      final isSelected = index == safeIndex;
                      return GestureDetector(
                        onTap: () => widget.onFlowSelected(index),
                        onLongPress: () => _showTabOptions(context, index, flow),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.accent.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: isSelected
                                ? Border.all(color: colors.accent, width: 1)
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (flow.isRunning) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: colors.latencyGood,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ] else if (flow.isLoading) ...[
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: ProgressRing(strokeWidth: 2),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                flow.title,
                                style: type.caption.copyWith(
                                  color: isSelected
                                      ? colors.accent
                                      : colors.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              if (widget.flows.length > 1) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onCloseFlow(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      FluentIcons.chrome_close,
                                      size: 10,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                TouchIconButton(
                  icon: Icon(FluentIcons.add, size: 14, color: colors.accent),
                  iconSize: 14,
                  onPressed: widget.onAddFlow,
                ),
              ],
            ),
          ),
          const Divider(),
          Navbar(
            ipController: currentSession.ipController,
            intervalController: currentSession.intervalController,
            execTraceroute: () => currentSession.execTraceroute(),
            isRunning: currentSession.isRunning,
            showSettings: widget.showSettings,
            setText: currentSession.setText,
            onExport: widget.onExport != null
                ? () => widget.onExport!(currentSession)
                : null,
            onSaveSnapshot: widget.onSaveSnapshot != null
                ? () => widget.onSaveSnapshot!(currentSession)
                : null,
            onReset: currentSession.reset,
            hasData: currentSession.dataCollected || currentSession.ipStats.isNotEmpty,
          ),
          Expanded(
            child: IndexedStack(index: _tabIndex, children: pages),
          ),
          _BottomTabBar(
            index: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
            incidentCount: currentSession.timelineEvents.length,
            colors: colors,
            type: type,
          ),
        ],
      ),
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({
    required this.index,
    required this.onChanged,
    required this.incidentCount,
    required this.colors,
    required this.type,
  });
  final int index;
  final void Function(int) onChanged;
  final int incidentCount;
  final AppColors colors;
  final AppTypography type;

  static const _tabs = [
    (FluentIcons.view_dashboard, 'Overview'),
    (FluentIcons.list, 'Hops'),
    (FluentIcons.line_chart, 'Graph'),
    (FluentIcons.timeline_progress, 'Timeline'),
    (FluentIcons.history, 'Snapshots'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.panelBackground,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (int i = 0; i < _tabs.length; i++)
            Expanded(
              child: HoverButton(
                onPressed: () => onChanged(i),
                builder: (context, states) {
                  final isSelected = index == i;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              _tabs[i].$1,
                              size: 20,
                              color: isSelected
                                  ? colors.accent
                                  : colors.textSecondary,
                            ),
                            if (i == 3 && incidentCount > 0)
                              Positioned(
                                right: -8,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 14,
                                    minHeight: 14,
                                  ),
                                  child: Center(
                                    child: Text(
                                      incidentCount > 99 ? '99+' : '$incidentCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _tabs[i].$2,
                          style: type.caption.copyWith(
                            color: isSelected
                                ? colors.accent
                                : colors.textSecondary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({
    required this.target,
    required this.isRunning,
    required this.ipStats,
    required this.deepStats,
    required this.isSuccess,
    required this.isLoading,
    required this.colors,
    required this.type,
    required this.interval,
    required this.onSelectHop,
    this.onToggleStatistics,
  });
  final String target;
  final bool isRunning;
  final List<Map<String, dynamic>> ipStats;
  final List<Map<String, dynamic>> deepStats;
  final bool isSuccess;
  final bool isLoading;
  final AppColors colors;
  final AppTypography type;
  final int interval;
  final void Function(int hop) onSelectHop;
  final VoidCallback? onToggleStatistics;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  String _dataType = 'lt';
  // Overview/Hops/Graph/Timeline tabs are all kept mounted at once by the
  // parent IndexedStack, so on iOS this SingleChildScrollView would otherwise
  // share the ambient PrimaryScrollController with _GraphTab's — the same
  // "ScrollController attached to more than one ScrollPosition" collision as
  // the 4-flow grid / BottomData crashes.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final type = widget.type;

    if (widget.isLoading) return const Center(child: ProgressRing());
    if (!widget.isSuccess || widget.ipStats.isEmpty) {
      return Center(
        child: Text('Start a traceroute to see stats', style: type.subtitle),
      );
    }

    final tiles = statTileData(widget.ipStats, widget.deepStats, colors);
    final worstHop = _worstHop(widget.ipStats);

    return SingleChildScrollView(
      primary: false,
      controller: _scrollController,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusHeader(
            target: widget.target,
            isRunning: widget.isRunning,
            colors: colors,
            type: type,
            onToggleStatistics: widget.onToggleStatistics,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Overview', style: type.title),
              if (widget.onToggleStatistics != null)
                Button(
                  onPressed: widget.onToggleStatistics,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.timeline_progress, size: 12, color: colors.accent),
                      const SizedBox(width: 4),
                      Text('All Hops', style: type.caption.copyWith(color: colors.accent)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.3,
            children: [
              for (final tile in tiles)
                StatTile(
                  icon: tile.$1,
                  label: tile.$2,
                  value: tile.$3,
                  valueColor: tile.$4,
                  colors: colors,
                  type: type,
                ),
            ],
          ),
          if (worstHop != null) ...[
            const SizedBox(height: 14),
            Text('Needs attention', style: type.title),
            const SizedBox(height: 8),
            _WorstHopCard(
              hop: worstHop,
              colors: colors,
              type: type,
              onTap: () => widget.onSelectHop(worstHop.$1),
            ),
          ],
          if (widget.deepStats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Target Live Latency', style: type.title),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.panelBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.borderColor),
              ),
              child: Column(
                children: [
                  GraphTypePills(
                    dataType: _dataType,
                    onSelect: (t) => setState(() => _dataType = t),
                    colors: colors,
                    type: type,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: Graph(
                      data: widget.deepStats.last,
                      dataType: _dataType,
                      interval: widget.interval,
                      isRunning: widget.isRunning,
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

  (int, Map<String, dynamic>)? _worstHop(List<Map<String, dynamic>> stats) {
    Map<String, dynamic>? worst;
    int worstHopNum = -1;
    for (final stat in stats) {
      if (stat['ip']?.toString().isEmpty ?? true) continue;
      final pl = stat['pl'] as int? ?? 0;
      final max = stat['max'] as int? ?? -1;
      if (worst == null) {
        worst = stat;
        worstHopNum = stat['hop'] as int;
        continue;
      }
      final worstPl = worst['pl'] as int? ?? 0;
      final worstMax = worst['max'] as int? ?? -1;
      final isWorse = pl > worstPl || (pl == worstPl && max > worstMax);
      if (isWorse) {
        worst = stat;
        worstHopNum = stat['hop'] as int;
      }
    }
    if (worst == null) return null;
    final pl = worst['pl'] as int? ?? 0;
    final max = worst['max'] as int? ?? -1;
    if (pl <= 0 && max < 150) return null;
    return (worstHopNum, worst);
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.target,
    required this.isRunning,
    required this.colors,
    required this.type,
    this.onToggleStatistics,
  });
  final String target;
  final bool isRunning;
  final AppColors colors;
  final AppTypography type;
  final VoidCallback? onToggleStatistics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isRunning ? colors.latencyGood : colors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target,
                  style: type.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isRunning ? 'Probing actively…' : 'Probing paused',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorstHopCard extends StatelessWidget {
  const _WorstHopCard({
    required this.hop,
    required this.colors,
    required this.type,
    required this.onTap,
  });
  final (int, Map<String, dynamic>) hop;
  final AppColors colors;
  final AppTypography type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hopNum = hop.$1;
    final stat = hop.$2;
    final pl = stat['pl'] as int? ?? 0;
    final max = stat['max'] as int? ?? -1;
    final name = '${stat['name']}'.isEmpty || stat['name'] == 'Unknown'
        ? '${stat['ip']}'
        : '${stat['name']}';

    return HoverButton(
      onPressed: onTap,
      builder: (context, states) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.panelBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.latencyBad.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.latencyBad.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.warning,
                size: 14,
                color: colors.latencyBad,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hop $hopNum · $name',
                    style: type.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    pl > 0
                        ? '$pl% packet loss · ${max}ms max'
                        : '${max}ms max latency',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              FluentIcons.chevron_right,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _HopsTab extends StatefulWidget {
  const _HopsTab({
    required this.data,
    required this.ipStats,
    required this.deepStats,
    required this.isLoading,
    required this.isSuccess,
    required this.colors,
    required this.type,
    required this.onSelectHop,
    required this.onSelectHopTimeline,
    this.onOpenInNewTab,
    this.onToggleStatistics,
  });

  final List<Map<String, dynamic>>? data;
  final List<Map<String, dynamic>> ipStats;
  final List<Map<String, dynamic>> deepStats;
  final bool isLoading;
  final bool isSuccess;
  final AppColors colors;
  final AppTypography type;
  final void Function(int hop) onSelectHop;
  final void Function(int hop) onSelectHopTimeline;
  final ValueChanged<String>? onOpenInNewTab;
  final VoidCallback? onToggleStatistics;

  @override
  State<_HopsTab> createState() => _HopsTabState();
}

class _HopsTabState extends State<_HopsTab> {
  String _filterQuery = '';
  bool _isSearchOpen = false;
  String _sortBy = 'hop'; // 'hop', 'latency', 'loss', 'ip'
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showHopActionSheet(
    BuildContext context,
    Map<String, dynamic> hop,
    Map<String, dynamic> stat,
  ) {
    final hopNum = hop['hop'] as int;
    final ip = hop['ip']?.toString() ?? '';
    final name = hop['name']?.toString() ?? '';
    final colors = widget.colors;
    final type = widget.type;

    showDialog(
      context: context,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (context) {
        return ContentDialog(
          title: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text('$hopNum', style: type.caption.copyWith(color: colors.accent, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(ip.isNotEmpty ? ip : 'Hop #$hopNum', style: type.subtitle, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ip.isNotEmpty) ...[
                ListTile(
                  leading: Icon(FluentIcons.copy, size: 16, color: colors.accent),
                  title: Text('Copy IP ($ip)', style: type.body),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Clipboard.setData(ClipboardData(text: ip));
                    displayInfoBar(
                      context,
                      builder: (_, __) => InfoBar(
                        title: const Text('IP Copied'),
                        content: Text('"$ip" copied to clipboard.'),
                        severity: InfoBarSeverity.success,
                      ),
                    );
                  },
                ),
                if (name.isNotEmpty && name != 'Unknown')
                  ListTile(
                    leading: Icon(FluentIcons.tag, size: 16, color: colors.accent),
                    title: Text('Copy Domain ($name)', style: type.body),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Clipboard.setData(ClipboardData(text: name));
                      displayInfoBar(
                        context,
                        builder: (_, __) => InfoBar(
                          title: const Text('Domain Copied'),
                          content: Text('"$name" copied to clipboard.'),
                          severity: InfoBarSeverity.success,
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: Icon(FluentIcons.favorite_star, size: 16, color: colors.accent),
                  title: const Text('Bookmark to IP Directory'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    TargetDirectory.instance.saveTarget(
                      ip,
                      name: name.isNotEmpty ? name : 'Hop $hopNum',
                      note: 'Intermediate hop #$hopNum',
                    );
                    displayInfoBar(
                      context,
                      builder: (_, __) => InfoBar(
                        title: const Text('Bookmarked'),
                        content: Text('$ip saved to your IP Directory.'),
                        severity: InfoBarSeverity.success,
                      ),
                    );
                  },
                ),
                if (widget.onOpenInNewTab != null)
                  ListTile(
                    leading: Icon(FluentIcons.open_in_new_tab, size: 16, color: colors.accent),
                    title: Text('Ping Hop #$hopNum in New Tab'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenInNewTab!(ip);
                    },
                  ),
                ListTile(
                  leading: Icon(FluentIcons.globe, size: 16, color: colors.accent),
                  title: const Text('IP Info (Location, ISP...)'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    showIpInfoDialog(context, ip, name: name);
                  },
                ),
              ],
              ListTile(
                leading: Icon(FluentIcons.line_chart, size: 16, color: colors.accent),
                title: const Text('Inspect Live Graph'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onSelectHop(hopNum);
                },
              ),
              ListTile(
                leading: Icon(FluentIcons.timeline_progress, size: 16, color: colors.accent),
                title: const Text('View Timeline History'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onSelectHopTimeline(hopNum);
                },
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  List<int> _getFilteredIndices() {
    final total = widget.data?.length ?? 0;
    if (total == 0) return [];

    List<int> indices = List.generate(total, (i) => i);

    if (_filterQuery.trim().isNotEmpty) {
      final query = _filterQuery.trim().toLowerCase();
      indices = indices.where((i) {
        final hop = widget.data![i];
        final ip = (hop['ip'] ?? '').toString().toLowerCase();
        final name = (hop['name'] ?? '').toString().toLowerCase();
        final hopStr = (hop['hop'] ?? '').toString();
        return ip.contains(query) || name.contains(query) || hopStr == query;
      }).toList();
    }

    if (_sortBy == 'latency') {
      indices.sort((a, b) {
        final statA = a < widget.ipStats.length ? widget.ipStats[a] : <String, dynamic>{};
        final statB = b < widget.ipStats.length ? widget.ipStats[b] : <String, dynamic>{};
        final lastA = (statA['last'] is num) ? statA['last'] as num : -1;
        final lastB = (statB['last'] is num) ? statB['last'] as num : -1;
        return lastB.compareTo(lastA); // Highest latency first
      });
    } else if (_sortBy == 'loss') {
      indices.sort((a, b) {
        final statA = a < widget.ipStats.length ? widget.ipStats[a] : <String, dynamic>{};
        final statB = b < widget.ipStats.length ? widget.ipStats[b] : <String, dynamic>{};
        final plA = (statA['pl'] is num) ? statA['pl'] as num : 0;
        final plB = (statB['pl'] is num) ? statB['pl'] as num : 0;
        return plB.compareTo(plA); // Highest packet loss first
      });
    } else if (_sortBy == 'ip') {
      indices.sort((a, b) {
        final ipA = (widget.data![a]['ip'] ?? '').toString();
        final ipB = (widget.data![b]['ip'] ?? '').toString();
        return ipA.compareTo(ipB);
      });
    }

    return indices;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final type = widget.type;

    if (widget.isLoading) return const Center(child: ProgressRing());
    if (!widget.isSuccess || widget.data == null || widget.data!.isEmpty) {
      return Center(child: Text('No hops yet', style: type.subtitle));
    }

    final filteredIndices = _getFilteredIndices();

    return Column(
      children: [
        // Filter & Sort Control Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: colors.panelBackgroundAlt,
          child: _isSearchOpen
              ? Row(
                  children: [
                    Icon(FluentIcons.search, size: 14, color: colors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextBox(
                        autofocus: true,
                        placeholder: 'Filter by IP, host, hop #...',
                        controller: _searchController,
                        style: type.caption,
                        onChanged: (text) => setState(() => _filterQuery = text),
                        suffix: _searchController.text.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _filterQuery = '');
                                  },
                                  child: Icon(FluentIcons.clear, size: 10, color: colors.textSecondary),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                    TouchIconButton(
                      icon: Icon(FluentIcons.chrome_close, size: 12, color: colors.textSecondary),
                      iconSize: 12,
                      onPressed: () {
                        setState(() {
                          _isSearchOpen = false;
                          _searchController.clear();
                          _filterQuery = '';
                        });
                      },
                    ),
                  ],
                )
              : Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${widget.data!.length} Hops',
                        style: type.caption.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropDownButton(
                      title: Text(
                        _sortBy == 'hop'
                            ? 'Hop #'
                            : _sortBy == 'latency'
                            ? 'Latency'
                            : _sortBy == 'loss'
                            ? 'Loss %'
                            : 'IP',
                        style: type.caption,
                      ),
                      items: [
                        MenuFlyoutItem(
                          text: const Text('Hop Number (Default)'),
                          onPressed: () => setState(() => _sortBy = 'hop'),
                        ),
                        MenuFlyoutItem(
                          text: const Text('Highest Latency First'),
                          onPressed: () => setState(() => _sortBy = 'latency'),
                        ),
                        MenuFlyoutItem(
                          text: const Text('Highest Packet Loss First'),
                          onPressed: () => setState(() => _sortBy = 'loss'),
                        ),
                        MenuFlyoutItem(
                          text: const Text('IP Address'),
                          onPressed: () => setState(() => _sortBy = 'ip'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    TouchIconButton(
                      icon: Icon(FluentIcons.search, size: 14, color: colors.textSecondary),
                      iconSize: 14,
                      onPressed: () => setState(() => _isSearchOpen = true),
                    ),
                    if (widget.onToggleStatistics != null) ...[
                      const SizedBox(width: 2),
                      TouchIconButton(
                        icon: Icon(FluentIcons.timeline_progress, size: 14, color: colors.textSecondary),
                        iconSize: 14,
                        onPressed: widget.onToggleStatistics,
                      ),
                    ],
                  ],
                ),
        ),
        const Divider(),
        Expanded(
          child: filteredIndices.isEmpty
              ? Center(
                  child: Text(
                    'No hops match "$_filterQuery"',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                )
              : ListView.separated(
                  primary: false,
                  padding: const EdgeInsets.all(10),
                  itemCount: filteredIndices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final originalIndex = filteredIndices[i];
                    final hop = widget.data![originalIndex];
                    final stat = widget.ipStats[originalIndex];
                    final hopNum = hop['hop'] as int;

                    final rawIp = hop['ip']?.toString() ?? '';
                    final isTimeout = rawIp.isEmpty;
                    final lastVal = stat['last'] != -1 ? '${stat['last']}ms' : '-';
                    final avgVal = stat['avg'] != -1 ? '${stat['avg']}ms' : '-';
                    final plVal = stat['pl'] as int? ?? 0;

                    return GestureDetector(
                      onTap: () => widget.onSelectHop(hopNum),
                      onLongPress: () => _showHopActionSheet(context, hop, stat),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.panelBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: colors.accent.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$hopNum',
                                    style: type.caption.copyWith(
                                      color: colors.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isTimeout ? 'Timed out' : rawIp,
                                        style: type.bodyStrong,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if ((hop['name']?.toString() ?? '').isNotEmpty && hop['name'] != 'Unknown')
                                        Text(
                                          '${hop['name']}',
                                          style: type.caption.copyWith(color: colors.textSecondary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  lastVal,
                                  style: type.bodyStrong.copyWith(
                                    color: latencyColor(colors, stat['last'] as int? ?? -1),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                TouchIconButton(
                                  icon: Icon(FluentIcons.more, size: 14, color: colors.textSecondary),
                                  iconSize: 14,
                                  onPressed: () => _showHopActionSheet(context, hop, stat),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Metric chips row (Min, Max, Avg, PL%)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _CompactStatChip(
                                  label: 'Avg',
                                  value: avgVal,
                                  colors: colors,
                                  type: type,
                                ),
                                _CompactStatChip(
                                  label: 'Min',
                                  value: stat['min'] != -1 ? '${stat['min']}ms' : '-',
                                  colors: colors,
                                  type: type,
                                ),
                                _CompactStatChip(
                                  label: 'Max',
                                  value: stat['max'] != -1 ? '${stat['max']}ms' : '-',
                                  colors: colors,
                                  type: type,
                                ),
                                _CompactStatChip(
                                  label: 'Loss',
                                  value: '$plVal%',
                                  valueColor: plVal > 0 ? colors.latencyBad : colors.latencyGood,
                                  colors: colors,
                                  type: type,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CompactStatChip extends StatelessWidget {
  const _CompactStatChip({
    required this.label,
    required this.value,
    this.valueColor,
    required this.colors,
    required this.type,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.borderColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: type.caption.copyWith(
              fontSize: 10,
              color: colors.textSecondary,
            ),
          ),
          Text(
            value,
            style: type.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphTab extends StatefulWidget {
  const _GraphTab({
    required this.ipStats,
    required this.deepStats,
    required this.isSuccess,
    required this.isLoading,
    required this.selectedHop,
    required this.onSelectHop,
    required this.dataType,
    required this.onSelectDataType,
    required this.interval,
    required this.isRunning,
    required this.totalPackets,
    required this.colors,
    required this.type,
    this.onToggleStatistics,
  });
  final List<Map<String, dynamic>> ipStats;
  final List<Map<String, dynamic>> deepStats;
  final bool isSuccess;
  final bool isLoading;
  final int selectedHop;
  final void Function(int) onSelectHop;
  final String dataType;
  final void Function(String) onSelectDataType;
  final int interval;
  final bool isRunning;
  final int totalPackets;
  final AppColors colors;
  final AppTypography type;
  final VoidCallback? onToggleStatistics;

  @override
  State<_GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<_GraphTab> {
  // Overview/Hops/Graph/Timeline tabs are all kept mounted at once by the
  // parent IndexedStack, so on iOS this SingleChildScrollView would otherwise
  // share the ambient PrimaryScrollController with _OverviewTab's — the same
  // "ScrollController attached to more than one ScrollPosition" collision as
  // the 4-flow grid / BottomData crashes.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ipStats = widget.ipStats;
    final deepStats = widget.deepStats;
    final isSuccess = widget.isSuccess;
    final isLoading = widget.isLoading;
    final selectedHop = widget.selectedHop;
    final onSelectHop = widget.onSelectHop;
    final dataType = widget.dataType;
    final onSelectDataType = widget.onSelectDataType;
    final interval = widget.interval;
    final isRunning = widget.isRunning;
    final totalPackets = widget.totalPackets;
    final colors = widget.colors;
    final type = widget.type;
    final onToggleStatistics = widget.onToggleStatistics;

    if (isLoading) return const Center(child: ProgressRing());
    if (!isSuccess || deepStats.isEmpty) {
      return Center(child: Text('No data available', style: type.subtitle));
    }
    final hop = selectedHop.clamp(1, deepStats.length);
    final selectedStat = ipStats[hop - 1];
    final selectedDeep = deepStats[hop - 1];

    final String jitterVal = (selectedDeep['jitter'] as List).isNotEmpty
        ? '${selectedDeep['jitter'].last['value']}ms'
        : '-';
    final String latencyVal =
        (selectedDeep['pings'] as List).isNotEmpty &&
            selectedDeep['pings'].last['value'] != -1
        ? '${selectedDeep['pings'].last['value']}ms'
        : '-';
    final String minVal = selectedStat['min'] != -1
        ? '${selectedStat['min']}ms'
        : '-';
    final String maxVal = selectedStat['max'] != -1
        ? '${selectedStat['max']}ms'
        : '-';
    final String plVal = (selectedDeep['pl'] as List).isNotEmpty
        ? '${selectedDeep['pl'].last['value']}%'
        : '0%';
    final String avgVal = selectedStat['avg'] != -1
        ? '${selectedStat['avg']}ms'
        : '-';

    return SingleChildScrollView(
      primary: false,
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Select Hop:', style: type.caption.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (onToggleStatistics != null)
                Button(
                  onPressed: onToggleStatistics,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.timeline_progress, size: 12, color: colors.accent),
                      const SizedBox(width: 4),
                      Text('All Hops', style: type.caption.copyWith(color: colors.accent)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              primary: false,
              scrollDirection: Axis.horizontal,
              itemCount: deepStats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final hopNum = deepStats[index]['hop'] as int;
                return SizedBox(
                  width: 44,
                  child: ToggleButton(
                    checked: hopNum == hop,
                    onChanged: (_) => onSelectHop(hopNum),
                    child: Text('$hopNum'),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: Graph(
              data: selectedDeep,
              dataType: dataType,
              interval: interval,
              isRunning: isRunning,
            ),
          ),
          const SizedBox(height: 12),
          GraphTypeColumn(dataType: dataType, onSelect: onSelectDataType),
          const SizedBox(height: 12),
          StatTable(
            colors: colors,
            type: type,
            rows: [
              ('Jitter', jitterVal),
              ('Latency', latencyVal),
              ('Minimum', minVal),
              ('IP Address', '${selectedStat['ip']}'),
              ('Maximum', maxVal),
              ('Packet Loss', plVal),
              ('Domain Name', '${selectedStat['name']}'),
              ('Average Latency', avgVal),
              (
                'Packets Sent / Received',
                '${selectedStat['sentPackets']}/${selectedStat['receivedPackets']}',
              ),
              ('Total Packets', '$totalPackets'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotsTab extends StatelessWidget {
  const _SnapshotsTab({
    required this.onOpenSnapshot,
    required this.colors,
    required this.type,
  });

  final ValueChanged<Snapshot>? onOpenSnapshot;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SnapshotsListView(
        onOpenSnapshot: (snapshot) => onOpenSnapshot?.call(snapshot),
      ),
    );
  }
}

class _TimelineTab extends StatefulWidget {
  const _TimelineTab({
    required this.deepStats,
    required this.events,
    required this.timelineHistory,
    required this.selectedHop,
    required this.onSelectHop,
    required this.interval,
    required this.isRunning,
    required this.isLoading,
    required this.isSuccess,
    required this.colors,
    required this.type,
  });

  final List<Map<String, dynamic>> deepStats;
  final List<TimelineEvent> events;
  final List<List<Map<String, dynamic>>> timelineHistory;
  final int selectedHop;
  final ValueChanged<int> onSelectHop;
  final int interval;
  final bool isRunning;
  final bool isLoading;
  final bool isSuccess;
  final AppColors colors;
  final AppTypography type;

  @override
  State<_TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends State<_TimelineTab> {
  int _viewMode = 0; // 0 = Timeline Chart, 1 = Incident Log

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final type = widget.type;

    if (widget.isLoading) return const Center(child: ProgressRing());
    if (!widget.isSuccess || widget.deepStats.isEmpty) {
      return Center(child: Text('No timeline telemetry available', style: type.subtitle));
    }

    final safeHop = widget.selectedHop.clamp(1, widget.deepStats.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode Selector: Timeline Chart vs Incident Log
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: colors.panelBackgroundAlt,
          child: Row(
            children: [
              Expanded(
                child: _ModePill(
                  icon: FluentIcons.timeline_progress,
                  label: 'Timeline Chart',
                  isSelected: _viewMode == 0,
                  onTap: () => setState(() => _viewMode = 0),
                  colors: colors,
                  type: type,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModePill(
                  icon: FluentIcons.incident_triangle,
                  label: 'Incidents (${widget.events.length})',
                  isSelected: _viewMode == 1,
                  onTap: () => setState(() => _viewMode = 1),
                  colors: colors,
                  type: type,
                ),
              ),
            ],
          ),
        ),
        const Divider(),

        // Hop Selector for Timeline
        if (_viewMode == 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text('Hop:', style: type.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: ListView.separated(
                      primary: false,
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.deepStats.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final hopNum = widget.deepStats[index]['hop'] as int;
                        return SizedBox(
                          width: 40,
                          child: ToggleButton(
                            checked: hopNum == safeHop,
                            onChanged: (_) => widget.onSelectHop(hopNum),
                            child: Text('$hopNum'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _viewMode == 0
                ? TimelineChart(
                    deepStats: widget.deepStats,
                    events: widget.events,
                    selectedHop: safeHop,
                    interval: widget.interval,
                    isRunning: widget.isRunning,
                    timelineHistory: widget.timelineHistory,
                  )
                : _buildIncidentLogList(colors, type),
          ),
        ),
      ],
    );
  }

  Widget _buildIncidentLogList(AppColors colors, AppTypography type) {
    if (widget.events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.completed_solid, size: 30, color: Colors.green),
            const SizedBox(height: 10),
            Text(
              'No Network Incidents Recorded',
              style: type.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Packet loss drops and latency spikes will be automatically logged here with timestamps.',
              textAlign: TextAlign.center,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: widget.events.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final evt = widget.events[index];
        final isLoss = evt.type == TimelineEventType.packetLoss;
        final isSpike = evt.type == TimelineEventType.latencySpike;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.panelBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isLoss
                      ? Colors.red.withValues(alpha: 0.15)
                      : isSpike
                          ? Colors.orange.withValues(alpha: 0.15)
                          : colors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLoss
                      ? FluentIcons.warning
                      : isSpike
                          ? FluentIcons.speed_high
                          : FluentIcons.timeline_progress,
                  size: 14,
                  color: isLoss
                      ? Colors.red
                      : isSpike
                          ? Colors.orange
                          : colors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hop ${evt.hop} · ${evt.title}',
                      style: type.bodyStrong.copyWith(
                        color: isLoss
                            ? Colors.red
                            : isSpike
                                ? Colors.orange
                                : colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Triggered at ${_formatTimestamp(evt.timestamp)}',
                      style: type.caption.copyWith(color: colors.textSecondary),
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

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    required this.type,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? colors.accent.withValues(alpha: 0.15) : colors.panelBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderColor,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: type.caption.copyWith(
                  color: isSelected ? colors.accent : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
