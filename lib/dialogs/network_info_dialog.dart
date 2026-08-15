import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../core/storage_helper.dart';
import '../core/theme.dart';

class NetworkInterfaceInfo {
  final String name;
  final List<String> ipv4Addresses;
  final List<String> ipv6Addresses;

  NetworkInterfaceInfo({
    required this.name,
    required this.ipv4Addresses,
    required this.ipv6Addresses,
  });
}

class NetworkDiagnosticsData {
  final String hostname;
  final String osVersion;
  final List<NetworkInterfaceInfo> interfaces;
  final String defaultGateway;
  final List<String> dnsServers;
  final String publicIp;
  final String publicIsp;
  final String publicLocation;
  final bool isFromCache;
  final String? publicIpError;
  final DateTime scannedAt;

  NetworkDiagnosticsData({
    required this.hostname,
    required this.osVersion,
    required this.interfaces,
    required this.defaultGateway,
    required this.dnsServers,
    required this.publicIp,
    required this.publicIsp,
    required this.publicLocation,
    required this.isFromCache,
    this.publicIpError,
    required this.scannedAt,
  });

  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# 🌐 PingRoute System Network Diagnostics');
    buffer.writeln('Scanned: ${scannedAt.toIso8601String()}');
    buffer.writeln('Hostname: $hostname');
    buffer.writeln('OS: $osVersion\n');

    buffer.writeln('## 🌍 Public Internet');
    buffer.writeln(
      '- Public IP: ${publicIp.isNotEmpty ? publicIp : "Unknown"}${isFromCache ? " (Cached)" : ""}',
    );
    if (publicIsp.isNotEmpty) buffer.writeln('- ISP / ASN: $publicIsp');
    if (publicLocation.isNotEmpty)
      buffer.writeln('- Location: $publicLocation');
    buffer.writeln();

    buffer.writeln('## 🚪 Gateway & DNS');
    buffer.writeln(
      '- Default Gateway: ${defaultGateway.isNotEmpty ? defaultGateway : "Not detected"}',
    );
    buffer.writeln(
      '- DNS Servers: ${dnsServers.isNotEmpty ? dnsServers.join(", ") : "None detected"}\n',
    );

    buffer.writeln('## 🔌 Local Network Interfaces');
    for (final iface in interfaces) {
      buffer.writeln('### Interface `${iface.name}`');
      if (iface.ipv4Addresses.isNotEmpty) {
        buffer.writeln('- IPv4: ${iface.ipv4Addresses.join(", ")}');
      }
      if (iface.ipv6Addresses.isNotEmpty) {
        buffer.writeln('- IPv6: ${iface.ipv6Addresses.join(", ")}');
      }
      if (iface.ipv4Addresses.isEmpty && iface.ipv6Addresses.isEmpty) {
        buffer.writeln('- No active IP addresses');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}

class NetworkDiagnosticsService {
  static String _resolveCachePath() {
    try {
      return StorageHelper.getFilePath('net_cache.json');
    } catch (_) {
      return 'net_cache.json';
    }
  }

  static Map<String, dynamic>? _loadCache({bool isTest = false}) {
    if (isTest) return null;
    try {
      final file = File(_resolveCachePath());
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('Failed to load network cache: $e');
    }
    return null;
  }

  static void _saveCache(Map<String, dynamic> data, {bool isTest = false}) {
    if (isTest) return;
    try {
      final file = File(_resolveCachePath());
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      file.writeAsStringSync(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Failed to save network cache: $e');
    }
  }

  static Future<NetworkDiagnosticsData> scan({
    bool forceRefresh = false,
    bool isTest = false,
  }) async {
    final hostname = Platform.localHostname;
    final osVersion =
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

    // 1. Interfaces
    final List<NetworkInterfaceInfo> interfaces = [];
    String firstLocalIpv4 = '';
    try {
      final nativeInterfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.any,
      );
      for (final iface in nativeInterfaces) {
        final ipv4s = <String>[];
        final ipv6s = <String>[];
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            ipv4s.add(addr.address);
            if (firstLocalIpv4.isEmpty &&
                !addr.isLoopback &&
                !addr.isLinkLocal) {
              firstLocalIpv4 = addr.address;
            }
          } else if (addr.type == InternetAddressType.IPv6) {
            ipv6s.add(addr.address);
          }
        }
        interfaces.add(
          NetworkInterfaceInfo(
            name: iface.name,
            ipv4Addresses: ipv4s,
            ipv6Addresses: ipv6s,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to list interfaces: $e');
    }

    // 2. Default Gateway
    String defaultGateway = '';
    try {
      if (Platform.isMacOS) {
        final res = await Process.run('route', ['-n', 'get', 'default']);
        final out = res.stdout.toString();
        final match = RegExp(r'gateway:\s+([^\s\r\n]+)').firstMatch(out);
        if (match != null) defaultGateway = match.group(1)!;
      } else if (Platform.isLinux) {
        final res = await Process.run('ip', ['route', 'show', 'default']);
        final out = res.stdout.toString();
        final match = RegExp(r'default via ([^\s]+)').firstMatch(out);
        if (match != null) defaultGateway = match.group(1)!;
      } else if (Platform.isWindows) {
        final res = await Process.run('route', ['print', '0.0.0.0']);
        final out = res.stdout.toString();
        final match = RegExp(
          r'0\.0\.0\.0\s+0\.0\.0\.0\s+([0-9\.]+)\s+([0-9\.]+)',
        ).firstMatch(out);
        if (match != null) defaultGateway = match.group(1)!;
      }
    } catch (_) {}

    // 3. DNS Servers
    final dnsServers = <String>[];
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final file = File('/etc/resolv.conf');
        if (file.existsSync()) {
          final lines = file.readAsLinesSync();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('nameserver ')) {
              final ip = trimmed.replaceFirst('nameserver ', '').trim();
              if (ip.isNotEmpty && !dnsServers.contains(ip)) {
                dnsServers.add(ip);
              }
            }
          }
        }
      }
    } catch (_) {}

