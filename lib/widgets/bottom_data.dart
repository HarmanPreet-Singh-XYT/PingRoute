import 'package:fluent_ui/fluent_ui.dart';
import '../core/theme.dart';
import '../models/flow_session.dart';
import 'graph.dart';
import 'shared_widgets.dart';
import 'timeline_chart.dart';

class BottomData extends StatefulWidget {
  const BottomData({
    super.key,
    required this.IPStats,
    required this.deepStats,
    required this.interval,
    required this.isRunning,
    required this.graphInterval,
    required this.isLoading,
    required this.totalPackets,
    required this.dataCollected,
    required this.success,
    required this.toggleStatistics,
    this.events = const [],
    this.timelineHistory = const [],
    this.initialViewMode,
    this.onViewModeChanged,
    this.initialSelectedHop,
    this.onSelectedHopChanged,
    this.initialDataType,
    this.onDataTypeChanged,
  });

  final List<Map<String, dynamic>> IPStats;
  final List<Map<String, dynamic>> deepStats;
  final int totalPackets;
  final int graphInterval;
  final bool isLoading;
  final int interval;
  final bool isRunning;
  final bool dataCollected;
  final bool success;
  final Function() toggleStatistics;
  final List<TimelineEvent> events;
  final List<List<Map<String, dynamic>>> timelineHistory;
  final int? initialViewMode;
  final ValueChanged<int>? onViewModeChanged;
  final int? initialSelectedHop;
  final ValueChanged<int>? onSelectedHopChanged;
  final String? initialDataType;
  final ValueChanged<String>? onDataTypeChanged;

  @override
  State<BottomData> createState() => _BottomDataState();
}

