import 'package:dart_ping_ios/dart_ping_ios.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:system_theme/system_theme.dart';

import 'core/breakpoints.dart';
import 'core/storage_helper.dart';
import 'core/theme.dart';
import 'dialogs/export_dialog.dart';
import 'dialogs/network_info_dialog.dart';
import 'dialogs/settings.dart';
import 'dialogs/target_dialog.dart';
import 'models/flow_session.dart';
import 'widgets/bottom_data.dart';
import 'widgets/error.dart';
import 'widgets/graph.dart';
import 'widgets/middle_data.dart';
import 'widgets/mobile_shell.dart';
import 'widgets/navbar.dart';
import 'widgets/statistics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPingIOS.register();
  await StorageHelper.initialize();
  runApp(const PingRouteApp());
}

class PingRouteApp extends StatelessWidget {
  const PingRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final systemAccent = SystemTheme.accentColor.accent;
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        return FluentApp(
          title: 'PingRoute',
          debugShowCheckedModeBanner: false,
          theme: buildFluentTheme(Brightness.light, systemAccent),
          darkTheme: buildFluentTheme(Brightness.dark, systemAccent),
          themeMode: AppSettings.instance.themeMode,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(AppSettings.instance.uiScale),
              ),
              child: child!,
            );
          },
          home: const MainApp(),
        );
      },
    );
  }
}