    // 4. Check Persistent Cache by Network Signature
    final networkSignature = '$defaultGateway|$firstLocalIpv4';
    final cached = _loadCache(isTest: isTest);

    String publicIp = '';
    String publicIsp = '';
    String publicLocation = '';
    String? publicIpError;
    bool isFromCache = false;

    if (!forceRefresh && cached != null) {
      final cachedSignature = cached['signature'] as String?;
      final cachedIp = cached['publicIp'] as String?;
      final cachedTimestamp = cached['timestamp'] as int? ?? 0;
      final cacheAgeHours =
          (DateTime.now().millisecondsSinceEpoch - cachedTimestamp) /
          (1000 * 60 * 60);

      if (cachedSignature == networkSignature &&
          cachedIp != null &&
          cachedIp.isNotEmpty &&
          cacheAgeHours < 24) {
        publicIp = cachedIp;
        publicIsp = cached['publicIsp'] as String? ?? '';
        publicLocation = cached['publicLocation'] as String? ?? '';
        isFromCache = true;
      }
    }

    // 5. Query API if not cached or cache invalid/expired
    if (publicIp.isEmpty && !isTest) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final request = await client.getUrl(
          Uri.parse('https://ipinfo.io/json'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          publicIp = json['ip']?.toString() ?? '';
          publicIsp = json['org']?.toString() ?? '';
          final city = json['city']?.toString() ?? '';
          final country = json['country']?.toString() ?? '';
          if (city.isNotEmpty && country.isNotEmpty) {
            publicLocation = '$city, $country';
          } else {
            publicLocation = country.isNotEmpty ? country : city;
          }

          // Cache result linked to the network signature
          _saveCache({
            'signature': networkSignature,
            'publicIp': publicIp,
            'publicIsp': publicIsp,
            'publicLocation': publicLocation,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }, isTest: isTest);
        }
        client.close();
      } catch (e) {
        publicIpError = 'Could not fetch public IP (offline / timeout)';
      }
    }

    return NetworkDiagnosticsData(
      hostname: hostname,
      osVersion: osVersion,
      interfaces: interfaces,
      defaultGateway: defaultGateway,
      dnsServers: dnsServers,
      publicIp: publicIp,
      publicIsp: publicIsp,
      publicLocation: publicLocation,
      isFromCache: isFromCache,
      publicIpError: publicIpError,
      scannedAt: DateTime.now(),
    );
  }
}

Future<void> showNetworkInfoDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => const _NetworkInfoDialogContent(),
  );
}

class _NetworkInfoDialogContent extends StatefulWidget {
  const _NetworkInfoDialogContent();

  @override
  State<_NetworkInfoDialogContent> createState() =>
      _NetworkInfoDialogContentState();
}

