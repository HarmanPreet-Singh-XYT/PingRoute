import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/ip_geolocation.dart';
import '../core/theme.dart';
import '../widgets/shared_widgets.dart';

void showIpInfoDialog(BuildContext context, String ip, {String? name}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (context) => _IpInfoDialogContent(ip: ip, name: name),
  );
}

class _IpInfoDialogContent extends StatefulWidget {
  const _IpInfoDialogContent({required this.ip, this.name});

  final String ip;
  final String? name;

  @override
  State<_IpInfoDialogContent> createState() => _IpInfoDialogContentState();
}

class _IpInfoDialogContentState extends State<_IpInfoDialogContent> {
  IpGeoInfo? _info;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final info = await IpGeoService.lookup(widget.ip, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _info = info;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final type = appTypography(context);
    final label = (widget.name?.isNotEmpty ?? false) ? widget.name! : widget.ip;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
      title: Row(
        children: [
          Icon(FluentIcons.globe, size: 20, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'IP Info — $label',
              style: type.title.copyWith(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Refresh (bypass cache)',
            child: IconButton(
              icon: Icon(FluentIcons.refresh, size: 16, color: colors.textSecondary),
              onPressed: _isLoading ? null : () => _fetch(forceRefresh: true),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: ProgressRing()),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(FluentIcons.warning, size: 16, color: colors.latencyWarn),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: type.body.copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_info!.hasCoordinates) ...[
                          _IpLocationMap(info: _info!, colors: colors),
                          const SizedBox(height: 12),
                        ],
                        StatTable(
                          colors: colors,
                          type: type,
                          rows: [
                            ('IP Address', _info!.ip),
                            if (_info!.hostname.isNotEmpty) ('Hostname', _info!.hostname),
                            if (_info!.asn.isNotEmpty) ('ASN', _info!.asn),
                            if (_info!.asOrg.isNotEmpty) ('ISP / Org', _info!.asOrg),
                            ('Anycast', _info!.anycast ? 'Yes' : 'No'),
                            if (_info!.city.isNotEmpty) ('City', _info!.city),
                            if (_info!.region.isNotEmpty) ('Region', _info!.region),
                            if (_info!.countryCode.isNotEmpty) ('Country', _info!.countryName),
                            if (_info!.postal.isNotEmpty) ('Postal Code', _info!.postal),
                            if (_info!.coordinatesLabel.isNotEmpty)
                              ('Coordinates', _info!.coordinatesLabel),
                            if (_info!.timezone.isNotEmpty) ('Timezone', _info!.timezone),
                          ],
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        if (_error != null)
          Button(
            onPressed: () => _fetch(forceRefresh: true),
            child: const Text('Retry'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Embedded OpenStreetMap view centered on the looked-up IP's coordinates,
/// with a single marker. No API key required (OSM's public tile server),
/// unlike Google Maps.
class _IpLocationMap extends StatelessWidget {
  const _IpLocationMap({required this.info, required this.colors});

  final IpGeoInfo info;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final center = LatLng(info.latitude!, info.longitude!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 220,
        decoration: BoxDecoration(border: Border.all(color: colors.borderColor)),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 9,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.harmanita.pingroute',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 32,
                  height: 32,
                  child: Icon(FluentIcons.map_pin, color: colors.accent, size: 32),
                ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
