import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'storage_helper.dart';
import 'theme.dart';
import 'target_directory.dart';

class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._internal();

  final bool _isTest;

  AppSettings._internal() : _isTest = false {
    _loadFromDisk();
  }

  // Visible for testing without disk I/O
  AppSettings.test({
    ThemeMode initialThemeMode = ThemeMode.system,
    int initialDefaultInterval = 1000,
    int initialDefaultGraphInterval = 1000,
    int initialDefaultPacketsLimit = 25,
    int initialDefaultPacketSize = 56,
    int initialDefaultMaxHops = 30,
    int initialDefaultTimeoutMs = 1000,
    double initialUiScale = 1.0,
  })  : _isTest = true,
        _themeMode = initialThemeMode,
        _defaultInterval = initialDefaultInterval,
        _defaultGraphInterval = initialDefaultGraphInterval,
        _defaultPacketsLimit = initialDefaultPacketsLimit,
        _defaultPacketSize = initialDefaultPacketSize,
        _defaultMaxHops = initialDefaultMaxHops,
        _defaultTimeoutMs = initialDefaultTimeoutMs,
        _uiScale = initialUiScale;

  ThemeMode _themeMode = ThemeMode.system;
  int _defaultInterval = 1000;
  int _defaultGraphInterval = 1000;
  int _defaultPacketsLimit = 25;
  int _defaultPacketSize = 56;
  int _defaultMaxHops = 30;
  int _defaultTimeoutMs = 1000;
  double _uiScale = 1.0;

  ThemeMode get themeMode => _themeMode;
  int get defaultInterval => _defaultInterval;
  int get defaultGraphInterval => _defaultGraphInterval;
  int get defaultPacketsLimit => _defaultPacketsLimit;
  int get defaultPacketSize => _defaultPacketSize;
  int get defaultMaxHops => _defaultMaxHops;
  int get defaultTimeoutMs => _defaultTimeoutMs;
  double get uiScale => _uiScale;

  static String _resolveStoragePath() {
    try {
      return StorageHelper.getFilePath('settings.json');
    } catch (_) {
      return 'settings.json';
    }
  }

  void _loadFromDisk() {
    if (_isTest) return;
    try {
      final file = File(_resolveStoragePath());
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);

          final modeStr = data['themeMode'] as String?;
          if (modeStr == 'light') {
            _themeMode = ThemeMode.light;
          } else if (modeStr == 'dark') {
            _themeMode = ThemeMode.dark;
          } else {
            _themeMode = ThemeMode.system;
          }

          if (data['defaultInterval'] is int && (data['defaultInterval'] as int) > 0) {
            _defaultInterval = data['defaultInterval'] as int;
          }
          if (data['defaultGraphInterval'] is int && (data['defaultGraphInterval'] as int) > 0) {
            _defaultGraphInterval = data['defaultGraphInterval'] as int;
          }
          if (data['defaultPacketsLimit'] is int && (data['defaultPacketsLimit'] as int) >= 16) {
            _defaultPacketsLimit = data['defaultPacketsLimit'] as int;
          }
          if (data['defaultPacketSize'] is int && (data['defaultPacketSize'] as int) >= 28) {
            _defaultPacketSize = data['defaultPacketSize'] as int;
          }
          if (data['defaultMaxHops'] is int && (data['defaultMaxHops'] as int) >= 1) {
            _defaultMaxHops = data['defaultMaxHops'] as int;
          }
          if (data['defaultTimeoutMs'] is int && (data['defaultTimeoutMs'] as int) >= 100) {
            _defaultTimeoutMs = data['defaultTimeoutMs'] as int;
          }
          if (data['uiScale'] is num) {
            _uiScale = (data['uiScale'] as num).toDouble().clamp(0.75, 1.50);
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load settings from disk: $e');
    }
  }

  void saveToDisk() {
    if (_isTest) return;
    try {
      final file = File(_resolveStoragePath());
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final modeStr = _themeMode == ThemeMode.light
          ? 'light'
          : _themeMode == ThemeMode.dark
              ? 'dark'
              : 'system';

      final data = {
        'themeMode': modeStr,
        'defaultInterval': _defaultInterval,
        'defaultGraphInterval': _defaultGraphInterval,
        'defaultPacketsLimit': _defaultPacketsLimit,
        'defaultPacketSize': _defaultPacketSize,
        'defaultMaxHops': _defaultMaxHops,
        'defaultTimeoutMs': _defaultTimeoutMs,
        'uiScale': _uiScale,
      };

      file.writeAsStringSync(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Failed to save settings to disk: $e');
    }
  }

  void setUiScale(double scale) {
    final clamped = scale.clamp(0.75, 1.50);
    if ((_uiScale - clamped).abs() > 0.001) {
      _uiScale = clamped;
      notifyListeners();
      saveToDisk();
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      saveToDisk();
    }
  }

  void toggleTheme(BuildContext context) {
    final currentBrightness = FluentTheme.of(context).brightness;
    if (currentBrightness == Brightness.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }

  void setDefaults({
    int? interval,
    int? graphInterval,
    int? packetsLimit,
    int? packetSize,
    int? maxHops,
    int? timeoutMs,
  }) {
    if (interval != null && interval > 0) _defaultInterval = interval;
    if (graphInterval != null && graphInterval > 0) _defaultGraphInterval = graphInterval;
    if (packetsLimit != null && packetsLimit >= 16) _defaultPacketsLimit = packetsLimit;
    if (packetSize != null && packetSize >= 28 && packetSize <= 65507) _defaultPacketSize = packetSize;
    if (maxHops != null && maxHops >= 1 && maxHops <= 64) _defaultMaxHops = maxHops;
    if (timeoutMs != null && timeoutMs >= 100 && timeoutMs <= 10000) _defaultTimeoutMs = timeoutMs;
    notifyListeners();
    saveToDisk();
  }
}

Future<void> _launchUrlString(String url) async {
  bool launched = false;
  try {
    final uri = Uri.parse(url);
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    launched = false;
  }

  if (!launched) {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Desktop process launch error: $e');
    }
  }
}

