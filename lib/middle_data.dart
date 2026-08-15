import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:PingRoute/graph.dart';
import 'theme.dart';
import 'shared_widgets.dart';
import 'target_directory.dart';

class _Column {
  final String label;
  final int flex;
  final String Function(Map<String, dynamic> hop, Map<String, dynamic> stat) valueOf;
  const _Column(this.label, this.flex, this.valueOf);
}

String _formatPing(dynamic val) {
  if (val == -1 || val == '-1' || val == null) return '-';
  return '${val}ms';
}

String _formatName(dynamic name) {
  return name?.toString().isEmpty ?? true ? '-' : name.toString();
}

bool _isUnresponding(Map<String, dynamic> hop, Map<String, dynamic> stat) {
  if (hop['ip']?.toString().isEmpty ?? true) return true;
  if (stat['receivedPackets'] == 0 && stat['sentPackets'] > 0) return true;
  return false;
}

final List<_Column> _fullColumns = [
  _Column('Hop', 4, (hop, stat) => '${hop['hop']}'),
  _Column('IP', 10, (hop, stat) => hop['ip']?.toString().isEmpty ?? true ? '-' : '${hop['ip']}'),
  _Column('Name', 12, (hop, stat) => _formatName(hop['name'])),
  _Column('Min', 4, (hop, stat) => _formatPing(stat['min'])),
  _Column('Max', 4, (hop, stat) => _formatPing(stat['max'])),
  _Column('Avg', 4, (hop, stat) => _formatPing(stat['avg'])),
  _Column('Last', 4, (hop, stat) => _formatPing(stat['last'])),
  _Column('PL%', 4, (hop, stat) => _isUnresponding(hop, stat) ? '-' : '${stat['pl']}%'),
];

// Narrower set for small screens
final List<_Column> _compactColumns = [
  _Column('Hop', 3, (hop, stat) => '${hop['hop']}'),
  _Column('IP / Name', 10, (hop, stat) {
    final ipStr = hop['ip']?.toString().isEmpty ?? true ? '-' : hop['ip'].toString();
    final nameStr = _formatName(hop['name']);
    if (ipStr == '-') return '-';
    return '$ipStr\n$nameStr';
  }),
  _Column('Last', 4, (hop, stat) => _formatPing(stat['last'])),
  _Column('PL%', 3, (hop, stat) => _isUnresponding(hop, stat) ? '-' : '${stat['pl']}%'),
];

int _compareIps(String? ipA, String? ipB) {
  final cleanA = (ipA ?? '').trim();
  final cleanB = (ipB ?? '').trim();
  if ((cleanA.isEmpty || cleanA == '-') && (cleanB.isEmpty || cleanB == '-')) return 0;
  if (cleanA.isEmpty || cleanA == '-') return 1;
  if (cleanB.isEmpty || cleanB == '-') return -1;

  final partsA = cleanA.split('.').map((p) => int.tryParse(p)).toList();
  final partsB = cleanB.split('.').map((p) => int.tryParse(p)).toList();
  if (partsA.length == 4 && partsB.length == 4 && !partsA.contains(null) && !partsB.contains(null)) {
    for (int i = 0; i < 4; i++) {
      final cmp = partsA[i]!.compareTo(partsB[i]!);
      if (cmp != 0) return cmp;
    }
    return 0;
  }
  return cleanA.compareTo(cleanB);
}

num? _extractNum(dynamic val) {
  if (val == null || val == -1 || val == '-1' || val == '-') return null;
  if (val is num) return val;
  if (val is String) {
    final cleaned = val.replaceAll('ms', '').replaceAll('%', '').trim();
    return num.tryParse(cleaned);
  }
  return null;
}

int _compareNumeric(dynamic valA, dynamic valB) {
  final numA = _extractNum(valA);
  final numB = _extractNum(valB);
  if (numA == null && numB == null) return 0;
  if (numA == null) return 1;
  if (numB == null) return -1;
  return numA.compareTo(numB);
}

class LeftData extends StatefulWidget {
  const LeftData({
    super.key,
    required this.data,
    required this.isLoading,
    required this.IPStats,
    required this.deepStats,
    required this.interval,
    required this.isRunning,
    required this.isSuccess,
    this.onOpenInNewTab,
  });

  final List<Map<String, dynamic>>? data;
  final bool isLoading;
  final List<Map<String, dynamic>> IPStats;
  final List<Map<String, dynamic>> deepStats;
  final int interval;
  final bool isRunning;
  final bool isSuccess;
  final ValueChanged<String>? onOpenInNewTab;

