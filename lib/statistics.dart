import 'package:PingRoute/graph.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'theme.dart';
import 'breakpoints.dart';
import 'shared_widgets.dart';

class Statistics extends StatefulWidget {
  const Statistics({
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
    required this.dataTypes,
    required this.setDataType,
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
  final Function(int index, String type) setDataType;
  final List<Map<String, dynamic>> dataTypes;

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return Center(
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        clipBehavior: Clip.hardEdge,
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: colors.panelBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderColor),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('All hops', style: type.title),
                  IconButton(
                    icon: Icon(FluentIcons.chrome_close, size: 16, color: colors.textSecondary),
                    onPressed: () => widget.toggleStatistics(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: widget.deepStats.asMap().entries.map((entry) {
                    final index = entry.key;
                    final deepStat = entry.value;
                    final ipStat = widget.IPStats[index];

                    final String jitterVal = (deepStat['jitter'] as List).isNotEmpty ? '${deepStat['jitter'].last['value']}ms' : '-';
                    final String latencyVal = (deepStat['pings'] as List).isNotEmpty && deepStat['pings'].last['value'] != -1 ? '${deepStat['pings'].last['value']}ms' : '-';
                    final String minVal = ipStat['min'] != -1 ? '${ipStat['min']}ms' : '-';
                    final String maxVal = ipStat['max'] != -1 ? '${ipStat['max']}ms' : '-';
                    final String plVal = (deepStat['pl'] as List).isNotEmpty ? '${deepStat['pl'].last['value']}%' : '0%';
                    final String avgVal = ipStat['avg'] != -1 ? '${ipStat['avg']}ms' : '-';

                    final statTable = _HopStatTable(
                      colors: colors,
                      type: type,
                      hopNumber: index + 1,
                      rows: [
                        ('Jitter', jitterVal),
                        ('Latency', latencyVal),
                        ('Minimum', minVal),
                        ('IP Address', '${ipStat['ip']}'),
                        ('Maximum', maxVal),
                        ('Packet Loss', plVal),
                        ('Domain Name', '${ipStat['name']}'),
                        ('Average Latency', avgVal),
                        ('Sent / Received', '${ipStat['sentPackets']}/${ipStat['receivedPackets']}'),
                        ('Total Packets', '${widget.totalPackets}'),
                      ],
                    );
                    final graph = widget.deepStats.isNotEmpty
                        ? Graph(
                            data: deepStat,
                            dataType: widget.dataTypes[index]['dataType'],
                            interval: widget.interval,
                            isRunning: widget.isRunning,
                          )
                        : const SizedBox.shrink();
                    final selector = GraphTypeColumn(
                      dataType: widget.dataTypes[index]['dataType'],
                      onSelect: (t) => widget.setDataType(index, t),
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.panelBackgroundAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.borderColor),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (screenClassForWidth(constraints.maxWidth) == ScreenClass.desktop) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: constraints.maxWidth * 0.28, child: statTable),
                                  SizedBox(width: constraints.maxWidth * 0.45, height: 400, child: graph),
                                  SizedBox(width: constraints.maxWidth * 0.12, child: selector),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                statTable,
                                const SizedBox(height: 12),
                                SizedBox(height: 260, child: graph),
                                const SizedBox(height: 12),
                                selector,
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HopStatTable extends StatelessWidget {
  const _HopStatTable({required this.colors, required this.type, required this.hopNumber, required this.rows});
  final AppColors colors;
  final AppTypography type;
  final int hopNumber;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.panelBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
            ),
            child: Text('Hop $hopNumber', style: type.bodyStrong.copyWith(color: colors.accent)),
          ),
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: i.isOdd ? colors.panelBackgroundAlt : colors.panelBackground),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(rows[i].$1, style: type.caption),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      style: type.body,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
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