void showSettingsPopup(
  BuildContext context,
  int graphInterval,
  int packetsLimit,
  Function(String text, String type) changeSettingParams, {
  int packetSize = 56,
  int maxHops = 30,
  int timeoutMs = 1000,
}) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return _SettingsDialogContent(
        graphInterval: graphInterval,
        packetsLimit: packetsLimit,
        packetSize: packetSize,
        maxHops: maxHops,
        timeoutMs: timeoutMs,
        changeSettingParams: changeSettingParams,
      );
    },
  );
}

class _SettingsDialogContent extends StatefulWidget {
  const _SettingsDialogContent({
    required this.graphInterval,
    required this.packetsLimit,
    required this.changeSettingParams,
    this.packetSize = 56,
    this.maxHops = 30,
    this.timeoutMs = 1000,
  });

  final int graphInterval;
  final int packetsLimit;
  final int packetSize;
  final int maxHops;
  final int timeoutMs;
  final Function(String text, String type) changeSettingParams;

  @override
  State<_SettingsDialogContent> createState() => _SettingsDialogContentState();
}

class _SettingsDialogContentState extends State<_SettingsDialogContent> {
  late int _graphInterval;
  late int _packetsLimit;
  late int _packetSize;
  late int _maxHops;
  late int _timeoutMs;

  @override
  void initState() {
    super.initState();
    _graphInterval = widget.graphInterval;
    _packetsLimit = widget.packetsLimit;
    _packetSize = widget.packetSize;
    _maxHops = widget.maxHops;
    _timeoutMs = widget.timeoutMs;
  }

