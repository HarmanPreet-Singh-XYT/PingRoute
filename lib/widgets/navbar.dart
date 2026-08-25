import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../core/breakpoints.dart';
import '../core/shortcuts.dart';
import '../core/theme.dart';
import '../dialogs/network_info_dialog.dart';
import '../dialogs/target_dialog.dart';
import '../models/target_directory.dart';
import 'shared_widgets.dart';

class Navbar extends StatelessWidget {
  const Navbar({
    super.key,
    required this.ipController,
    required this.intervalController,
    required this.execTraceroute,
    required this.isRunning,
    required this.showSettings,
    this.setText,
    this.onExport,
    this.onReset,
    this.onSaveSnapshot,
    this.hasData = false,
    this.forceMobile,
  });

  final TextEditingController ipController;
  final TextEditingController intervalController;
  final Function(String text, String type)? setText;
  final VoidCallback execTraceroute;
  final bool isRunning;
  final VoidCallback showSettings;
  final VoidCallback? onExport;
  final VoidCallback? onReset;
  final VoidCallback? onSaveSnapshot;
  final bool hasData;
  final bool? forceMobile;

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenClass = screenClassForSize(Size(
          constraints.maxWidth,
          MediaQuery.of(context).size.height,
        ));
        final isMobileLayout = forceMobile ?? (screenClass == ScreenClass.mobile);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.panelBackground,
            border: Border.all(color: colors.borderColor),
            borderRadius: isMobileLayout
                ? BorderRadius.zero
                : const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
          ),
          child: isMobileLayout
              ? _MobileNavbar(
                  colors: colors,
                  type: type,
                  ipController: ipController,
                  intervalController: intervalController,
                  setText: setText,
                  execTraceroute: execTraceroute,
                  isRunning: isRunning,
                  showSettings: showSettings,
                  onExport: onExport,
                  onReset: onReset,
                  onSaveSnapshot: onSaveSnapshot,
                  hasData: hasData,
                )
              : _WideNavbar(
                  colors: colors,
                  type: type,
                  ipController: ipController,
                  intervalController: intervalController,
                  setText: setText,
                  execTraceroute: execTraceroute,
                  isRunning: isRunning,
                  showSettings: showSettings,
                  onExport: onExport,
                  onReset: onReset,
                  onSaveSnapshot: onSaveSnapshot,
                  hasData: hasData,
                  wrap: screenClass == ScreenClass.tablet,
                ),
        );
      },
    );
  }
}

class _WideNavbar extends StatelessWidget {
  const _WideNavbar({
    required this.colors,
    required this.type,
    required this.ipController,
    required this.intervalController,
    required this.setText,
    required this.execTraceroute,
    required this.isRunning,
    required this.showSettings,
    required this.wrap,
    this.onExport,
    this.onReset,
    this.onSaveSnapshot,
    this.hasData = false,
  });

  final AppColors colors;
  final AppTypography type;
  final TextEditingController ipController;
  final TextEditingController intervalController;
  final Function(String text, String type)? setText;
  final VoidCallback execTraceroute;
  final bool isRunning;
  final VoidCallback showSettings;
  final bool wrap;
  final VoidCallback? onExport;
  final VoidCallback? onReset;
  final VoidCallback? onSaveSnapshot;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final isResumable = !isRunning && hasData;

    final playButton = Tooltip(
      message: isRunning
          ? 'Pause Probing (${shortcutLabel('R')})'
          : isResumable
          ? 'Resume Probing (${shortcutLabel('R')})'
          : 'Start Traceroute (${shortcutLabel('R')} / Enter)',
      child: IconButton(
        icon: Icon(
          isRunning ? FluentIcons.circle_pause_solid : FluentIcons.play_solid,
          color: isRunning ? colors.latencyWarn : colors.latencyGood,
          size: 38,
        ),
        onPressed: () {
          FocusScope.of(context).unfocus();
          execTraceroute();
        },
      ),
    );

    final resetButton = (onReset != null && isResumable)
        ? Tooltip(
            message: 'Reset Session & Clear Telemetry',
            child: IconButton(
              icon: Icon(
                FluentIcons.refresh,
                color: colors.textSecondary,
                size: 20,
              ),
              onPressed: onReset,
            ),
          )
        : null;

    final targetField = _LabeledField(
      label: 'Target Name / IP',
      typography: type,
      child: TargetInputWithHistory(
        key: ValueKey(ipController),
        controller: ipController,
        typography: type,
        colors: colors,
        onChanged: (text) => setText?.call(text, 'ip'),
        width: 250,
      ),
    );