class _NetworkInfoDialogContentState extends State<_NetworkInfoDialogContent> {
  NetworkDiagnosticsData? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch(forceRefresh: false);
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    final data = await NetworkDiagnosticsService.scan(
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    if (_data == null) return;
    Clipboard.setData(ClipboardData(text: _data!.toMarkdown()));
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Copied'),
        content: const Text('Network diagnostics copied to clipboard'),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(FluentIcons.network_tower, color: colors.accent, size: 22),
              const SizedBox(width: 10),
              Text('Network Diagnostics & System Info', style: type.title),
            ],
          ),
          IconButton(
            icon: Icon(
              FluentIcons.chrome_close,
              size: 14,
              color: colors.textSecondary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ProgressRing(),
                  const SizedBox(height: 12),
                  Text(
                    'Scanning network interfaces & routing...',
                    style: type.body,
                  ),
                ],
              ),
            )
          : _data == null
          ? Center(child: Text('Failed to load network info', style: type.body))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Host & Public IP Section
                  _SectionHeader(
                    title: 'Internet & Host Details',
                    icon: FluentIcons.globe,
                    trailing: _data!.isFromCache
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.panelBackgroundAlt,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: colors.borderColor),
                            ),
                            child: Text(
                              'Cached',
                              style: type.caption.copyWith(
                                color: colors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          )
                        : null,
                    colors: colors,
                    type: type,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.panelBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderColor),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          label: 'Public IP',
                          value: _data!.publicIp.isNotEmpty
                              ? _data!.publicIp
                              : (_data!.publicIpError ?? 'Unavailable'),
                          isHighlighted: true,
                          colors: colors,
                          type: type,
                        ),
                        if (_data!.publicIsp.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: 'ISP / ASN',
                            value: _data!.publicIsp,
                            colors: colors,
                            type: type,
                          ),
                        ],
                        if (_data!.publicLocation.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: 'Location',
                            value: _data!.publicLocation,
                            colors: colors,
                            type: type,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _InfoRow(
                          label: 'Local Hostname',
                          value: _data!.hostname,
                          colors: colors,
                          type: type,
                        ),
                        const SizedBox(height: 6),
                        _InfoRow(
                          label: 'OS Version',
                          value: _data!.osVersion,
                          colors: colors,
                          type: type,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Gateway & DNS
                  _SectionHeader(
                    title: 'Routing & DNS',
                    icon: FluentIcons.server,
                    colors: colors,
                    type: type,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.panelBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderColor),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          label: 'Default Gateway',
                          value: _data!.defaultGateway.isNotEmpty
                              ? _data!.defaultGateway
                              : 'Not detected',
                          colors: colors,
                          type: type,
                        ),
                        const SizedBox(height: 6),
                        _InfoRow(
                          label: 'DNS Servers',
                          value: _data!.dnsServers.isNotEmpty
                              ? _data!.dnsServers.join(', ')
                              : 'Default system resolver',
                          colors: colors,
                          type: type,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Network Interfaces
                  _SectionHeader(
                    title:
                        'Local Network Interfaces (${_data!.interfaces.length})',
                    icon: FluentIcons.network_tower,
                    colors: colors,
                    type: type,
                  ),
                  const SizedBox(height: 6),
                  for (final iface in _data!.interfaces)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
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
                                Icon(
                                  iface.name.startsWith('lo')
                                      ? FluentIcons.repeat_all
                                      : (iface.name.startsWith('en') ||
                                            iface.name.startsWith('eth') ||
                                            iface.name.startsWith('wlan'))
                                      ? FluentIcons.wifi
                                      : FluentIcons.plug_connected,
                                  size: 14,
                                  color: colors.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(iface.name, style: type.bodyStrong),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (iface.ipv4Addresses.isNotEmpty)
                              _InfoRow(
                                label: 'IPv4',
                                value: iface.ipv4Addresses.join(', '),
                                colors: colors,
                                type: type,
                              ),
                            if (iface.ipv6Addresses.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              _InfoRow(
                                label: 'IPv6',
                                value: iface.ipv6Addresses.join(', '),
                                colors: colors,
                                type: type,
                              ),
                            ],
                            if (iface.ipv4Addresses.isEmpty &&
                                iface.ipv6Addresses.isEmpty)
                              Text(
                                'Inactive / No IP assigned',
                                style: type.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        Button(
          onPressed: _isLoading ? null : () => _fetch(forceRefresh: true),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.refresh, size: 14),
              SizedBox(width: 6),
              Text('Refresh Scan'),
            ],
          ),
        ),
        FilledButton(
          onPressed: _data == null ? null : _copyToClipboard,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.copy, size: 14),
              SizedBox(width: 6),
              Text('Copy Diagnostics'),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
    required this.colors,
    required this.type,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(title, style: type.subtitle),
          ],
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isHighlighted = false,
    required this.colors,
    required this.type,
  });

  final String label;
  final String value;
  final bool isHighlighted;
  final AppColors colors;
  final AppTypography type;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: type.caption.copyWith(color: colors.textSecondary)),
        const SizedBox(width: 12),
        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.right,
            style: type.body.copyWith(
              color: isHighlighted ? colors.accent : colors.textPrimary,
              fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
