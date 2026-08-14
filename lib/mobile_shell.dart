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
        ipStats: currentSession.ipStats,
        deepStats: currentSession.deepStats,
        isSuccess: currentSession.success,
        isLoading: currentSession.isLoading,
        colors: colors,
        type: type,
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

    return Column(
      children: [
        // Flow session selector bar for mobile
        Container(
          height: 38,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? colors.accent.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: isSelected ? Border.all(color: colors.accent, width: 1) : null,
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
                                color: isSelected ? colors.accent : colors.textPrimary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            if (widget.flows.length > 1) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => widget.onCloseFlow(index),
                                child: Icon(FluentIcons.chrome_close, size: 10, color: colors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                icon: Icon(FluentIcons.add, size: 14, color: colors.accent),
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
        Expanded(child: IndexedStack(index: _tabIndex, children: pages)),
        _BottomTabBar(
          index: _tabIndex,
          onChanged: (i) => setState(() => _tabIndex = i),
          colors: colors,
          type: type,
        ),
      ],
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({required this.index, required this.onChanged, required this.colors, required this.type});
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
                      Icon(_tabs[i].$1, size: 20, color: index == i ? colors.accent : colors.textSecondary),
                      const SizedBox(height: 4),
                      Text(_tabs[i].$2, style: type.caption.copyWith(color: index == i ? colors.accent : colors.textSecondary)),
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.ipStats, required this.deepStats, required this.isSuccess, required this.isLoading, required this.colors, required this.type});
  final List<Map<String, dynamic>> ipStats;
  final List<Map<String, dynamic>> deepStats;
  final bool isSuccess;
  final bool isLoading;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: ProgressRing());
    if (!isSuccess || ipStats.isEmpty) {
      return Center(child: Text('Start a traceroute to see stats', style: type.subtitle));
    }
    final tiles = statTileData(ipStats, deepStats, colors);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview', style: type.title),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final tile in tiles)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 16 * 2 - 10) / 2,
                  child: StatTile(icon: tile.$1, label: tile.$2, value: tile.$3, valueColor: tile.$4, colors: colors, type: type),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HopsTab extends StatelessWidget {
  const _HopsTab({required this.data, required this.ipStats, required this.isLoading, required this.isSuccess, required this.colors, required this.type, required this.onSelectHop});
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
                  decoration: BoxDecoration(color: colors.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Text('$hopNum', style: type.caption.copyWith(color: colors.accent, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${hop['ip']}'.isEmpty ? 'Timed out' : '${hop['ip']}', style: type.bodyStrong),
                      Text('${hop['name']}', style: type.caption, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text('${stat['last']}ms', style: type.body.copyWith(color: latencyColor(colors, stat['last'] as int))),
                const SizedBox(width: 8),
                Icon(FluentIcons.chevron_right, size: 14, color: colors.textSecondary),
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

    final String jitterVal = (selectedDeep['jitter'] as List).isNotEmpty ? '${selectedDeep['jitter'].last['value']}ms' : '-';
    final String latencyVal = (selectedDeep['pings'] as List).isNotEmpty && selectedDeep['pings'].last['value'] != -1 ? '${selectedDeep['pings'].last['value']}ms' : '-';
    final String minVal = selectedStat['min'] != -1 ? '${selectedStat['min']}ms' : '-';
    final String maxVal = selectedStat['max'] != -1 ? '${selectedStat['max']}ms' : '-';
    final String plVal = (selectedDeep['pl'] as List).isNotEmpty ? '${selectedDeep['pl'].last['value']}%' : '0%';
    final String avgVal = selectedStat['avg'] != -1 ? '${selectedStat['avg']}ms' : '-';

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
          Graph(data: selectedDeep, dataType: dataType, interval: interval, isRunning: isRunning),
          const SizedBox(height: 12),
          GraphTypeColumn(dataType: dataType, onSelect: onSelectDataType),
          const SizedBox(height: 12),
          StatTable(colors: colors, type: type, rows: [
            ('Jitter', jitterVal),
            ('Latency', latencyVal),
            ('Minimum', minVal),
            ('IP Address', '${selectedStat['ip']}'),
            ('Maximum', maxVal),
            ('Packet Loss', plVal),
            ('Domain Name', '${selectedStat['name']}'),
            ('Average Latency', avgVal),
            ('Packets Sent / Received', '${selectedStat['sentPackets']}/${selectedStat['receivedPackets']}'),
            ('Total Packets', '$totalPackets'),
          ]),
        ],
      ),
    );
  }
}
