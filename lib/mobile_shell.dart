import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/graph.dart';
import 'theme.dart';
import 'shared_widgets.dart';
import 'navbar.dart';
import 'flow_session.dart';

/// Tabbed presentation for narrow (phone) screens: splits data into
/// Overview / Hops / Graph with a bottom navigation bar, and supports
/// switching between parallel active flow sessions.
class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.flows,
    required this.currentFlowIndex,
    required this.onFlowSelected,
    required this.onAddFlow,
    required this.onCloseFlow,
    required this.showSettings,
  });

  final List<FlowSession> flows;
  final int currentFlowIndex;
  final ValueChanged<int> onFlowSelected;
  final VoidCallback onAddFlow;
  final ValueChanged<int> onCloseFlow;
  final VoidCallback showSettings;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _tabIndex = 0;
  int _selectedHop = 1;
  String _dataType = 'lt';

  void _openHop(int hop) {
    setState(() {
      _selectedHop = hop;
      _tabIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    final safeIndex = widget.currentFlowIndex.clamp(0, widget.flows.length - 1);
    final currentSession = widget.flows[safeIndex];

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
      ),
      _HopsTab(
        data: currentSession.tracerouteResult,
        ipStats: currentSession.ipStats,
        isLoading: currentSession.isLoading,
        isSuccess: currentSession.success,
        colors: colors,
        type: type,
        onSelectHop: _openHop,
      ),
      _GraphTab(
        ipStats: currentSession.ipStats,
        deepStats: currentSession.deepStats,
        isSuccess: currentSession.success,
        isLoading: currentSession.isLoading,
        selectedHop: _selectedHop,
        onSelectHop: (h) => setState(() => _selectedHop = h),
        dataType: _dataType,
        onSelectDataType: (t) => setState(() => _dataType = t),
        interval: currentSession.interval,
        isRunning: currentSession.isRunning,
        totalPackets: currentSession.packetSent,
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
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.flows.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final flow = widget.flows[index];
                      final isSelected = index == safeIndex;
                      return GestureDetector(
                        onTap: () => widget.onFlowSelected(index),
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
                                const SizedBox(width: 2),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onCloseFlow(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
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
          ),
          Expanded(
            child: IndexedStack(index: _tabIndex, children: pages),
          ),
          _BottomTabBar(
            index: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
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
    required this.colors,
    required this.type,
  });
  final int index;
  final void Function(int) onChanged;
  final AppColors colors;
  final AppTypography type;

  static const _tabs = [
    (FluentIcons.view_dashboard, 'Overview'),
    (FluentIcons.list, 'Hops'),
    (FluentIcons.line_chart, 'Graph'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.panelBackground,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < _tabs.length; i++)
            Expanded(
              child: HoverButton(
                onPressed: () => onChanged(i),
                builder: (context, states) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Icon(
                        _tabs[i].$1,
                        size: 20,
                        color: index == i
                            ? colors.accent
                            : colors.textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabs[i].$2,
                        style: type.caption.copyWith(
                          color: index == i
                              ? colors.accent
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
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

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  String _dataType = 'lt';

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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusHeader(
            target: widget.target,
            isRunning: widget.isRunning,
            colors: colors,
            type: type,
          ),
          const SizedBox(height: 16),
          Text('Overview', style: type.title),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
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
            const SizedBox(height: 16),
            Text('Needs attention', style: type.title),
            const SizedBox(height: 12),
            _WorstHopCard(
              hop: worstHop,
              colors: colors,
              type: type,
              onTap: () => widget.onSelectHop(worstHop.$1),
            ),
          ],
          if (widget.deepStats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Target Chart', style: type.title),
            const SizedBox(height: 12),
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

  /// Picks the hop most worth surfacing: highest packet loss first, then
  /// highest latency, matching the severity ordering StatTile already uses
  /// for the packet-loss/latency tiles. Returns (hopNumber, stat) or null
  /// when every hop is clean.
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
  });
  final String target;
  final bool isRunning;
  final AppColors colors;
  final AppTypography type;

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
                  isRunning ? 'Probing…' : 'Paused',
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

class _HopsTab extends StatelessWidget {
  const _HopsTab({
    required this.data,
    required this.ipStats,
    required this.isLoading,
    required this.isSuccess,
    required this.colors,
    required this.type,
    required this.onSelectHop,
  });
  final List<Map<String, dynamic>>? data;
  final List<Map<String, dynamic>> ipStats;
  final bool isLoading;
  final bool isSuccess;
  final AppColors colors;
  final AppTypography type;
  final void Function(int hop) onSelectHop;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: ProgressRing());
    if (!isSuccess || data == null || data!.isEmpty) {
      return Center(child: Text('No hops yet', style: type.subtitle));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: data!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final hop = data![index];
        final stat = ipStats[index];
        final hopNum = hop['hop'] as int;
        return HoverButton(
          onPressed: () => onSelectHop(hopNum),
          builder: (context, states) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.panelBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderColor),
            ),
            child: Row(
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${hop['ip']}'.isEmpty ? 'Timed out' : '${hop['ip']}',
                        style: type.bodyStrong,
                      ),
                      Text(
                        '${hop['name']}',
                        style: type.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${stat['last']}ms',
                  style: type.body.copyWith(
                    color: latencyColor(colors, stat['last'] as int),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  FluentIcons.chevron_right,
                  size: 14,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GraphTab extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
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
