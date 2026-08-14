import 'package:PingRoute/statistics.dart';
import 'package:PingRoute/graph.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:system_theme/system_theme.dart';
import 'package:PingRoute/bottom_data.dart';
import 'navbar.dart';
import 'middle_data.dart';
import 'settings.dart';
import 'error.dart';
import 'theme.dart';
import 'breakpoints.dart';
import 'mobile_shell.dart';
import 'flow_session.dart';
import 'target_dialog.dart';
import 'export_dialog.dart';
import 'network_info_dialog.dart';

void main() {
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

enum ViewMode {
  tabs,
  splitTwo,
  splitGrid,
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with SingleTickerProviderStateMixin {
  final List<FlowSession> _flows = [];
  final List<FlyoutController> _tabFlyoutControllers = [];
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

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _statisticsController,
      curve: Curves.easeInOut,
    ));

    _addNewFlow(initialIp: '1.1.1.1');
  }

  void _onFlowUpdated() {
    if (mounted) {
      setState(() {});
    }
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
          newFlow.execTraceroute(onError: () {
            if (mounted) showErrorPopup(context);
          });
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
    });
  }

  void _toggleStatisticsVisibility() {
    final activeFlow = _flows.isNotEmpty ? _flows[_currentIndex.clamp(0, _flows.length - 1)] : null;
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

  Widget _buildDesktopFlowBody(FlowSession flow, AppColors colors) {
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
                Navbar(
                  key: ValueKey('navbar_${flow.id}'),
                  ipController: flow.ipController,
                  intervalController: flow.intervalController,
                  execTraceroute: () => flow.execTraceroute(onError: () => showErrorPopup(context)),
                  onReset: () => flow.reset(),
                  hasData: flow.dataCollected || flow.ipStats.isNotEmpty,
                  isRunning: flow.isRunning,
                  showSettings: () => showSettingsPopup(
                    context,
                    flow.graphInterval,
                    flow.packetsLimit,
                    flow.changeSettingParams,
                    packetSize: flow.packetSize,
                    maxHops: flow.maxHops,
                    timeoutMs: flow.timeoutMs,
                  ),
                  onExport: () => showExportDialog(context, flow),
                  setText: flow.setText,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LeftData(
                    data: flow.tracerouteResult,
                    isLoading: flow.isLoading,
                    IPStats: flow.ipStats,
                    deepStats: flow.deepStats,
                    interval: flow.graphInterval,
                    isRunning: flow.isRunning,
                    isSuccess: flow.success,
                    onOpenInNewTab: (ip) => _addNewFlow(initialIp: ip, autoStart: true),
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
                toggleStatistics: _toggleStatisticsVisibility,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitCard(FlowSession flow, int index, AppColors colors, AppTypography type) {
    return Container(
      key: ValueKey(flow.id),
      decoration: BoxDecoration(
        color: colors.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        children: [
          // Header Bar for Split Pane with editable Target IP & Interval
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.panelBackgroundAlt,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
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
                      flow.isRunning ? FluentIcons.circle_pause_solid : FluentIcons.play_solid,
                      size: 26,
                      color: flow.isRunning ? colors.latencyWarn : colors.latencyGood,
                    ),
                    onPressed: () => flow.execTraceroute(onError: () => showErrorPopup(context)),
                  ),
                ),
                if (flow.dataCollected || flow.ipStats.isNotEmpty)
                  Tooltip(
                    message: 'Reset Session & Clear Telemetry',
                    child: IconButton(
                      icon: Icon(FluentIcons.refresh, size: 14, color: colors.textSecondary),
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
                    icon: Icon(FluentIcons.share, size: 16, color: colors.textSecondary),
                    onPressed: () => showExportDialog(context, flow),
                  ),
                ),
                Tooltip(
                  message: 'Settings',
                  child: IconButton(
                    icon: Icon(FluentIcons.settings, size: 16, color: colors.textSecondary),
                    onPressed: () => showSettingsPopup(
                      context,
                      flow.graphInterval,
                      flow.packetsLimit,
                      flow.changeSettingParams,
                      packetSize: flow.packetSize,
                      maxHops: flow.maxHops,
                      timeoutMs: flow.timeoutMs,
                    ),
                  ),
                ),
                if (_flows.length > 1)
                  Tooltip(
                    message: 'Close Flow',
                    child: IconButton(
                      icon: Icon(FluentIcons.chrome_close, size: 14, color: colors.textSecondary),
                      onPressed: () => _closeFlow(index),
                    ),
                  ),
              ],
            ),
          ),
          // Split Pane Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
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
                      onOpenInNewTab: (ip) => _addNewFlow(initialIp: ip),
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
                              dataType: 'lt',
                              interval: flow.interval,
                              isRunning: flow.isRunning,
                            )
                          : Center(
                              child: flow.isLoading
                                  ? const ProgressRing()
                                  : Text('No data available', style: type.caption),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitView(AppColors colors, AppTypography type) {
    if (_flows.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_viewMode == ViewMode.splitTwo) {
      final firstFlow = _flows[0];
      final secondFlow = _flows.length > 1 ? _flows[1] : null;

      return Row(
        children: [
          Expanded(child: _buildSplitCard(firstFlow, 0, colors, type)),
          const SizedBox(width: 12),
          Expanded(
            child: secondFlow != null
                ? _buildSplitCard(secondFlow, 1, colors, type)
                : Center(
                    child: Button(
                      onPressed: () => _addNewFlow(initialIp: '8.8.8.8', autoStart: true),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.add, size: 14),
                          SizedBox(width: 6),
                          Text('Add 2nd Target to Compare'),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      );
    } else {
      // 4-Pane Grid
      final flowsToShow = _flows.take(4).toList();
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildSplitCard(flowsToShow[0], 0, colors, type)),
                const SizedBox(width: 12),
                Expanded(
                  child: flowsToShow.length > 1
                      ? _buildSplitCard(flowsToShow[1], 1, colors, type)
                      : Center(
                          child: Button(
                            onPressed: () => _addNewFlow(initialIp: '8.8.8.8', autoStart: true),
                            child: const Text('+ Add Target 2'),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: flowsToShow.length > 2
                      ? _buildSplitCard(flowsToShow[2], 2, colors, type)
                      : Center(
                          child: Button(
                            onPressed: () => _addNewFlow(initialIp: '9.9.9.9', autoStart: true),
                            child: const Text('+ Add Target 3'),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: flowsToShow.length > 3
                      ? _buildSplitCard(flowsToShow[3], 3, colors, type)
                      : Center(
                          child: Button(
                            onPressed: () => _addNewFlow(initialIp: '208.67.222.222', autoStart: true),
                            child: const Text('+ Add Target 4'),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final activeIndex = _currentIndex.clamp(0, _flows.isNotEmpty ? _flows.length - 1 : 0);
    final currentFlow = _flows.isNotEmpty ? _flows[activeIndex] : null;

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () => _addNewFlow(initialIp: '8.8.8.8'),
      const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => _addNewFlow(initialIp: '8.8.8.8'),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _closeFlow(_currentIndex),
      const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeFlow(_currentIndex),
      const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => currentFlow?.execTraceroute(),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => currentFlow?.execTraceroute(),
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
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => showNetworkInfoDialog(context),
      const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => showNetworkInfoDialog(context),
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
        if (currentFlow != null) {
          showSettingsPopup(
            context,
            currentFlow.graphInterval,
            currentFlow.packetsLimit,
            currentFlow.changeSettingParams,
            packetSize: currentFlow.packetSize,
            maxHops: currentFlow.maxHops,
            timeoutMs: currentFlow.timeoutMs,
          );
        }
      },
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
        if (currentFlow != null) {
          showSettingsPopup(
            context,
            currentFlow.graphInterval,
            currentFlow.packetsLimit,
            currentFlow.changeSettingParams,
            packetSize: currentFlow.packetSize,
            maxHops: currentFlow.maxHops,
            timeoutMs: currentFlow.timeoutMs,
          );
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
              if (screenClassForWidth(constraints.maxWidth) == ScreenClass.mobile) {
                return MobileShell(
                  flows: _flows,
                  currentFlowIndex: activeIndex,
                  onFlowSelected: (index) => setState(() => _currentIndex = index),
                  onAddFlow: () => _addNewFlow(initialIp: '8.8.8.8'),
                  onCloseFlow: _closeFlow,
                  showSettings: () {
                    if (currentFlow != null) {
                      showSettingsPopup(
                        context,
                        currentFlow.graphInterval,
                        currentFlow.packetsLimit,
                        currentFlow.changeSettingParams,
                        packetSize: currentFlow.packetSize,
                        maxHops: currentFlow.maxHops,
                        timeoutMs: currentFlow.timeoutMs,
                      );
                    }
                  },
                );
              }

              return Stack(
                children: [
                  Column(
                    children: [
                      // Desktop Top Header: Tab / Split Controls
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.pageBackground,
                          border: Border(bottom: BorderSide(color: colors.borderColor)),
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
                                  onTap: () => setState(() => _viewMode = ViewMode.tabs),
                                  colors: colors,
                                  type: type,
                                ),
                                const SizedBox(width: 6),
                                _ViewModePill(
                                  label: '2-Flow Split',
                                  icon: FluentIcons.column_left_two_thirds,
                                  isSelected: _viewMode == ViewMode.splitTwo,
                                  onTap: () {
                                    if (_flows.length < 2) {
                                      _addNewFlow(initialIp: '8.8.8.8');
                                    }
                                    setState(() => _viewMode = ViewMode.splitTwo);
                                  },
                                  colors: colors,
                                  type: type,
                                ),
                                const SizedBox(width: 6),
                                _ViewModePill(
                                  label: '4-Flow Grid',
                                  icon: FluentIcons.grid_view_medium,
                                  isSelected: _viewMode == ViewMode.splitGrid,
                                  onTap: () {
                                    while (_flows.length < 4) {
                                      final sampleIps = ['8.8.8.8', '9.9.9.9', '208.67.222.222'];
                                      _addNewFlow(
                                        initialIp: sampleIps[(_flows.length - 1) % sampleIps.length],
                                      );
                                    }
                                    setState(() => _viewMode = ViewMode.splitGrid);
                                  },
                                  colors: colors,
                                  type: type,
                                ),
                              ],
                            ),
                            Button(
                              onPressed: () => _addNewFlow(initialIp: '8.8.8.8'),
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
                                onChanged: (index) => setState(() => _currentIndex = index),
                                onNewPressed: () => _addNewFlow(initialIp: '8.8.8.8'),
                                onReorder: (oldIndex, newIndex) {
                                  setState(() {
                                    if (oldIndex < newIndex) {
                                      newIndex -= 1;
                                    }
                                    final item = _flows.removeAt(oldIndex);
                                    final flyout = _tabFlyoutControllers.removeAt(oldIndex);
                                    _flows.insert(newIndex, item);
                                    _tabFlyoutControllers.insert(newIndex, flyout);

                                    if (_currentIndex == oldIndex) {
                                      _currentIndex = newIndex;
                                    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
                                      _currentIndex -= 1;
                                    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
                                      _currentIndex += 1;
                                    }
                                  });
                                },
                                tabs: List.generate(_flows.length, (index) {
                                  final flow = _flows[index];
                                  final tabFlyout = index < _tabFlyoutControllers.length
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
                                    leadingIcon = const Icon(FluentIcons.network_tower, size: 14);
                                  }

                                  return Tab(
                                    text: FlyoutTarget(
                                      controller: tabFlyout,
                                      child: GestureDetector(
                                        onSecondaryTapDown: (details) {
                                          tabFlyout.showFlyout(
                                            barrierColor: Colors.transparent,
                                            autoModeConfiguration: FlyoutAutoConfiguration(
                                              preferredMode: FlyoutPlacementMode.bottomCenter,
                                            ),
                                            builder: (context) => MenuFlyout(
                                              items: [
                                                MenuFlyoutItem(
                                                  leading: const Icon(FluentIcons.add, size: 14),
                                                  text: const Text('Duplicate Tab'),
                                                  onPressed: () {
                                                    _addNewFlow(initialIp: flow.ip);
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                                MenuFlyoutItem(
                                                  leading: const Icon(FluentIcons.share, size: 14),
                                                  text: const Text('Export Report'),
                                                  onPressed: () {
                                                    Navigator.of(context).pop();
                                                    showExportDialog(context, flow);
                                                  },
                                                ),
                                                MenuFlyoutItem(
                                                  leading: const Icon(FluentIcons.copy, size: 14),
                                                  text: Text('Copy Target (${flow.ip})'),
                                                  onPressed: () {
                                                    Clipboard.setData(ClipboardData(text: flow.ip));
                                                    displayInfoBar(
                                                      context,
                                                      builder: (context, close) => InfoBar(
                                                        title: const Text('Copied'),
                                                        content: Text('"${flow.ip}" copied to clipboard.'),
                                                        severity: InfoBarSeverity.success,
                                                      ),
                                                    );
                                                    Navigator.of(context).pop();
                                                  },
                                                ),
                                                if (_flows.length > 1) ...[
                                                  const MenuFlyoutSeparator(),
                                                  MenuFlyoutItem(
                                                    leading: const Icon(FluentIcons.chrome_close, size: 14),
                                                    text: const Text('Close Tab'),
                                                    onPressed: () {
                                                      Navigator.of(context).pop();
                                                      _closeFlow(index);
                                                    },
                                                  ),
                                                  MenuFlyoutItem(
                                                    leading: const Icon(FluentIcons.clear, size: 14),
                                                    text: const Text('Close Other Tabs'),
                                                    onPressed: () {
                                                      Navigator.of(context).pop();
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
                                                    color: index == activeIndex ? colors.textPrimary : colors.textSecondary,
                                                    fontWeight: index == activeIndex ? FontWeight.w600 : FontWeight.w500,
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
                                    onClosed: _flows.length > 1 ? () => _closeFlow(index) : null,
                                  );
                                }),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(12),
                                child: _buildSplitView(colors, type),
                              ),
                      ),
                    ],
                  ),

                  // Fade-in scrim behind the Statistics overlay
                  if (_isStatisticsVisible)
                    AnimatedOpacity(
                      opacity: _isStatisticsVisible ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        color: Colors.black,
                      ),
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
          color: isSelected ? colors.accent.withValues(alpha: 0.15) : colors.panelBackground,
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