  @override
  State<LeftData> createState() => _LeftDataState();
}

class _LeftDataState extends State<LeftData> {
  String dataType = 'lt';
  String? _sortColumn;
  bool _sortAscending = true;
  String _filterQuery = '';
  bool _isSearchOpen = false;
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void setGraphType(String type) {
    setState(() {
      dataType = type;
    });
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        if (_sortAscending) {
          _sortAscending = false;
        } else {
          _sortColumn = null;
          _sortAscending = true;
        }
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  List<int> _getDisplayIndices() {
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

    if (_sortColumn != null) {
      indices.sort((iA, iB) {
        final hopA = widget.data![iA];
        final statA = iA < widget.IPStats.length ? widget.IPStats[iA] : <String, dynamic>{};
        final hopB = widget.data![iB];
        final statB = iB < widget.IPStats.length ? widget.IPStats[iB] : <String, dynamic>{};

        int cmp = 0;
        switch (_sortColumn) {
          case 'Hop':
            final hA = hopA['hop'] is int ? hopA['hop'] as int : int.tryParse('${hopA['hop']}') ?? 0;
            final hB = hopB['hop'] is int ? hopB['hop'] as int : int.tryParse('${hopB['hop']}') ?? 0;
            cmp = hA.compareTo(hB);
            break;
          case 'IP':
          case 'IP / Name':
            cmp = _compareIps(hopA['ip']?.toString(), hopB['ip']?.toString());
            if (cmp == 0 && _sortColumn == 'IP / Name') {
              final nA = hopA['name']?.toString() ?? '';
              final nB = hopB['name']?.toString() ?? '';
              cmp = nA.toLowerCase().compareTo(nB.toLowerCase());
            }
            break;
          case 'Name':
            final nA = hopA['name']?.toString() ?? '';
            final nB = hopB['name']?.toString() ?? '';
            if (nA.isEmpty && nB.isEmpty) cmp = 0;
            else if (nA.isEmpty) cmp = 1;
            else if (nB.isEmpty) cmp = -1;
            else cmp = nA.toLowerCase().compareTo(nB.toLowerCase());
            break;
          case 'Min':
            cmp = _compareNumeric(statA['min'], statB['min']);
            break;
          case 'Max':
            cmp = _compareNumeric(statA['max'], statB['max']);
            break;
          case 'Avg':
            cmp = _compareNumeric(statA['avg'], statB['avg']);
            break;
          case 'Last':
            cmp = _compareNumeric(statA['last'], statB['last']);
            break;
          case 'PL%':
            final plA = _extractNum(statA['pl']) ?? -1;
            final plB = _extractNum(statB['pl']) ?? -1;
            cmp = plA.compareTo(plB);
            break;
          default:
            cmp = iA.compareTo(iB);
        }
        return _sortAscending ? cmp : -cmp;
      });
    }

    return indices;
  }

  Widget _buildTablePanel(
    BuildContext context,
    AppColors colors,
    AppTypography type,
    List<_Column> columns,
    double? height,
  ) {
    final displayIndices = _getDisplayIndices();

    return Container(
      clipBehavior: Clip.hardEdge,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 1, color: colors.borderColor),
        color: colors.panelBackground,
      ),
      child: Column(
        children: [
          _HeaderRow(
            colors: colors,
            type: type,
            columns: columns,
            sortColumn: _sortColumn,
            sortAscending: _sortAscending,
            onSort: _onSort,
            onSortAscending: (col) => setState(() {
              _sortColumn = col;
              _sortAscending = true;
            }),
            onSortDescending: (col) => setState(() {
              _sortColumn = col;
              _sortAscending = false;
            }),
            onResetSort: () => setState(() => _sortColumn = null),
            isSearchOpen: _isSearchOpen,
            onOpenSearch: () => setState(() => _isSearchOpen = true),
            onCloseSearch: () {
              setState(() {
                _isSearchOpen = false;
                _filterController.clear();
                _filterQuery = '';
              });
            },
            filterController: _filterController,
            onFilterChanged: (text) => setState(() => _filterQuery = text),
            onClearFilter: () {
              _filterController.clear();
              setState(() => _filterQuery = '');
            },
            hasFilter: _filterQuery.isNotEmpty,
          ),
          widget.isLoading
              ? const Expanded(child: Center(child: ProgressRing()))
              : widget.isSuccess
                  ? Expanded(
                      child: displayIndices.isEmpty
                          ? Center(
                              child: Text(
                                'No hops match "$_filterQuery"',
                                style: type.caption.copyWith(color: colors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              itemCount: displayIndices.length,
                              shrinkWrap: height == null,
                              physics: height == null ? const NeverScrollableScrollPhysics() : null,
                              itemBuilder: (context, index) {
                                final originalIndex = displayIndices[index];
                                final hop = widget.data![originalIndex];
                                final stat = widget.IPStats[originalIndex];
                                return _DataRow(
                                  hop: hop,
                                  stat: stat,
                                  colors: colors,
                                  index: index,
                                  columns: columns,
                                  onOpenInNewTab: widget.onOpenInNewTab,
                                );
                              },
                            ),
                    )
                  : const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  Widget _buildGraphPanel(
    BuildContext context,
    AppColors colors,
    AppTypography type,
  ) {
    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(width: 1, color: colors.borderColor),
        color: colors.panelBackground,
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 6,
            runSpacing: 4,
            children: [
              _GraphPill(label: 'Packet Loss', value: 'pl', current: dataType, onSelect: setGraphType, colors: colors, type: type),
              _GraphPill(label: 'Latency', value: 'lt', current: dataType, onSelect: setGraphType, colors: colors, type: type),
              _GraphPill(label: 'Jitter', value: 'jt', current: dataType, onSelect: setGraphType, colors: colors, type: type),
              _GraphPill(label: 'Avg Latency', value: 'alt', current: dataType, onSelect: setGraphType, colors: colors, type: type),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.deepStats.isNotEmpty
                ? Graph(
                    data: widget.deepStats.last,
                    dataType: dataType,
                    interval: widget.interval,
                    isRunning: widget.isRunning,
                  )
                : Center(
                    child: widget.isLoading ? const ProgressRing() : Text('No data available', style: type.subtitle),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final columns = constraints.maxWidth < 600 ? _compactColumns : _fullColumns;
        final showStatTiles = widget.isSuccess && !widget.isLoading;

        if (isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showStatTiles) ...[
                _StatTileRow(ipStats: widget.IPStats, deepStats: widget.deepStats, colors: colors, type: type),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 6, child: _buildTablePanel(context, colors, type, columns, double.infinity)),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: _buildGraphPanel(context, colors, type)),
                  ],
                ),
              ),
            ],
          );
        }

        // Compact / Split Mode: Full width table without squeeze
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showStatTiles) ...[
              _StatTileRow(ipStats: widget.IPStats, deepStats: widget.deepStats, colors: colors, type: type),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _buildTablePanel(context, colors, type, columns, double.infinity),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? colors.accent.withValues(alpha: 0.18) : colors.panelBackgroundAlt,
          borderRadius: BorderRadius.circular(6),
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

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.colors,
    required this.type,
    required this.columns,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.onSortAscending,
    this.onSortDescending,
    this.onResetSort,
    required this.isSearchOpen,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.filterController,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.hasFilter,
  });

  final AppColors colors;
  final AppTypography type;
  final List<_Column> columns;
  final String? sortColumn;
  final bool sortAscending;
  final void Function(String column)? onSort;
  final void Function(String column)? onSortAscending;
  final void Function(String column)? onSortDescending;
  final VoidCallback? onResetSort;
  final bool isSearchOpen;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final TextEditingController filterController;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        border: Border(bottom: BorderSide(color: colors.borderColor)),
      ),
      child: isSearchOpen
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(FluentIcons.search, size: 12, color: colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextBox(
                      autofocus: true,
                      placeholder: 'Filter hops by IP, hostname, or hop #...',
                      controller: filterController,
                      style: type.caption.copyWith(fontSize: 12),
                      onChanged: onFilterChanged,
                      suffix: filterController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(FluentIcons.clear, size: 9),
                              onPressed: onClearFilter,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Close search',
                    child: IconButton(
                      icon: Icon(
                        FluentIcons.chrome_close,
                        size: 11,
                        color: colors.textSecondary,
                      ),
                      onPressed: onCloseSearch,
                    ),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                for (final col in columns)
                  Flexible(
                    flex: col.flex,
                    child: _HeaderCell(
                      column: col,
                      colors: colors,
                      type: type,
                      isSorted: sortColumn == col.label,
                      sortAscending: sortAscending,
                      onTap: onSort != null ? () => onSort!(col.label) : null,
                      onSortAscending: onSortAscending != null
                          ? () => onSortAscending!(col.label)
                          : null,
                      onSortDescending: onSortDescending != null
                          ? () => onSortDescending!(col.label)
                          : null,
                      onResetSort: onResetSort,
                      onOpenSearch: onOpenSearch,
                      onClearFilter: onClearFilter,
                      hasFilter: hasFilter,
                      hasSort: sortColumn != null,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _HeaderCell extends StatefulWidget {
  const _HeaderCell({
    required this.column,
    required this.colors,
    required this.type,
    required this.isSorted,
    required this.sortAscending,
    this.onTap,
    this.onSortAscending,
    this.onSortDescending,
    this.onResetSort,
    this.onOpenSearch,
    this.onClearFilter,
    this.hasFilter = false,
    this.hasSort = false,
  });

  final _Column column;
  final AppColors colors;
  final AppTypography type;
  final bool isSorted;
  final bool sortAscending;
  final VoidCallback? onTap;
  final VoidCallback? onSortAscending;
  final VoidCallback? onSortDescending;
  final VoidCallback? onResetSort;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onClearFilter;
  final bool hasFilter;
  final bool hasSort;

  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  final FlyoutController _flyoutController = FlyoutController();
  bool _isHovered = false;

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortDirectionTooltip = widget.isSorted
        ? (widget.sortAscending
            ? ' (Ascending - click for Descending, right-click for options)'
            : ' (Descending - click to reset, right-click for options)')
        : ' (Click to sort, right-click for options)';

    return FlyoutTarget(
      controller: _flyoutController,
      child: Tooltip(
        message: 'Sort by ${widget.column.label}$sortDirectionTooltip',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTapDown: (details) {
              _flyoutController.showFlyout(
                barrierColor: Colors.transparent,
                autoModeConfiguration: FlyoutAutoConfiguration(
                  preferredMode: FlyoutPlacementMode.bottomCenter,
                ),
                builder: (context) {
                  return MenuFlyout(
                    items: [
                      MenuFlyoutItem(
                        leading: const Icon(FluentIcons.search, size: 14),
                        text: const Text('Search / Filter Hops...'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenSearch?.call();
                        },
                      ),
                      const MenuFlyoutSeparator(),
                      MenuFlyoutItem(
                        leading: const Icon(FluentIcons.chevron_up, size: 14),
                        text: Text('Sort "${widget.column.label}" Ascending'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onSortAscending?.call();
                        },
                      ),
                      MenuFlyoutItem(
                        leading: const Icon(FluentIcons.chevron_down, size: 14),
                        text: Text('Sort "${widget.column.label}" Descending'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onSortDescending?.call();
                        },
                      ),
                      if (widget.hasSort)
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.refresh, size: 14),
                          text: const Text('Reset Column Sorting'),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onResetSort?.call();
                          },
                        ),
                      if (widget.hasFilter)
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.clear, size: 14),
                          text: const Text('Clear Search Filter'),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onClearFilter?.call();
                          },
                        ),
                    ],
                  );
                },
              );
            },
            child: Container(
              constraints: const BoxConstraints(minWidth: 40),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.isSorted
                    ? widget.colors.accent.withValues(alpha: 0.12)
                    : (_isHovered
                        ? widget.colors.panelBackground
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.column.label,
                      style: widget.type.subtitle.copyWith(
                        color: widget.isSorted
                            ? widget.colors.accent
                            : (_isHovered
                                ? widget.colors.textPrimary
                                : widget.colors.textSecondary),
                        fontWeight:
                            widget.isSorted ? FontWeight.bold : FontWeight.w600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isSorted) ...[
                    const SizedBox(width: 3),
                    Icon(
                      widget.sortAscending
                          ? FluentIcons.chevron_up
                          : FluentIcons.chevron_down,
                      size: 9,
                      color: widget.colors.accent,
                    ),
                  ] else if (_isHovered) ...[
                    const SizedBox(width: 3),
                    Icon(
                      FluentIcons.sort,
                      size: 9,
                      color: widget.colors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({
    required this.hop,
    required this.stat,
    required this.colors,
    required this.index,
    required this.columns,
    this.onOpenInNewTab,
  });

  final Map<String, dynamic> hop;
  final Map<String, dynamic> stat;
  final AppColors colors;
  final int index;
  final List<_Column> columns;
  final ValueChanged<String>? onOpenInNewTab;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  final FlyoutController _flyoutController = FlyoutController();
  bool _isHovered = false;

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  void _copyIP() {
    final ip = widget.hop['ip']?.toString() ?? '';
    if (ip.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: ip));
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('IP Copied'),
          content: Text('"$ip" copied to clipboard.'),
          severity: InfoBarSeverity.success,
        ),
      );
    }
  }

  void _copyDomain() {
    final domain = widget.hop['name']?.toString() ?? '';
    if (domain.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: domain));
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Domain Copied'),
          content: Text('"$domain" copied to clipboard.'),
          severity: InfoBarSeverity.success,
        ),
      );
    }
  }

  void _bookmarkHop() {
    final ip = widget.hop['ip']?.toString() ?? '';
    final name = widget.hop['name']?.toString() ?? '';
    if (ip.isNotEmpty) {
      TargetDirectory.instance.saveTarget(
        ip,
        name: name.isNotEmpty ? name : 'Hop ${widget.hop['hop']}',
        note: 'Intermediate hop #${widget.hop['hop']}',
      );
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Bookmarked'),
          content: Text('$ip saved to your IP Directory.'),
          severity: InfoBarSeverity.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawIp = widget.hop['ip']?.toString() ?? '';
    final hasIp = rawIp.isNotEmpty;
    final hopNum = widget.hop['hop'];

    return FlyoutTarget(
      controller: _flyoutController,
      child: MouseRegion(
        cursor: hasIp ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: hasIp ? _copyIP : null,
          onSecondaryTapDown: (details) {
            if (hasIp) {
              _flyoutController.showFlyout(
                barrierColor: Colors.transparent,
                autoModeConfiguration: FlyoutAutoConfiguration(
                  preferredMode: FlyoutPlacementMode.bottomCenter,
                ),
                builder: (context) {
                  return MenuFlyout(
                    items: [
                      MenuFlyoutItem(
                        leading: const Icon(FluentIcons.copy, size: 14),
                        text: Text('Copy IP ($rawIp)'),
                        onPressed: () {
                          _copyIP();
                          Navigator.of(context).pop();
                        },
                      ),
                      if ((widget.hop['name']?.toString() ?? '').isNotEmpty)
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.tag, size: 14),
                          text: Text('Copy Domain (${widget.hop['name']})'),
                          onPressed: () {
                            _copyDomain();
                            Navigator.of(context).pop();
                          },
                        ),
                      MenuFlyoutItem(
                        leading: const Icon(FluentIcons.favorite_star, size: 14),
                        text: const Text('Bookmark to Directory'),
                        onPressed: () {
                          _bookmarkHop();
                          Navigator.of(context).pop();
                        },
                      ),
                      if (widget.onOpenInNewTab != null)
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.open_in_new_tab, size: 14),
                          text: Text('Ping Hop #$hopNum in New Tab'),
                          onPressed: () {
                            widget.onOpenInNewTab!(rawIp);
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  );
                },
              );
            }
          },
          child: Tooltip(
            message: hasIp ? 'Hop #$hopNum ($rawIp) - Click to copy, right-click for options' : 'Hop #$hopNum (Timed out)',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: _isHovered
                    ? widget.colors.accent.withValues(alpha: 0.12)
                    : widget.index.isOdd
                        ? widget.colors.panelBackgroundAlt
                        : widget.colors.panelBackground,
                border: Border(
                  bottom: BorderSide(
                    color: _isHovered ? widget.colors.accent.withValues(alpha: 0.3) : widget.colors.dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  for (final col in widget.columns)
                    Flexible(
                      flex: col.flex,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 40),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        alignment: Alignment.center,
                        child: Text(
                          col.valueOf(widget.hop, widget.stat),
                          style: TextStyle(
                            color: widget.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: _isHovered && col.label == 'IP' ? FontWeight.w600 : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glanceable summary tiles across all hops, laid out in one row.
class _StatTileRow extends StatelessWidget {
  const _StatTileRow({required this.ipStats, required this.deepStats, required this.colors, required this.type});
  final List<Map<String, dynamic>> ipStats;
  final List<Map<String, dynamic>> deepStats;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    final tiles = statTileData(ipStats, deepStats, colors);
    if (tiles.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (int i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              icon: tiles[i].$1,
              label: tiles[i].$2,
              value: tiles[i].$3,
              valueColor: tiles[i].$4,
              colors: colors,
              type: type,
            ),
          ),
        ],
      ],
    );
  }
}
