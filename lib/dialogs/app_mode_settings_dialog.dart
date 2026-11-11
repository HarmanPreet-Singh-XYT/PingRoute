import 'package:fluent_ui/fluent_ui.dart';

import '../core/theme.dart';
import '../models/app_mode_settings.dart';

void showAppModeSettings(BuildContext context, AppModeSettings settings) {
  showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => _SettingsDialog(settings: settings),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.settings});

  final AppModeSettings settings;

  @override
  Widget build(BuildContext context) {
    final type = appTypography(context);
    return ContentDialog(
      title: const Text('App Mode settings'),
      constraints: const BoxConstraints(maxWidth: 560),
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading('Tracking', type),
              _Row(
                label: 'Which apps to track',
                help: settings.trackingMode.description,
                child: ComboBox<TrackingMode>(
                  value: settings.trackingMode,
                  items: [
                    for (final m in TrackingMode.values)
                      ComboBoxItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) settings.setTrackingMode(v);
                  },
                ),
              ),
              _heading('Monitoring', type),
              _Row(
                label: 'Refresh connections every',
                help: 'How often the app list and endpoints are re-read.',
                child: _choice(
                  AppModeSettings.pollIntervalChoices,
                  settings.pollIntervalSec,
                  settings.setPollIntervalSec,
                  (v) => '$v s',
                ),
              ),
              _Row(
                label: 'Live pings (max)',
                help:
                    'Endpoints pinged at once, busiest first. Higher values '
                    'use more CPU and network.',
                child: SizedBox(
                  width: 220,
                  child: Slider(
                    value: settings.maxLivePingers.toDouble(),
                    min: AppModeSettings.minPingers.toDouble(),
                    max: AppModeSettings.maxPingersLimit.toDouble(),
                    divisions:
                        AppModeSettings.maxPingersLimit -
                        AppModeSettings.minPingers,
                    label: '${settings.maxLivePingers}',
                    onChanged: (v) => settings.setMaxLivePingers(v.round()),
                  ),
                ),
              ),
              _Row(
                label: 'Ping interval',
                help: 'Time between pings to each endpoint.',
                child: _choice(
                  AppModeSettings.pingIntervalChoices,
                  settings.pingIntervalSec,
                  settings.setPingIntervalSec,
                  (v) => '$v s',
                ),
              ),
              _Row(
                label: 'Keep closed endpoints for',
                help: 'Closed connections stay listed greyed out this long.',
                child: _choice(
                  AppModeSettings.idleRetentionChoices,
                  settings.idleRetentionSec,
                  settings.setIdleRetentionSec,
                  (v) => v >= 60 ? '${v ~/ 60} min' : '$v s',
                ),
              ),
              _heading('What to show', type),
              _Row(
                label: 'Hide system apps',
                help: 'Hides OS services such as launchd and mDNSResponder.',
                child: ToggleSwitch(
                  checked: settings.hideSystemApps,
                  onChanged: settings.setHideSystemApps,
                ),
              ),
              _Row(
                label: 'Include local network',
                help: 'Also list LAN, loopback and link-local peers.',
                child: ToggleSwitch(
                  checked: settings.includePrivate,
                  onChanged: settings.setIncludePrivate,
                ),
              ),
              _Row(
                label: 'Include UDP / QUIC',
                help: 'Shows HTTP/3 and other UDP flows. macOS only.',
                child: ToggleSwitch(
                  checked: settings.includeUdp,
                  onChanged: settings.setIncludeUdp,
                ),
              ),
              _Row(
                label: 'TCP check for silent hosts',
                help:
                    'If a host ignores ping, time a TCP connection to the '
                    'port the app already uses. Opens short connections to '
                    'that server.',
                child: ToggleSwitch(
                  checked: settings.tcpFallback,
                  onChanged: settings.setTcpFallback,
                ),
              ),
              _heading('Alerts', type),
              _Row(
                label: 'Flag endpoint as poor at',
                help: 'Recent packet loss at or above this marks it Poor.',
                child: _choice(
                  AppModeSettings.lossAlertChoices,
                  settings.lossAlertPercent,
                  settings.setLossAlertPercent,
                  (v) => '$v% loss',
                ),
              ),
              _heading('Display', type),
              _Row(
                label: 'Row density',
                child: ComboBox<RowDensity>(
                  value: settings.density,
                  items: [
                    for (final d in RowDensity.values)
                      ComboBoxItem(value: d, child: Text(d.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) settings.setDensity(v);
                  },
                ),
              ),
              _Row(
                label: 'Default sort',
                child: ComboBox<EndpointSort>(
                  value: settings.defaultSort,
                  items: [
                    for (final s in EndpointSort.values)
                      ComboBoxItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) settings.setDefaultSort(v);
                  },
                ),
              ),
              _Row(
                label: 'Start tracking automatically',
                help:
                    'Off: open an app and click Start to begin tracking its '
                    'IPs and stats. On: tracking begins as soon as you pick it.',
                child: ToggleSwitch(
                  checked: settings.autoStartTracking,
                  onChanged: settings.setAutoStartTracking,
                ),
              ),
              _Row(
                label: 'Remember pinned apps',
                help: 'Restores your pinned and selected apps next time.',
                child: ToggleSwitch(
                  checked: settings.rememberSelection,
                  onChanged: settings.setRememberSelection,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Button(
          onPressed: settings.resetToDefaults,
          child: const Text('Reset to defaults'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _heading(String text, AppTypography type) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(text, style: type.subtitle),
  );

  Widget _choice(
    List<int> options,
    int value,
    ValueChanged<int> onChanged,
    String Function(int) label,
  ) => ComboBox<int>(
    value: value,
    items: [
      for (final o in options) ComboBoxItem(value: o, child: Text(label(o))),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.help});

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final type = appTypography(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: type.body),
                if (help != null) Text(help!, style: type.caption),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }
}
