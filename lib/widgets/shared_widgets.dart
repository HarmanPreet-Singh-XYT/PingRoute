import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

/// [IconButton] padded to at least a 44x44 hit area regardless of icon size,
/// meeting the Apple/Material minimum touch target. Fluent's default icon
/// button padding (8px/side) leaves small mobile icons (16-18px) well under
/// that, so this pads based on the actual icon size instead. Use for
/// icon-only buttons on mobile/touch layouts.
class TouchIconButton extends StatelessWidget {
  const TouchIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.iconSize = 18,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final double iconSize;

  static const double _minTapExtent = 44;

  @override
  Widget build(BuildContext context) {
    final padding = ((_minTapExtent - iconSize) / 2).clamp(
      0.0,
      double.infinity,
    );
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.all(padding)),
      ),
    );
  }
}

/// A single glanceable stat card: icon + label + value with desktop hover effects
/// and 1-click clipboard copy.
class StatTile extends StatefulWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    required this.type,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final AppColors colors;
  final AppTypography type;

  @override
  State<StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<StatTile> {
  bool _isHovered = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.value));
    if (mounted) {
      displayInfoBar(
        context,
        duration: const Duration(seconds: 1),
        builder: (context, close) => InfoBar(
          title: Text('${widget.label} Copied'),
          content: Text('"${widget.value}" copied to clipboard.'),
          severity: InfoBarSeverity.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _copyToClipboard,
        child: Tooltip(
          message: 'Click to copy ${widget.label}',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.colors.panelBackgroundAlt
                  : widget.colors.panelBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isHovered
                    ? widget.colors.accent
                    : widget.colors.borderColor,
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.colors.accent.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: _isHovered
                      ? widget.colors.accent
                      : widget.colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: widget.type.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.value,
                        style: widget.type.title.copyWith(
                          color: widget.valueColor ?? widget.colors.textPrimary,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// (icon, label, value, valueColor) tuples summarizing a hop-stats list:
/// hop count, worst-case max latency, overall average, cumulative jitter of
/// the last hop, and aggregate packet loss.
List<(IconData, String, String, Color?)> statTileData(
  List<Map<String, dynamic>> ipStats,
  List<Map<String, dynamic>> deepStats,
  AppColors colors,
) {
  if (ipStats.isEmpty) return const [];

  final validHops = ipStats.where((s) {
    if (s['ip']?.toString().isEmpty ?? true) return false;
    if (s['receivedPackets'] == 0 && s['sentPackets'] > 0) return false;
    return true;
  }).toList();

  final maxLatency = validHops.isEmpty
      ? 0
      : validHops
            .map((s) => s['max'] as int)
            .where((v) => v != -1)
            .fold<int>(0, (a, b) => b > a ? b : a);
  final avgLatencies = validHops
      .map((s) => s['avg'])
      .whereType<num>()
      .where((v) => v != -1)
      .toList();
  final avgLatency = avgLatencies.isEmpty
      ? 0
      : (avgLatencies.reduce((a, b) => a + b) / avgLatencies.length).round();

  final lastJitter =
      deepStats.isNotEmpty && (deepStats.last['jitter'] as List).isNotEmpty
      ? deepStats.last['jitter'].last['value']
      : 0;

  int finalPacketLoss = 0;
  if (ipStats.isNotEmpty) {
    final lastHop = ipStats.last;
    if (lastHop['ip']?.toString().isEmpty ?? true) {
      finalPacketLoss = 100;
    } else if (lastHop['receivedPackets'] == 0 && lastHop['sentPackets'] > 0) {
      finalPacketLoss = 100;
    } else {
      finalPacketLoss = lastHop['pl'] as int;
    }
  }

  return [
    (FluentIcons.list, 'Hops', '${ipStats.length}', null),
    (
      FluentIcons.speed_high,
      'Max latency',
      '${maxLatency}ms',
      latencyColor(colors, maxLatency),
    ),
    (
      FluentIcons.analytics_view,
      'Avg latency',
      '${avgLatency}ms',
      latencyColor(colors, avgLatency),
    ),
    (FluentIcons.activity_feed, 'Jitter (last hop)', '${lastJitter}ms', null),
    (
      FluentIcons.warning,
      'Packet loss (target)',
      '$finalPacketLoss%',
      finalPacketLoss > 0 ? colors.latencyBad : colors.latencyGood,
    ),
  ];
}

/// Key/value row list for a single hop's detail stats with hover copy support.
class StatTable extends StatelessWidget {
  const StatTable({
    super.key,
    required this.colors,
    required this.type,
    required this.rows,
  });
  final AppColors colors;
  final AppTypography type;
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
          for (int i = 0; i < rows.length; i++)
            _StatTableRowItem(
              label: rows[i].$1,
              value: rows[i].$2,
              colors: colors,
              type: type,
              isOdd: i.isOdd,
            ),
        ],
      ),
    );
  }
}

class _StatTableRowItem extends StatefulWidget {
  const _StatTableRowItem({
    required this.label,
    required this.value,
    required this.colors,
    required this.type,
    required this.isOdd,
  });

  final String label;
  final String value;
  final AppColors colors;
  final AppTypography type;
  final bool isOdd;

  @override
  State<_StatTableRowItem> createState() => _StatTableRowItemState();
}

class _StatTableRowItemState extends State<_StatTableRowItem> {
  bool _isHovered = false;

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.value));
    if (mounted) {
      displayInfoBar(
        context,
        duration: const Duration(seconds: 1),
        builder: (context, close) => InfoBar(
          title: Text('${widget.label} Copied'),
          content: Text('"${widget.value}" copied to clipboard.'),
          severity: InfoBarSeverity.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _copy,
        child: Tooltip(
          message: 'Click to copy ${widget.label}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.colors.accent.withValues(alpha: 0.1)
                  : widget.isOdd
                  ? widget.colors.panelBackgroundAlt
                  : widget.colors.panelBackground,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.label, style: widget.type.subtitle),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.value,
                      style: widget.type.bodyStrong,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_isHovered) ...[
                      const SizedBox(width: 6),
                      Icon(
                        FluentIcons.copy,
                        size: 12,
                        color: widget.colors.accent,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical stack of graph-type toggle buttons (Jitter / Latency / Packet
/// Loss / Avg Latency), shared by the bottom panel, statistics overlay, and
/// mobile graph tab.
class GraphTypeColumn extends StatelessWidget {
  const GraphTypeColumn({
    super.key,
    required this.dataType,
    required this.onSelect,
  });
  final String dataType;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('Jitter', 'jt'),
      ('Latency', 'lt'),
      ('Packet Loss', 'pl'),
      ('Avg Latency', 'alt'),
    ];
    return Column(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              width: double.infinity,
              child: ToggleButton(
                checked: dataType == option.$2,
                onChanged: (_) => onSelect(option.$2),
                child: Text(option.$1, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }
}

/// Horizontal row of rounded graph-type pills (Packet Loss / Latency /
/// Jitter / Avg Latency), used above a standalone chart where a vertical
/// column of full ToggleButtons would take too much width.
class GraphTypePills extends StatelessWidget {
  const GraphTypePills({
    super.key,
    required this.dataType,
    required this.onSelect,
    required this.colors,
    required this.type,
  });
  final String dataType;
  final void Function(String) onSelect;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('Packet Loss', 'pl'),
      ('Latency', 'lt'),
      ('Jitter', 'jt'),
      ('Avg Latency', 'alt'),
    ];
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final option in options)
          _GraphPill(
            label: option.$1,
            value: option.$2,
            current: dataType,
            onSelect: onSelect,
            colors: colors,
            type: type,
          ),
      ],
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
          color: isSelected
              ? colors.accent.withValues(alpha: 0.18)
              : colors.panelBackgroundAlt,
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