    final intervalField = _LabeledField(
      label: 'Ping Interval',
      typography: type,
      child: SizedBox(
        width: 110,
        child: TextBox(
          placeholder: 'ms',
          textAlign: TextAlign.center,
          style: type.body,
          controller: intervalController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('ms', style: type.caption),
          ),
          onChanged: (text) => setText?.call(text, 'interval'),
        ),
      ),
    );

    final directoryButton = Tooltip(
      message: 'IP Directory & Saved Targets (${shortcutLabel('D')})',
      child: IconButton(
        icon: Icon(
          FluentIcons.contact_list,
          color: colors.textSecondary,
          size: 22,
        ),
        onPressed: () => showTargetDirectoryDialog(
          context,
          initialTarget: ipController.text,
          onSelectTarget: (target) {
            ipController.text = target;
            setText?.call(target, 'ip');
          },
        ),
      ),
    );

    final infoButton = Tooltip(
      message: 'Network Diagnostics & System Info (${shortcutLabel('I')})',
      child: IconButton(
        icon: Icon(FluentIcons.info, color: colors.textSecondary, size: 21),
        onPressed: () => showNetworkInfoDialog(context),
      ),
    );

    final exportButton = onExport != null
        ? Tooltip(
            message: 'Export & Share Report (MTR / CSV / JSON)',
            child: IconButton(
              icon: Icon(
                FluentIcons.share,
                color: colors.textSecondary,
                size: 20,
              ),
              onPressed: onExport,
            ),
          )
        : null;

    final saveSnapshotButton = onSaveSnapshot != null
        ? Tooltip(
            message: 'Save Snapshot (${shortcutLabel('S', shift: true)})',
            child: IconButton(
              icon: Icon(
                FluentIcons.camera,
                color: colors.textSecondary,
                size: 20,
              ),
              onPressed: onSaveSnapshot,
            ),
          )
        : null;

    final legend = _LatencyLegend(colors: colors, type: type);
    final settingsButton = Tooltip(
      message: 'Settings (${shortcutLabel(',')})',
      child: IconButton(
        icon: Icon(FluentIcons.settings, color: colors.textSecondary, size: 22),
        onPressed: () => showSettings(),
      ),
    );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            playButton,
            if (resetButton != null) resetButton,
            targetField,
            intervalField,
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            legend,
            directoryButton,
            infoButton,
            if (saveSnapshotButton != null) saveSnapshotButton,
            if (exportButton != null) exportButton,
            settingsButton,
          ],
        ),
      ],
    );
  }
}

class _MobileNavbar extends StatelessWidget {
  const _MobileNavbar({
    required this.colors,
    required this.type,
    required this.ipController,
    required this.intervalController,
    required this.setText,
    required this.execTraceroute,
    required this.isRunning,
    required this.showSettings,
    this.onExport,
    this.onReset,
    this.onSaveSnapshot,
    this.hasData = false,
  });

  final AppColors colors;
  final AppTypography type;
  final TextEditingController ipController;
  final TextEditingController intervalController;
  final Function(String text, String type)? setText;
  final VoidCallback execTraceroute;
  final bool isRunning;
  final VoidCallback showSettings;
  final VoidCallback? onExport;
  final VoidCallback? onReset;
  final VoidCallback? onSaveSnapshot;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final isResumable = !isRunning && hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: isRunning
                  ? 'Pause Probing'
                  : isResumable
                  ? 'Resume Probing'
                  : 'Start Traceroute',
              child: TouchIconButton(
                icon: Icon(
                  isRunning
                      ? FluentIcons.circle_pause_solid
                      : FluentIcons.play_solid,
                  color: isRunning ? colors.latencyWarn : colors.latencyGood,
                  size: 34,
                ),
                iconSize: 34,
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  execTraceroute();
                },
              ),
            ),
            if (onReset != null && isResumable) ...[
              const SizedBox(width: 2),
              Tooltip(
                message: 'Reset Session & Telemetry',
                child: TouchIconButton(
                  icon: Icon(
                    FluentIcons.refresh,
                    color: colors.textSecondary,
                    size: 16,
                  ),
                  iconSize: 16,
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    onReset?.call();
                  },
                ),
              ),
            ],
            const SizedBox(width: 4),
            Expanded(
              child: TargetInputWithHistory(
                key: ValueKey(ipController),
                controller: ipController,
                typography: type,
                colors: colors,
                onChanged: (text) => setText?.call(text, 'ip'),
                onSubmitted: (text) => execTraceroute(),
                width: double.infinity,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Interval', style: type.caption),
                const SizedBox(width: 6),
                SizedBox(
                  width: 95,
                  child: TextBox(
                    placeholder: '1000',
                    textAlign: TextAlign.center,
                    style: type.body,
                    controller: intervalController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    suffix: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('ms', style: type.caption.copyWith(fontSize: 10)),
                    ),
                    onChanged: (text) => setText?.call(text, 'interval'),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TouchIconButton(
                  icon: Icon(
                    FluentIcons.contact_list,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    showTargetDirectoryDialog(
                      context,
                      initialTarget: ipController.text,
                      onSelectTarget: (target) {
                        ipController.text = target;
                        setText?.call(target, 'ip');
                      },
                    );
                  },
                ),
                TouchIconButton(
                  icon: Icon(
                    FluentIcons.info,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    showNetworkInfoDialog(context);
                  },
                ),
                if (onSaveSnapshot != null)
                  TouchIconButton(
                    icon: Icon(
                      FluentIcons.camera,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      onSaveSnapshot?.call();
                    },
                  ),
                if (onExport != null)
                  TouchIconButton(
                    icon: Icon(
                      FluentIcons.share,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      onExport?.call();
                    },
                  ),
                TouchIconButton(
                  icon: Icon(
                    FluentIcons.settings,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    showSettings();
                  },
                ),
              ],
            ),
            _LatencyLegend(colors: colors, type: type, compact: true),
          ],
        ),
      ],
    );
  }
}

