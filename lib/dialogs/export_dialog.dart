import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/flow_session.dart';

void showExportDialog(BuildContext context, FlowSession flow) {
  showDialog(
    context: context,
    builder: (context) => _ExportDialogContent(flow: flow),
  );
}

class _ExportDialogContent extends StatefulWidget {
  const _ExportDialogContent({required this.flow});
  final FlowSession flow;

  @override
  State<_ExportDialogContent> createState() => _ExportDialogContentState();
}

class _ExportDialogContentState extends State<_ExportDialogContent> {
  int _selectedTabIndex = 0;

  void _copy(String text, String formatName) {
    Clipboard.setData(ClipboardData(text: text));
    displayInfoBar(
      context,
      duration: const Duration(seconds: 2),
      builder: (context, close) => InfoBar(
        title: Text('$formatName Copied'),
        content: Text('$formatName formatted report has been copied to your clipboard.'),
        severity: InfoBarSeverity.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    final mtrText = widget.flow.generateMtrReport();
    final csvText = widget.flow.generateCsvReport();
    final jsonText = widget.flow.generateJsonReport();

    final currentText = _selectedTabIndex == 0
        ? mtrText
        : _selectedTabIndex == 1
            ? csvText
            : jsonText;

    final formatLabel = _selectedTabIndex == 0
        ? 'MTR Report'
        : _selectedTabIndex == 1
            ? 'CSV'
            : 'JSON';

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(FluentIcons.share, size: 20, color: colors.accent),
              const SizedBox(width: 10),
              Text('Export & Share Report', style: type.title),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FormatTabButton(
                label: 'MTR Text',
                isSelected: _selectedTabIndex == 0,
                onTap: () => setState(() => _selectedTabIndex = 0),
                colors: colors,
                type: type,
              ),
              const SizedBox(width: 6),
              _FormatTabButton(
                label: 'CSV',
                isSelected: _selectedTabIndex == 1,
                onTap: () => setState(() => _selectedTabIndex = 1),
                colors: colors,
                type: type,
              ),
              const SizedBox(width: 6),
              _FormatTabButton(
                label: 'JSON',
                isSelected: _selectedTabIndex == 2,
                onTap: () => setState(() => _selectedTabIndex = 2),
                colors: colors,
                type: type,
              ),
            ],
          ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Target: ', style: type.bodyStrong),
              Text('${widget.flow.ip} (${widget.flow.title})', style: type.body),
              const Spacer(),
              Text('${widget.flow.ipStats.length} hops • ${widget.flow.packetSent} packets', style: type.caption),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderColor),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  currentText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        Button(
          child: const Text('Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          onPressed: () => _copy(currentText, formatLabel),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.copy, size: 14),
              const SizedBox(width: 6),
              Text('Copy $formatLabel'),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormatTabButton extends StatelessWidget {
  const _FormatTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    required this.type,
  });

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
          color: isSelected ? colors.accent.withValues(alpha: 0.15) : colors.panelBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: type.caption.copyWith(
            color: isSelected ? colors.accent : colors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
