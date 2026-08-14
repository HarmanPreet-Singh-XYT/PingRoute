import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/graph.dart';
import 'theme.dart';
import 'shared_widgets.dart';

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

  @override
  State<BottomData> createState() => _BottomDataState();
}

class _BottomDataState extends State<BottomData> {
  String dataType = 'pl';
  int selectedHop = 1;

  void setGraphType(String type) {
    setState(() {
      dataType = type;
    });
  }

  void setHop(int hop) {
    setState(() {
      selectedHop = hop;
    });
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

    final safeSelectedHop = selectedHop.clamp(1, widget.IPStats.isNotEmpty ? widget.IPStats.length : 1);
    final selectedStat = widget.IPStats[safeSelectedHop - 1];
    final selectedDeep = widget.deepStats[safeSelectedHop - 1];

    final hopSelectorHorizontal = SingleChildScrollView(
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
        ? Graph(data: selectedDeep, dataType: dataType, interval: widget.interval, isRunning: widget.isRunning)
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

    return LayoutBuilder(
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
                child: SingleChildScrollView(child: statTable),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: graph,
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: SingleChildScrollView(child: actions),
              ),
            ],
          );
        }

        // Compact / Split / Tablet Layout: no empty spaces, clean responsive layout
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
                    child: SingleChildScrollView(child: statTable),
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