  void _showContactOptions() {
    final colors = appColors(context);
    final type = appTypography(context);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 380),
          title: Row(
            children: [
              Icon(FluentIcons.contact, size: 20, color: colors.accent),
              const SizedBox(width: 8),
              Text('Contact & Support', style: type.title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose how you would like to reach out:', style: type.body),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: colors.panelBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderColor),
                ),
                child: Column(
                  children: [
                    _ContactOptionTile(
                      icon: FluentIcons.shopping_cart,
                      title: 'Microsoft Store',
                      subtitle: 'Rate, review, or install on Windows Store',
                      colors: colors,
                      type: type,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _launchUrlString('https://apps.microsoft.com/detail/9mvqgxvmc883?hl=en-US&gl=CA');
                      },
                    ),
                    const Divider(),
                    _ContactOptionTile(
                      icon: FluentIcons.globe,
                      title: 'Visit harmanita.com',
                      subtitle: 'Developer website & portfolio',
                      colors: colors,
                      type: type,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _launchUrlString('https://harmanita.com');
                      },
                    ),
                    const Divider(),
                    _ContactOptionTile(
                      icon: FluentIcons.mail,
                      title: 'Mail to pingroute@harmanita.com',
                      subtitle: 'Direct email inquiry & feedback',
                      colors: colors,
                      type: type,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _launchUrlString('mailto:pingroute@harmanita.com');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Button(
              child: const Text('Close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = appTypography(context);
    final colors = appColors(context);

    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final currentMode = AppSettings.instance.themeMode;

        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          title: Row(
            children: [
              Icon(FluentIcons.settings, size: 22, color: colors.accent),
              const SizedBox(width: 10),
              Text('Settings', style: type.title),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Appearance & Scaling
                Text('Appearance & Scaling', style: type.subtitle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.panelBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Theme Mode', style: type.bodyStrong),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _ThemeOptionButton(
                            label: 'System',
                            icon: FluentIcons.devices4,
                            isSelected: currentMode == ThemeMode.system,
                            onTap: () => AppSettings.instance.setThemeMode(ThemeMode.system),
                            colors: colors,
                            type: type,
                          ),
                          const SizedBox(width: 8),
                          _ThemeOptionButton(
                            label: 'Light',
                            icon: FluentIcons.sunny,
                            isSelected: currentMode == ThemeMode.light,
                            onTap: () => AppSettings.instance.setThemeMode(ThemeMode.light),
                            colors: colors,
                            type: type,
                          ),
                          const SizedBox(width: 8),
                          _ThemeOptionButton(
                            label: 'Dark',
                            icon: FluentIcons.clear_night,
                            isSelected: currentMode == ThemeMode.dark,
                            onTap: () => AppSettings.instance.setThemeMode(ThemeMode.dark),
                            colors: colors,
                            type: type,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(style: DividerThemeData(decoration: BoxDecoration(color: colors.borderColor))),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('UI Scaling', style: type.bodyStrong),
                          Text(
                            '${(AppSettings.instance.uiScale * 100).round()}%',
                            style: type.bodyStrong.copyWith(color: colors.accent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _ScalePresetButton(
                            label: '85% Compact',
                            scale: 0.85,
                            currentScale: AppSettings.instance.uiScale,
                            onTap: (s) => AppSettings.instance.setUiScale(s),
                            colors: colors,
                            type: type,
                          ),
                          const SizedBox(width: 6),
                          _ScalePresetButton(
                            label: '100% Normal',
                            scale: 1.0,
                            currentScale: AppSettings.instance.uiScale,
                            onTap: (s) => AppSettings.instance.setUiScale(s),
                            colors: colors,
                            type: type,
                          ),
                          const SizedBox(width: 6),
                          _ScalePresetButton(
                            label: '115% Large',
                            scale: 1.15,
                            currentScale: AppSettings.instance.uiScale,
                            onTap: (s) => AppSettings.instance.setUiScale(s),
                            colors: colors,
                            type: type,
                          ),
                          const SizedBox(width: 6),
                          _ScalePresetButton(
                            label: '130% XL',
                            scale: 1.30,
                            currentScale: AppSettings.instance.uiScale,
                            onTap: (s) => AppSettings.instance.setUiScale(s),
                            colors: colors,
                            type: type,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Advanced Network Probing Options
                Text('Network Probing Options', style: type.subtitle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.panelBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Packet payload size', style: type.bodyStrong),
                              Text('ICMP payload bytes (MTU testing)', style: type.caption),
                            ],
                          ),
                          SizedBox(
                            width: 120,
                            child: NumberBox<int>(
                              value: _packetSize,
                              mode: SpinButtonPlacementMode.inline,
                              min: 28,
                              max: 65507,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _packetSize = value);
                                  widget.changeSettingParams('$value', 'packetSize');
                                  AppSettings.instance.setDefaults(packetSize: value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Preset pills for MTU payload
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [56, 64, 512, 1472].map((sz) {
                          final isSelected = _packetSize == sz;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _packetSize = sz);
                              widget.changeSettingParams('$sz', 'packetSize');
                              AppSettings.instance.setDefaults(packetSize: sz);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? colors.accent.withValues(alpha: 0.2) : colors.pageBackground,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected ? colors.accent : colors.borderColor,
                                ),
                              ),
                              child: Text(
                                sz == 1472 ? '1472B (MTU)' : '${sz}B',
                                style: type.caption.copyWith(
                                  color: isSelected ? colors.accent : colors.textSecondary,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Max hops discovery limit', style: type.bodyStrong),
                              Text('Traceroute TTL search boundary', style: type.caption),
                            ],
                          ),
                          SizedBox(
                            width: 120,
                            child: NumberBox<int>(
                              value: _maxHops,
                              mode: SpinButtonPlacementMode.inline,
                              min: 1,
                              max: 64,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _maxHops = value);
                                  widget.changeSettingParams('$value', 'maxHops');
                                  AppSettings.instance.setDefaults(maxHops: value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Probe timeout', style: type.bodyStrong),
                              Text('Max wait per hop packet (ms)', style: type.caption),
                            ],
                          ),
                          SizedBox(
                            width: 120,
                            child: NumberBox<int>(
                              value: _timeoutMs,
                              mode: SpinButtonPlacementMode.inline,
                              min: 200,
                              max: 10000,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _timeoutMs = value);
                                  widget.changeSettingParams('$value', 'timeoutMs');
                                  AppSettings.instance.setDefaults(timeoutMs: value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Active Flow Tab Settings
                Text('Active Flow Tab', style: type.subtitle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.panelBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Graph refresh interval', style: type.bodyStrong),
                              Text('How often the live graph updates (ms)', style: type.caption),
                            ],
                          ),
                          SizedBox(
                            width: 120,
                            child: NumberBox<int>(
                              value: _graphInterval,
                              mode: SpinButtonPlacementMode.inline,
                              min: 100,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _graphInterval = value);
                                  widget.changeSettingParams('$value', 'graphInterval');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Rolling packet limit', style: type.bodyStrong),
                              Text('Points preserved in rolling history', style: type.caption),
                            ],
                          ),
                          SizedBox(
                            width: 120,
                            child: NumberBox<int>(
                              value: _packetsLimit,
                              mode: SpinButtonPlacementMode.inline,
                              min: 16,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _packetsLimit = value);
                                  widget.changeSettingParams('$value', 'packetsLimit');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // History & Data Section
                Text('History & Data', style: type.subtitle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.panelBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recent IP Search History', style: type.bodyStrong),
                          Text('Clear the last 5 auto-suggested IPs', style: type.caption),
                        ],
                      ),
                      Button(
                        onPressed: () {
                          TargetDirectory.instance.clearRecent();
                          displayInfoBar(
                            context,
                            duration: const Duration(seconds: 1),
                            builder: (context, close) => const InfoBar(
                              title: Text('Cleared'),
                              content: Text('Recent search history has been cleared.'),
                              severity: InfoBarSeverity.info,
                            ),
                          );
                        },
                        child: const Text('Clear History'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // About, GitHub & Contact Section
                Text('About & Community', style: type.subtitle),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.panelBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset(
                              'logo.png',
                              width: 28,
                              height: 28,
                              errorBuilder: (_, __, ___) => Icon(FluentIcons.network_tower, size: 24, color: colors.accent),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PingRoute', style: type.bodyStrong.copyWith(fontSize: 15)),
                              Text('Multi-flow network latency and traceroute tool', style: type.caption),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Button(
                            onPressed: () => _launchUrlString('https://apps.microsoft.com/detail/9mvqgxvmc883?hl=en-US&gl=CA'),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.shopping_cart, size: 14),
                                SizedBox(width: 6),
                                Text('Microsoft Store'),
                              ],
                            ),
                          ),
                          Button(
                            onPressed: () => _launchUrlString('https://github.com/HarmanPreet-Singh-XYT/PingRoute'),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.code, size: 14),
                                SizedBox(width: 6),
                                Text('GitHub'),
                              ],
                            ),
                          ),
                          Button(
                            onPressed: _showContactOptions,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.mail, size: 14),
                                SizedBox(width: 6),
                                Text('Contact & Feedback'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Open Source • Developed by Harmanpreet Singh • harmanita.com',
                          style: type.caption.copyWith(color: colors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              child: const Text('Done'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

class _ThemeOptionButton extends StatelessWidget {
  const _ThemeOptionButton({
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.accent.withValues(alpha: 0.15) : colors.pageBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? colors.accent : colors.borderColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? colors.accent : colors.textSecondary,
              ),
              const SizedBox(height: 4),
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
      ),
    );
  }
}

class _ContactOptionTile extends StatefulWidget {
  const _ContactOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.colors,
    required this.type,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final AppColors colors;
  final AppTypography type;

  @override
  State<_ContactOptionTile> createState() => _ContactOptionTileState();
}

class _ContactOptionTileState extends State<_ContactOptionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.accent.withValues(alpha: 0.1)
                : widget.colors.panelBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.colors.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: widget.type.bodyStrong),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: widget.type.caption),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right,
                size: 14,
                color: _isHovered ? widget.colors.accent : widget.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScalePresetButton extends StatelessWidget {
  const _ScalePresetButton({
    required this.label,
    required this.scale,
    required this.currentScale,
    required this.onTap,
    required this.colors,
    required this.type,
  });

  final String label;
  final double scale;
  final double currentScale;
  final ValueChanged<double> onTap;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    final isSelected = (currentScale - scale).abs() < 0.01;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(scale),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.accent.withValues(alpha: 0.15)
                : colors.panelBackgroundAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? colors.accent : colors.borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: type.caption.copyWith(
                color: isSelected ? colors.accent : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