enum ViewMode { tabs, splitTwo, splitGrid }

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with SingleTickerProviderStateMixin {
  final List<FlowSession> _flows = [];
  final List<FlyoutController> _tabFlyoutControllers = [];
  final List<String?> _paneFlowIds = [null, null, null, null];
  int _currentIndex = 0;
  ViewMode _viewMode = ViewMode.tabs;

  // Animation for statistics overlay
  late AnimationController _statisticsController;
  late Animation<Offset> _offsetAnimation;
  bool _isStatisticsVisible = false;

  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _statisticsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _offsetAnimation =
        Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _statisticsController,
            curve: Curves.easeInOut,
          ),
        );

    _addNewFlow(initialIp: '1.1.1.1');
  }

  void _onFlowUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  FlowSession? _getFlowForSlot(int slotIndex) {
    if (slotIndex < _paneFlowIds.length && _paneFlowIds[slotIndex] != null) {
      final id = _paneFlowIds[slotIndex]!;
      if (id == '__empty__') return null;
      final match = _flows.where((f) => f.id == id).firstOrNull;
      if (match != null) return match;
    }
    if (slotIndex < _flows.length) {
      return _flows[slotIndex];
    }
    return null;
  }

  void _addNewFlow({String initialIp = '1.1.1.1', bool autoStart = false}) {
    setState(() {
      final newFlow = FlowSession(initialIp: initialIp);
      newFlow.addListener(_onFlowUpdated);
      _flows.add(newFlow);
      _tabFlyoutControllers.add(FlyoutController());
      _currentIndex = _flows.length - 1;

      if (autoStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          newFlow.execTraceroute(
            onError: () {
              if (mounted) showErrorPopup(context);
            },
          );
        });
      }
    });
  }

  void _closeFlow(int index) {
    if (_flows.length <= 1) return;
    setState(() {
      final removed = _flows.removeAt(index);
      removed.removeListener(_onFlowUpdated);
      removed.dispose();
      _tabFlyoutControllers.removeAt(index);

      for (int i = 0; i < _paneFlowIds.length; i++) {
        if (_paneFlowIds[i] == removed.id) {
          _paneFlowIds[i] = null;
        }
      }

      if (_currentIndex >= _flows.length) {
        _currentIndex = _flows.length - 1;
      }
    });
  }

  void _closeOtherFlows(int keepIndex) {
    if (_flows.length <= 1) return;
    setState(() {
      final keptFlow = _flows[keepIndex];
      final keptFlyout = _tabFlyoutControllers[keepIndex];

      for (int i = 0; i < _flows.length; i++) {
        if (i != keepIndex) {
          _flows[i].removeListener(_onFlowUpdated);
          _flows[i].dispose();
        }
      }

      _flows.clear();
      _tabFlyoutControllers.clear();

      _flows.add(keptFlow);
      _tabFlyoutControllers.add(keptFlyout);
      _currentIndex = 0;

      _paneFlowIds.fillRange(0, _paneFlowIds.length, null);
      _paneFlowIds[0] = keptFlow.id;
    });
  }

  void _toggleStatisticsVisibility() {
    final activeFlow = _flows.isNotEmpty
        ? _flows[_currentIndex.clamp(0, _flows.length - 1)]
        : null;
    if (activeFlow == null) return;

    if (_isStatisticsVisible) {
      _statisticsController.reverse().then((_) {
        setState(() {
          _isStatisticsVisible = false;
        });
        activeFlow.setStatisticsVisible(false);
      });
    } else {
      setState(() {
        _isStatisticsVisible = true;
      });
      activeFlow.setStatisticsVisible(true);
      _statisticsController.forward();
    }
  }

  @override
  void dispose() {
    for (final flow in _flows) {
      flow.removeListener(_onFlowUpdated);
      flow.dispose();
    }
    _keyboardFocusNode.dispose();
    _statisticsController.dispose();
    super.dispose();
  }

  void _openFlowSettings(FlowSession flow) {
    showSettingsPopup(
      context,
      flow.graphInterval,
      flow.packetsLimit,
      flow.changeSettingParams,
      packetSize: flow.packetSize,
      maxHops: flow.maxHops,
      timeoutMs: flow.timeoutMs,
      showMetricCards: flow.showMetricCards,
      showControls: flow.showControls,
      showGraphPills: flow.showGraphPills,
      activeMetric: flow.activeMetric,
      onToggleMetricCards: (val) => flow.toggleMetricCards(val),
      onToggleControls: (val) => flow.toggleControls(val),
      onToggleGraphPills: (val) => flow.toggleGraphPills(val),
      onSelectMetric: (metric) => flow.setActiveMetric(metric),
      onApplyToAllTabs: () {
        for (final other in _flows) {
          other.copySettingsFrom(flow);
        }
        displayInfoBar(
          context,
          builder: (context, close) => const InfoBar(
            title: Text('Settings Applied'),
            content: Text('Layout and telemetry settings synced across all open tabs.'),
            severity: InfoBarSeverity.success,
          ),
        );
      },
    );
  }

  Widget _buildMiniControlsBar(
    FlowSession flow,
    AppColors colors,
    AppTypography type,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.panelBackgroundAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: flow.isRunning
                  ? colors.latencyGood
                  : (flow.dataCollected || flow.ipStats.isNotEmpty
                      ? colors.latencyWarn
                      : colors.textSecondary.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            flow.ip,
            style: type.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.panelBackground,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.borderColor),
            ),
            child: Text(
              '${flow.interval}ms',
              style: type.caption.copyWith(color: colors.textSecondary, fontSize: 11),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: flow.isRunning ? 'Pause Flow' : 'Resume Flow',
            child: IconButton(
              icon: Icon(
                flow.isRunning ? FluentIcons.circle_pause_solid : FluentIcons.play_solid,
                size: 14,
                color: flow.isRunning ? colors.latencyWarn : colors.latencyGood,
              ),
              onPressed: () => flow.execTraceroute(
                onError: () => showErrorPopup(context),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Show Target & Controls Bar',
            child: Button(
              onPressed: () => flow.toggleControls(true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.chevron_down, size: 10, color: colors.accent),
                  const SizedBox(width: 4),
                  Text('Controls', style: type.caption.copyWith(color: colors.accent)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Settings',
            child: IconButton(
              icon: Icon(FluentIcons.settings, size: 14, color: colors.textSecondary),
              onPressed: () => _openFlowSettings(flow),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFlowBody(FlowSession flow, AppColors colors) {
    final type = appTypography(context);
    return Container(
      key: ValueKey(flow.id),
      color: colors.pageBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                flow.showControls
                    ? Navbar(
                        key: ValueKey('navbar_${flow.id}'),
                        ipController: flow.ipController,
                        intervalController: flow.intervalController,
                        execTraceroute: () => flow.execTraceroute(
                          onError: () => showErrorPopup(context),
                        ),
                        onReset: () => flow.reset(),
                        hasData: flow.dataCollected || flow.ipStats.isNotEmpty,
                        isRunning: flow.isRunning,
                        showSettings: () => _openFlowSettings(flow),
                        onExport: () => showExportDialog(context, flow),
                        setText: flow.setText,
                      )
                    : _buildMiniControlsBar(flow, colors, type),
                SizedBox(height: flow.showControls ? 16 : 8),
                Expanded(
                  child: LeftData(
                    data: flow.tracerouteResult,
                    isLoading: flow.isLoading,
                    IPStats: flow.ipStats,
                    deepStats: flow.deepStats,
                    interval: flow.graphInterval,
                    isRunning: flow.isRunning,
                    isSuccess: flow.success,
                    showMetricCards: flow.showMetricCards,
                    showGraphPills: flow.showGraphPills,
                    showControls: flow.showControls,
                    initialMetric: flow.activeMetric,
                    onMetricChanged: flow.setActiveMetric,
                    onToggleMetricCards: flow.toggleMetricCards,
                    onToggleGraphPills: flow.toggleGraphPills,
                    onToggleControls: flow.toggleControls,
                    onReset: flow.reset,
                    onOpenInNewTab: (ip) =>
                        _addNewFlow(initialIp: ip, autoStart: true),
                    onToggleStatistics: _toggleStatisticsVisibility,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            flex: 3,
            child: Container(
              clipBehavior: Clip.hardEdge,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.borderColor),
                color: colors.panelBackground,
              ),
              child: BottomData(
                IPStats: flow.ipStats,
                deepStats: flow.deepStats,
                interval: flow.interval,
                isRunning: flow.isRunning,
                totalPackets: flow.packetSent,
                isLoading: flow.isLoading,
                graphInterval: flow.graphInterval,
                dataCollected: flow.dataCollected,
                success: flow.success,
                events: flow.timelineEvents,
                timelineHistory: flow.timelineHistory,
                toggleStatistics: _toggleStatisticsVisibility,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitCard(
    FlowSession flow,
    int slotIndex,
    AppColors colors,
    AppTypography type,
  ) {
    final flowIndex = _flows.indexOf(flow);
    return Container(
      key: ValueKey('split_slot_${slotIndex}_${flow.id}'),
      decoration: BoxDecoration(
        color: colors.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        children: [
          // Pane Slot Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.panelBackgroundAlt,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              border: Border(bottom: BorderSide(color: colors.borderColor)),
            ),
            child: Row(
              children: [
                DropDownButton(
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: flow.isRunning
                              ? colors.latencyGood
                              : (flow.dataCollected || flow.ipStats.isNotEmpty
                                  ? colors.latencyWarn
                                  : colors.textSecondary.withValues(alpha: 0.5)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Slot ${slotIndex + 1}: Tab ${flowIndex != -1 ? flowIndex + 1 : "?"} (${flow.title.isEmpty ? flow.ip : flow.title})',
                        style: type.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  items: [
                    for (int f = 0; f < _flows.length; f++)
                      MenuFlyoutItem(
                        leading: Icon(
                          _flows[f].id == flow.id
                              ? FluentIcons.check_mark
                              : FluentIcons.tab,
                          size: 12,
                          color: _flows[f].id == flow.id
                              ? colors.accent
                              : colors.textSecondary,
                        ),
                        text: Text(
                          'Tab ${f + 1}: ${_flows[f].title} (${_flows[f].ip})',
                          style: type.body.copyWith(
                            fontWeight: _flows[f].id == flow.id
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            _paneFlowIds[slotIndex] = _flows[f].id;
                          });
                        },
                      ),
                    const MenuFlyoutSeparator(),
                    MenuFlyoutItem(
                      leading:
                          Icon(FluentIcons.add, size: 12, color: colors.accent),
                      text: Text('+ New Tab in this Slot', style: type.body),
                      onPressed: () {
                        _addNewFlow();
                        setState(() {
                          _paneFlowIds[slotIndex] = _flows.last.id;
                        });
                      },
                    ),
                    MenuFlyoutItem(
                      leading: Icon(FluentIcons.clear,
                          size: 12, color: colors.latencyBad),
                      text: Text('Unassign Slot',
                          style: type.body.copyWith(color: colors.latencyBad)),
                      onPressed: () {
                        setState(() {
                          _paneFlowIds[slotIndex] = '__empty__';
                        });
                      },
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: flow.showControls
                      ? 'Hide Target & Controls Bar'
                      : 'Show Target & Controls Bar',
                  child: IconButton(
                    icon: Icon(
                      flow.showControls
                          ? FluentIcons.chevron_up
                          : FluentIcons.chevron_down,
                      size: 11,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => flow.toggleControls(),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Slot Settings & Customization',
                  child: IconButton(
                    icon: Icon(
                      FluentIcons.settings,
                      size: 11,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => _openFlowSettings(flow),
                  ),
                ),
                const SizedBox(width: 6),
                if (flowIndex != -1)
                  Text(
                    '${flowIndex + 1} of ${_flows.length} tabs',
                    style: type.caption.copyWith(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          // Header Bar for Split Pane with editable Target IP & Interval
          if (flow.showControls)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.panelBackgroundAlt,
                border: Border(bottom: BorderSide(color: colors.borderColor)),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: flow.isRunning
                        ? 'Pause Flow'
                        : (flow.dataCollected || flow.ipStats.isNotEmpty)
                        ? 'Resume Flow'
                        : 'Start Flow',
                    child: IconButton(
                      icon: Icon(
                        flow.isRunning
                            ? FluentIcons.circle_pause_solid
                            : FluentIcons.play_solid,
                        size: 26,
                        color: flow.isRunning
                            ? colors.latencyWarn
                            : colors.latencyGood,
                      ),
                      onPressed: () => flow.execTraceroute(
                        onError: () => showErrorPopup(context),
                      ),
                    ),
                  ),
                  if (flow.dataCollected || flow.ipStats.isNotEmpty)
                    Tooltip(
                      message: 'Reset Session & Clear Telemetry',
                      child: IconButton(
                        icon: Icon(
                          FluentIcons.refresh,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        onPressed: () => flow.reset(),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TargetInputWithHistory(
                      key: ValueKey(flow.ipController),
                      controller: flow.ipController,
                      typography: type,
                      colors: colors,
                      onChanged: (text) => flow.setText(text, 'ip'),
                      width: double.infinity,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 80,
                    child: TextBox(
                      placeholder: 'ms',
                      textAlign: TextAlign.center,
                      style: type.body,
                      controller: flow.intervalController,
                      suffix: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text('ms', style: type.caption),
                      ),
                      onChanged: (text) => flow.setText(text, 'interval'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Export Report',
                    child: IconButton(
                      icon: Icon(
                        FluentIcons.share,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      onPressed: () => showExportDialog(context, flow),
                    ),
                  ),
                  Tooltip(
                    message: 'Settings',
                    child: IconButton(
                      icon: Icon(
                        FluentIcons.settings,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      onPressed: () => _openFlowSettings(flow),
                    ),
                  ),
                  if (_flows.length > 1)
                    Tooltip(
                      message: 'Close Flow',
                      child: IconButton(
                        icon: Icon(
                          FluentIcons.chrome_close,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        onPressed: () {
                          final idx = _flows.indexOf(flow);
                          if (idx != -1) _closeFlow(idx);
                        },
                      ),
                    ),
                ],
              ),
            ),
          // Split Pane Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  if (isWide) {
                    return LeftData(
                      data: flow.tracerouteResult,
                      isLoading: flow.isLoading,
                      IPStats: flow.ipStats,
                      deepStats: flow.deepStats,
                      interval: flow.graphInterval,
                      isRunning: flow.isRunning,
                      isSuccess: flow.success,
                      showMetricCards: flow.showMetricCards,
                      showGraphPills: flow.showGraphPills,
                      showControls: flow.showControls,
                      initialMetric: flow.activeMetric,
                      onMetricChanged: flow.setActiveMetric,
                      onToggleMetricCards: flow.toggleMetricCards,
                      onToggleGraphPills: flow.toggleGraphPills,
                      onToggleControls: flow.toggleControls,
                      onReset: flow.reset,
                      onOpenInNewTab: (ip) => _addNewFlow(initialIp: ip),
                      onToggleStatistics: _toggleStatisticsVisibility,
                    );
                  }

                  return Column(
                    children: [
                      // Hop Table
                      Expanded(
                        flex: 5,
                        child: LeftData(
                          data: flow.tracerouteResult,
                          isLoading: flow.isLoading,
                          IPStats: flow.ipStats,
                          deepStats: flow.deepStats,
                          interval: flow.graphInterval,
                          isRunning: flow.isRunning,
                          isSuccess: flow.success,
                          showMetricCards: flow.showMetricCards,
                          showGraphPills: flow.showGraphPills,
                          showControls: flow.showControls,
                          initialMetric: flow.activeMetric,
                          onMetricChanged: flow.setActiveMetric,
                          onToggleMetricCards: flow.toggleMetricCards,
                          onToggleGraphPills: flow.toggleGraphPills,
                          onToggleControls: flow.toggleControls,
                          onReset: flow.reset,
                          onOpenInNewTab: (ip) => _addNewFlow(initialIp: ip),
                          onToggleStatistics: _toggleStatisticsVisibility,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Live Target Latency Graph
                      Expanded(
                        flex: 4,
                        child: Container(
                          clipBehavior: Clip.hardEdge,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.borderColor),
                            color: colors.panelBackground,
                          ),
                          child: flow.deepStats.isNotEmpty
                              ? Graph(
                                  data: flow.deepStats.last,
                                  dataType: flow.activeMetric,
                                  interval: flow.interval,
                                  isRunning: flow.isRunning,
                                  onSelectMetric: flow.setActiveMetric,
                                  onTogglePills: flow.toggleGraphPills,
                                  onToggleCards: flow.toggleMetricCards,
                                  onToggleControls: flow.toggleControls,
                                  onReset: flow.reset,
                                  showPills: flow.showGraphPills,
                                  showCards: flow.showMetricCards,
                                  showControls: flow.showControls,
                                )
                              : Center(
                                  child: flow.isLoading
                                      ? const ProgressRing()
                                      : Text(
                                          'No data available',
                                          style: type.caption,
                                        ),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Stacks [panes] vertically, each getting an equal share of [availableHeight]
  /// as long as that share stays above [minPaneHeight]; otherwise each pane
  /// is pinned to [minPaneHeight] and the stack scrolls instead of squeezing
  /// panes down to an unusable size.
  Widget _verticalPaneStack(
    List<Widget> panes,
    double availableHeight, {
    double minPaneHeight = 520,
    double spacing = 12,
  }) {
    final totalSpacing = spacing * (panes.length - 1);
    final perPaneHeight = (availableHeight - totalSpacing) / panes.length;
    final fits = perPaneHeight >= minPaneHeight;

    final children = <Widget>[
      for (int i = 0; i < panes.length; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        fits
            ? Expanded(child: panes[i])
            : SizedBox(height: minPaneHeight, child: panes[i]),
      ],
    ];

    if (fits) {
      return Column(children: children);
    }
    return SingleChildScrollView(child: Column(children: children));
  }

  Widget _buildEmptySlotCard(
    int slotIndex,
    AppColors colors,
    AppTypography type,
  ) {
    final slot0Index = slotIndex - 1;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor.withValues(alpha: 0.6)),
        color: colors.cardBackground.withValues(alpha: 0.4),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.panelBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.borderColor),
                ),
                child: Icon(
                  FluentIcons.view_all,
                  size: 22,
                  color: colors.accent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Slot $slotIndex (Unassigned)',
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Select any open tab or create a new flow to display here',
                textAlign: TextAlign.center,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_flows.isNotEmpty) ...[
                    DropDownButton(
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.tab, size: 12, color: colors.accent),
                          const SizedBox(width: 6),
                          Text('Select Open Tab', style: type.body),
                        ],
                      ),
                      items: [
                        for (int f = 0; f < _flows.length; f++)
                          MenuFlyoutItem(
                            leading: const Icon(FluentIcons.tab, size: 12),
                            text: Text(
                              'Tab ${f + 1}: ${_flows[f].title} (${_flows[f].ip})',
                            ),
                            onPressed: () {
                              setState(() {
                                _paneFlowIds[slot0Index] = _flows[f].id;
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                  ],
                  Button(
                    onPressed: () {
                      _addNewFlow();
                      setState(() {
                        _paneFlowIds[slot0Index] = _flows.last.id;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.add, size: 12, color: colors.accent),
                        const SizedBox(width: 6),
                        Text('New Flow', style: type.body),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSplitView(AppColors colors, AppTypography type) {
    if (_flows.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Each split card needs real width for its navbar + hop table +
        // graph to stay usable, so only reflow to a vertical stack in the
        // tablet range and below — normal desktop windows keep the grid.
        final isCompact = constraints.maxWidth < kTabletBreakpoint;

        if (_viewMode == ViewMode.splitTwo) {
          final flow0 = _getFlowForSlot(0);
          final flow1 = _getFlowForSlot(1);

          final firstPane = flow0 != null
              ? _buildSplitCard(flow0, 0, colors, type)
              : _buildEmptySlotCard(1, colors, type);
          final secondPane = flow1 != null
              ? _buildSplitCard(flow1, 1, colors, type)
              : _buildEmptySlotCard(2, colors, type);

          if (isCompact) {
            return _verticalPaneStack([
              firstPane,
              secondPane,
            ], constraints.maxHeight);
          }

          return Row(
            children: [
              Expanded(child: firstPane),
              const SizedBox(width: 12),
              Expanded(child: secondPane),
            ],
          );
        } else {
          // 4-Pane Grid
          final flow0 = _getFlowForSlot(0);
          final flow1 = _getFlowForSlot(1);
          final flow2 = _getFlowForSlot(2);
          final flow3 = _getFlowForSlot(3);

          final pane1 = flow0 != null
              ? _buildSplitCard(flow0, 0, colors, type)
              : _buildEmptySlotCard(1, colors, type);
          final pane2 = flow1 != null
              ? _buildSplitCard(flow1, 1, colors, type)
              : _buildEmptySlotCard(2, colors, type);
          final pane3 = flow2 != null
              ? _buildSplitCard(flow2, 2, colors, type)
              : _buildEmptySlotCard(3, colors, type);
          final pane4 = flow3 != null
              ? _buildSplitCard(flow3, 3, colors, type)
              : _buildEmptySlotCard(4, colors, type);

          if (isCompact) {
            return _verticalPaneStack([
              pane1,
              pane2,
              pane3,
              pane4,
            ], constraints.maxHeight);
          }

          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: pane1),
                    const SizedBox(width: 12),
                    Expanded(child: pane2),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: pane3),
                    const SizedBox(width: 12),
                    Expanded(child: pane4),
                  ],
                ),
              ),
            ],
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final activeIndex = _currentIndex.clamp(
      0,
      _flows.isNotEmpty ? _flows.length - 1 : 0,
    );
    final currentFlow = _flows.isNotEmpty ? _flows[activeIndex] : null;

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
          _addNewFlow(initialIp: '8.8.8.8'),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
          _addNewFlow(initialIp: '8.8.8.8'),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
          _closeFlow(_currentIndex),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
          _closeFlow(_currentIndex),
      const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
          currentFlow?.execTraceroute(),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
          currentFlow?.execTraceroute(),
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
        if (currentFlow != null) {
          showTargetDirectoryDialog(
            context,
            initialTarget: currentFlow.ip,
            onSelectTarget: (t) => currentFlow.setText(t, 'ip'),
          );
        }
      },
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
        if (currentFlow != null) {
          showTargetDirectoryDialog(
            context,
            initialTarget: currentFlow.ip,
            onSelectTarget: (t) => currentFlow.setText(t, 'ip'),
          );
        }
      },
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
          showNetworkInfoDialog(context),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
          showNetworkInfoDialog(context),
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
        if (currentFlow != null) {
          _openFlowSettings(currentFlow);
        }
      },
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
        if (currentFlow != null) {
          _openFlowSettings(currentFlow);
        }
      },
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        focusNode: _keyboardFocusNode,
        child: ScaffoldPage(
          padding: EdgeInsets.zero,
          content: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = screenClassForWidth(constraints.maxWidth) ==
                  ScreenClass.mobile;

              final mainContent = isMobile
                  ? MobileShell(
                      flows: _flows,
                      currentFlowIndex: activeIndex,
                      onFlowSelected: (index) =>
                          setState(() => _currentIndex = index),
                      onAddFlow: () => _addNewFlow(initialIp: '8.8.8.8'),
                      onCloseFlow: _closeFlow,
                      showSettings: () {
                        if (currentFlow != null) {
                          _openFlowSettings(currentFlow);
                        }
                      },
                      onExport: (flow) => showExportDialog(context, flow),
                      onReset: () => currentFlow?.reset(),
                      onOpenInNewTab: (ip) =>
                          _addNewFlow(initialIp: ip, autoStart: true),
                      onToggleStatistics: _toggleStatisticsVisibility,
                      onDuplicateFlow: (flow) =>
                          _addNewFlow(initialIp: flow.ip, autoStart: true),
                      onCloseOtherFlows: _closeOtherFlows,
                    )
                  : Column(
                      children: [
                        // Desktop Top Header: Tab / Split Controls
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.pageBackground,
                            border: Border(
                              bottom: BorderSide(color: colors.borderColor),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  _ViewModePill(
                                    label: 'Tabs',
                                    icon: FluentIcons.tab,
                                    isSelected: _viewMode == ViewMode.tabs,
                                    onTap: () =>
                                        setState(() => _viewMode = ViewMode.tabs),
                                    colors: colors,
                                    type: type,
                                  ),
                                  const SizedBox(width: 6),
                                  _ViewModePill(
                                    label: '2-Flow Split',
                                    icon: FluentIcons.column_left_two_thirds,
                                    isSelected: _viewMode == ViewMode.splitTwo,
                                    onTap: () => setState(
                                      () => _viewMode = ViewMode.splitTwo,
                                    ),
                                    colors: colors,
                                    type: type,
                                  ),
                                  const SizedBox(width: 6),
                                  _ViewModePill(
                                    label: '4-Flow Grid',
                                    icon: FluentIcons.grid_view_medium,
                                    isSelected: _viewMode == ViewMode.splitGrid,
                                    onTap: () => setState(
                                      () => _viewMode = ViewMode.splitGrid,
                                    ),
                                    colors: colors,
                                    type: type,
                                  ),
                                ],
                              ),
                              Button(
                                onPressed: () =>
                                    _addNewFlow(initialIp: '8.8.8.8'),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.add, size: 12),
                                    SizedBox(width: 4),
                                    Text('New Flow (⌘T)'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Main Content Area
                        Expanded(
                          child: _viewMode == ViewMode.tabs
                              ? TabView(
                                  currentIndex: activeIndex,
                                  onChanged: (index) =>
                                      setState(() => _currentIndex = index),
                                  onNewPressed: () =>
                                      _addNewFlow(initialIp: '8.8.8.8'),
                                  onReorder: (oldIndex, newIndex) {
                                    setState(() {
                                      if (oldIndex < newIndex) {
                                        newIndex -= 1;
                                      }
                                      final item = _flows.removeAt(oldIndex);
                                      final flyout = _tabFlyoutControllers
                                          .removeAt(oldIndex);
                                      _flows.insert(newIndex, item);
                                      _tabFlyoutControllers.insert(
                                        newIndex,
                                        flyout,
                                      );

                                      if (_currentIndex == oldIndex) {
                                        _currentIndex = newIndex;
                                      } else if (oldIndex < _currentIndex &&
                                          newIndex >= _currentIndex) {
                                        _currentIndex -= 1;
                                      } else if (oldIndex > _currentIndex &&
                                          newIndex <= _currentIndex) {
                                        _currentIndex += 1;
                                      }
                                    });
                                  },
                                  tabs: List.generate(_flows.length, (index) {
                                    final flow = _flows[index];
                                    final tabFlyout =
                                        index < _tabFlyoutControllers.length
                                        ? _tabFlyoutControllers[index]
                                        : FlyoutController();

                                    Widget leadingIcon;
                                    if (flow.isRunning) {
                                      leadingIcon = Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: colors.latencyGood,
                                          shape: BoxShape.circle,
                                        ),
                                      );
                                    } else if (flow.isLoading) {
                                      leadingIcon = const SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: ProgressRing(strokeWidth: 2),
                                      );
                                    } else {
                                      leadingIcon = const Icon(
                                        FluentIcons.network_tower,
                                        size: 14,
                                      );
                                    }

                                    return Tab(
                                      text: FlyoutTarget(
                                        controller: tabFlyout,
                                        child: GestureDetector(
                                          onSecondaryTapDown: (details) {
                                            tabFlyout.showFlyout(
                                              barrierColor: Colors.transparent,
                                              autoModeConfiguration:
                                                  FlyoutAutoConfiguration(
                                                    preferredMode:
                                                        FlyoutPlacementMode
                                                            .bottomCenter,
                                                  ),
                                              builder: (context) => MenuFlyout(
                                                items: [
                                                  MenuFlyoutItem(
                                                    leading: const Icon(
                                                      FluentIcons.add,
                                                      size: 14,
                                                    ),
                                                    text: const Text(
                                                      'Duplicate Tab',
                                                    ),
                                                    onPressed: () {
                                                      _addNewFlow(
                                                        initialIp: flow.ip,
                                                      );
                                                      Navigator.of(context).pop();
                                                    },
                                                  ),
                                                  MenuFlyoutItem(
                                                    leading: const Icon(
                                                      FluentIcons.share,
                                                      size: 14,
                                                    ),
                                                    text: const Text(
                                                      'Export Report',
                                                    ),
                                                    onPressed: () {
                                                      Navigator.of(context).pop();
                                                      showExportDialog(
                                                        context,
                                                        flow,
                                                      );
                                                    },
                                                  ),
                                                  MenuFlyoutItem(
                                                    leading: const Icon(
                                                      FluentIcons.copy,
                                                      size: 14,
                                                    ),
                                                    text: Text(
                                                      'Copy Target (${flow.ip})',
                                                    ),
                                                    onPressed: () {
                                                      Clipboard.setData(
                                                        ClipboardData(
                                                          text: flow.ip,
                                                        ),
                                                      );
                                                      displayInfoBar(
                                                        context,
                                                        builder:
                                                            (
                                                              context,
                                                              close,
                                                            ) => InfoBar(
                                                              title: const Text(
                                                                'Copied',
                                                              ),
                                                              content: Text(
                                                                '"${flow.ip}" copied to clipboard.',
                                                              ),
                                                              severity:
                                                                  InfoBarSeverity
                                                                      .success,
                                                              ),
                                                      );
                                                      Navigator.of(context).pop();
                                                    },
                                                  ),
                                                  if (_flows.length > 1) ...[
                                                    const MenuFlyoutSeparator(),
                                                    MenuFlyoutItem(
                                                      leading: const Icon(
                                                        FluentIcons.chrome_close,
                                                        size: 14,
                                                      ),
                                                      text: const Text(
                                                        'Close Tab',
                                                      ),
                                                      onPressed: () {
                                                        Navigator.of(
                                                          context,
                                                        ).pop();
                                                        _closeFlow(index);
                                                      },
                                                    ),
                                                    MenuFlyoutItem(
                                                      leading: const Icon(
                                                        FluentIcons.clear,
                                                        size: 14,
                                                      ),
                                                      text: const Text(
                                                        'Close Other Tabs',
                                                      ),
                                                      onPressed: () {
                                                        Navigator.of(
                                                          context,
                                                        ).pop();
                                                        _closeOtherFlows(index);
                                                      },
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            );
                                          },
                                          child: ListenableBuilder(
                                            listenable: flow.ipController,
                                            builder: (context, _) {
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    flow.title,
                                                    style: TextStyle(
                                                      color: index == activeIndex
                                                          ? colors.textPrimary
                                                          : colors.textSecondary,
                                                      fontWeight:
                                                          index == activeIndex
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  if (index == activeIndex) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        color: colors.accent,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      icon: leadingIcon,
                                      body: _buildDesktopFlowBody(flow, colors),
                                      onClosed: _flows.length > 1
                                          ? () => _closeFlow(index)
                                          : null,
                                    );
                                  }),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: _buildSplitView(colors, type),
                                ),
                        ),
                      ],
                    );

              return Stack(
                children: [
                  mainContent,

                  // Fade-in scrim behind the Statistics overlay
                  if (_isStatisticsVisible)
                    AnimatedOpacity(
                      opacity: _isStatisticsVisible ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(color: Colors.black),
                    ),

                  // Slide-in Statistics widget for the active flow
                  if (currentFlow != null)
                    Center(
                      child: SlideTransition(
                        position: _offsetAnimation,
                        child: Statistics(
                          IPStats: currentFlow.ipStats,
                          deepStats: currentFlow.deepStats,
                          interval: currentFlow.interval,
                          isRunning: currentFlow.isRunning,
                          graphInterval: currentFlow.graphInterval,
                          isLoading: currentFlow.isLoading,
                          totalPackets: currentFlow.packetSent,
                          dataCollected: currentFlow.dataCollected,
                          success: currentFlow.success,
                          toggleStatistics: _toggleStatisticsVisibility,
                          dataTypes: currentFlow.dataTypes,
                          setDataType: currentFlow.setDataType,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ViewModePill extends StatelessWidget {
  const _ViewModePill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    required this.type,
  });

  final String label;
  final IconData icon;
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
          color: isSelected
              ? colors.accent.withValues(alpha: 0.15)
              : colors.panelBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: type.caption.copyWith(
                color: isSelected ? colors.accent : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