class _BottomDataState extends State<BottomData> {
  late String dataType;
  int? _selectedHop;
  late int _viewMode;
  final ScrollController _hopScrollController = ScrollController();
  final ScrollController _statScrollController = ScrollController();
  final ScrollController _actionsScrollController = ScrollController();
  final ScrollController _incidentScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    dataType = widget.initialDataType ?? 'pl';
    _selectedHop = widget.initialSelectedHop;
    _viewMode = widget.initialViewMode ?? 0;
  }

  @override
  void didUpdateWidget(BottomData oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialViewMode != null && widget.initialViewMode != oldWidget.initialViewMode) {
      _viewMode = widget.initialViewMode!;
    }
    if (widget.initialSelectedHop != null && widget.initialSelectedHop != oldWidget.initialSelectedHop) {
      _selectedHop = widget.initialSelectedHop;
    }
    if (widget.initialDataType != null && widget.initialDataType != oldWidget.initialDataType) {
      dataType = widget.initialDataType!;
    }
  }

  @override
  void dispose() {
    _hopScrollController.dispose();
    _statScrollController.dispose();
    _actionsScrollController.dispose();
    _incidentScrollController.dispose();
    super.dispose();
  }

  void setGraphType(String type) {
    setState(() {
      dataType = type;
    });
    widget.onDataTypeChanged?.call(type);
  }

  void setHop(int hop) {
    setState(() {
      _selectedHop = hop;
    });
    widget.onSelectedHopChanged?.call(hop);
  }

  void setViewMode(int mode) {
    setState(() {
      _viewMode = mode;
    });
    widget.onViewModeChanged?.call(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    if (!(widget.dataCollected && widget.success)) {
      return Center(
        child: widget.isLoading
            ? const ProgressRing()
            : Text('No data available', style: type.title),
      );
    }

    final defaultHop = widget.IPStats.isNotEmpty ? widget.IPStats.length : 1;
    final safeSelectedHop = (_selectedHop ?? defaultHop).clamp(1, widget.IPStats.isNotEmpty ? widget.IPStats.length : 1);
    final selectedStat = widget.IPStats[safeSelectedHop - 1];
    final selectedDeep = widget.deepStats[safeSelectedHop - 1];

    final hopSelectorHorizontal = SingleChildScrollView(
      key: const PageStorageKey('bottom_hop_selector_horizontal'),
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: widget.deepStats.map((item) {
          final hopNum = item['hop'] as int;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ToggleButton(
              checked: hopNum == safeSelectedHop,
              onChanged: (_) => setHop(hopNum),
              child: Text('$hopNum'),
            ),
          );
        }).toList(),
      ),
    );

    final hopSelectorVertical = ListView.builder(
      key: const PageStorageKey('bottom_hop_selector_vertical'),
      controller: _hopScrollController,
      primary: false,
      itemCount: widget.deepStats.length,
      itemBuilder: (context, i) {
        final hopNum = widget.deepStats[i]['hop'] as int;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ToggleButton(
            checked: hopNum == safeSelectedHop,
            onChanged: (_) => setHop(hopNum),
            child: Center(child: Text('$hopNum')),
          ),
        );
      },
    );

    final String jitterVal = (selectedDeep['jitter'] as List).isNotEmpty ? '${selectedDeep['jitter'].last['value']}ms' : '-';
    final String latencyVal = (selectedDeep['pings'] as List).isNotEmpty && selectedDeep['pings'].last['value'] != -1 ? '${selectedDeep['pings'].last['value']}ms' : '-';
    final String minVal = selectedStat['min'] != -1 ? '${selectedStat['min']}ms' : '-';
    final String maxVal = selectedStat['max'] != -1 ? '${selectedStat['max']}ms' : '-';
    final String plVal = (selectedDeep['pl'] as List).isNotEmpty ? '${selectedDeep['pl'].last['value']}%' : '0%';
    final String avgVal = selectedStat['avg'] != -1 ? '${selectedStat['avg']}ms' : '-';

    final statTable = StatTable(colors: colors, type: type, rows: [
      ('Jitter', jitterVal),
      ('Latency', latencyVal),
      ('Minimum', minVal),
      ('IP Address', '${selectedStat['ip']}'),
      ('Maximum', maxVal),
      ('Packet Loss', plVal),
      ('Domain Name', '${selectedStat['name']}'),
      ('Average Latency', avgVal),
      ('Packets Sent / Received', '${selectedStat['sentPackets']}/${selectedStat['receivedPackets']}'),
      ('Total Packets', '${widget.totalPackets}'),
    ]);

    final graph = widget.deepStats.isNotEmpty
        ? Graph(
            data: selectedDeep,
            dataType: dataType,
            interval: widget.interval,
            isRunning: widget.isRunning,
            onSelectMetric: setGraphType,
          )
        : const SizedBox.shrink();

    final actions = Column(
      children: [
        FilledButton(
          onPressed: () => widget.toggleStatistics(),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('View All Hops', textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 12),
        GraphTypeColumn(dataType: dataType, onSelect: setGraphType),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top View Mode Selector Bar
        Row(
          children: [
            _BottomTabPill(
              icon: FluentIcons.table,
              label: 'Hop Inspector',
              isSelected: _viewMode == 0,
              onTap: () => setViewMode(0),
              colors: colors,
              type: type,
            ),
            const SizedBox(width: 6),
            _BottomTabPill(
              icon: FluentIcons.timeline_progress,
              label: 'Timeframe Timeline',
              isSelected: _viewMode == 1,
              onTap: () => setViewMode(1),
              colors: colors,
              type: type,
            ),
            const SizedBox(width: 6),
            _BottomTabPill(
              icon: FluentIcons.incident_triangle,
              label: 'Incident Log (${widget.events.length})',
              isSelected: _viewMode == 2,
              onTap: () => setViewMode(2),
              colors: colors,
              type: type,
            ),
            const Spacer(),
            if (_viewMode == 1 || _viewMode == 2)
              Text(
                'Selected: Hop $safeSelectedHop (${selectedStat['ip'] ?? 'Target'})',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Main View Body
        Expanded(
          child: _viewMode == 1
              ? TimelineChart(
                  deepStats: widget.deepStats,
                  events: widget.events,
                  selectedHop: safeSelectedHop,
                  interval: widget.interval,
                  isRunning: widget.isRunning,
                  timelineHistory: widget.timelineHistory,
                )
              : _viewMode == 2
                  ? _buildIncidentLogView(colors, type)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 800;

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 50,
                                child: hopSelectorVertical,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 4,
                                child: SingleChildScrollView(
                                  key: const PageStorageKey('bottom_stat_table_scroll_wide'),
                                  controller: _statScrollController,
                                  child: statTable,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 5,
                                child: graph,
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 120,
                                child: SingleChildScrollView(
                                  key: const PageStorageKey('bottom_actions_scroll_wide'),
                                  controller: _actionsScrollController,
                                  child: actions,
                                ),
                              ),
                            ],
                          );
                        }

                        // Compact / Split / Tablet Layout
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 32,
                              child: hopSelectorHorizontal,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: SingleChildScrollView(
                                      key: const PageStorageKey('bottom_stat_table_scroll_compact'),
                                      controller: _statScrollController,
                                      child: statTable,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 6,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: graph),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            _GraphPill(label: 'Loss', value: 'pl', current: dataType, onSelect: setGraphType, colors: colors, type: type),
                                            _GraphPill(label: 'Latency', value: 'lt', current: dataType, onSelect: setGraphType, colors: colors, type: type),
                                            _GraphPill(label: 'Jitter', value: 'jt', current: dataType, onSelect: setGraphType, colors: colors, type: type),
                                            _GraphPill(label: 'Avg', value: 'alt', current: dataType, onSelect: setGraphType, colors: colors, type: type),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildIncidentLogView(AppColors colors, AppTypography type) {
    if (widget.events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.completed_solid, size: 24, color: Colors.green),
            const SizedBox(height: 8),
            Text(
              'No network incidents or packet loss events recorded in this session',
              style: type.bodyStrong.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Packet loss dropouts and latency surges will be logged automatically here with timestamps.',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.panelBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderColor),
      ),
      child: ListView.separated(
        key: const PageStorageKey('bottom_incident_log_list'),
        controller: _incidentScrollController,
        itemCount: widget.events.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final evt = widget.events[index];
          final isLoss = evt.type == TimelineEventType.packetLoss;
          final isSpike = evt.type == TimelineEventType.latencySpike;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      Row(
                        children: [
                          Text(
                            evt.title,
                            style: type.bodyStrong.copyWith(
                              color: isLoss ? Colors.red : colors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.panelBackgroundAlt,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Hop ${evt.hop}',
                              style: type.caption.copyWith(fontSize: 10, color: colors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        evt.description,
                        style: type.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  evt.timeFormatted,
                  style: type.caption.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BottomTabPill extends StatelessWidget {
  const _BottomTabPill({
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? colors.accent.withValues(alpha: 0.18) : colors.panelBackgroundAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderColor,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isSelected ? colors.accent : colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: type.caption.copyWith(
                color: isSelected ? colors.accent : colors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphPill extends StatelessWidget {
  const _GraphPill({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelect,
    required this.colors,
    required this.type,
  });

  final String label;
  final String value;
  final String current;
  final void Function(String) onSelect;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    final isSelected = current == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? colors.accent.withValues(alpha: 0.2) : colors.panelBackground,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderColor,
            width: isSelected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: type.caption.copyWith(
            color: isSelected ? colors.accent : colors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