class TargetInputWithHistory extends StatefulWidget {
  const TargetInputWithHistory({
    super.key,
    required this.controller,
    required this.typography,
    required this.colors,
    required this.onChanged,
    required this.width,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final AppTypography typography;
  final AppColors colors;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final double width;

  @override
  State<TargetInputWithHistory> createState() => _TargetInputWithHistoryState();
}

class _TargetInputWithHistoryState extends State<TargetInputWithHistory> {
  final FlyoutController _flyoutController = FlyoutController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _flyoutController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TargetDirectory.instance,
      builder: (context, _) {
        final currentText = widget.controller.text.trim();
        final isSaved = TargetDirectory.instance.isSaved(currentText);
        final recent = TargetDirectory.instance.recentIps;

        return SizedBox(
          width: widget.width == double.infinity ? null : widget.width,
          child: Row(
            mainAxisSize: widget.width == double.infinity
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              Expanded(
                child: FlyoutTarget(
                  controller: _flyoutController,
                  child: AutoSuggestBox<String>(
                    key: ValueKey(widget.controller),
                    controller: widget.controller,
                    focusNode: _focusNode,
                    placeholder: 'IP or domain',
                    clearButtonEnabled: true,
                    autofocus: false,
                    items: recent.map((ip) {
                      final saved = TargetDirectory.instance.getSavedTarget(ip);
                      return AutoSuggestBoxItem<String>(
                        value: ip,
                        label: ip,
                        child: saved != null
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(ip),
                                  const SizedBox(width: 8),
                                  Text(
                                    saved.name,
                                    style: widget.typography.caption.copyWith(
                                      color: widget.colors.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : Text(ip),
                      );
                    }).toList(),
                    onSelected: (item) {
                      if (item.value != null) {
                        widget.controller.text = item.value!;
                        widget.onChanged(item.value!);
                        widget.onSubmitted?.call(item.value!);
                        _focusNode.unfocus();
                      }
                    },
                    onChanged: (text, reason) {
                      widget.onChanged(text);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Star bookmark button
              Tooltip(
                message: isSaved
                    ? 'Bookmarked in Directory'
                    : 'Bookmark Target',
                child: TouchIconButton(
                  icon: Icon(
                    isSaved
                        ? FluentIcons.favorite_star_fill
                        : FluentIcons.favorite_star,
                    color: isSaved
                        ? Colors.warningPrimaryColor
                        : widget.colors.textSecondary,
                    size: 16,
                  ),
                  onPressed: () {
                    _focusNode.unfocus();
                    TargetDirectory.instance.toggleFavorite(
                      widget.controller.text,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.typography,
    required this.child,
  });
  final String label;
  final AppTypography typography;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: typography.subtitle),
        const SizedBox(width: 12),
        child,
      ],
    );
  }
}

class _LatencyLegend extends StatelessWidget {
  const _LatencyLegend({
    required this.colors,
    required this.type,
    this.compact = false,
  });
  final AppColors colors;
  final AppTypography type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendChip(
            label: compact ? '0-100' : '0-100ms',
            color: colors.latencyGood,
            textStyle: type.caption,
            compact: compact,
          ),
          _LegendChip(
            label: compact ? '100-200' : '100-200ms',
            color: colors.latencyWarn,
            textStyle: type.caption,
            compact: compact,
          ),
          _LegendChip(
            label: compact ? '200+' : '200ms+',
            color: colors.latencyBad,
            textStyle: type.caption,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.textStyle,
    this.compact = false,
  });
  final String label;
  final Color color;
  final TextStyle textStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      width: compact ? 62 : 88,
      height: compact ? 26 : 32,
      alignment: Alignment.center,
      child: Text(
        label,
        style: textStyle.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 10 : null,
        ),
      ),
    );
  }
}
