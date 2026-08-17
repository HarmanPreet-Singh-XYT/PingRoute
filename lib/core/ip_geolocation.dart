import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// True for addresses that have no meaningful public geolocation: RFC1918
/// private ranges, loopback, link-local, CGNAT (RFC6598), and their IPv6
/// equivalents. Looking these up against a public IP database would just
/// return the database's own location or an error.
bool isPrivateIp(String ip) {
  final address = InternetAddress.tryParse(ip);
  if (address == null) return true;

  if (address.isLoopback || address.isLinkLocal) return true;

  if (address.type == InternetAddressType.IPv4) {
    final parts = address.rawAddress;
    final a = parts[0], b = parts[1];
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 (CGNAT)
    if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
    if (a == 127) return true; // 127.0.0.0/8 loopback
    return false;
  }

  // IPv6 unique local addresses (fc00::/7).
  final first = address.rawAddress[0];
  if (first >= 0xfc && first <= 0xfd) return true;

  return false;
}

/// Common ISO 3166-1 alpha-2 codes expanded to full names. ipinfo.io's
/// free/no-auth tier only returns the country code, not the full name, so
/// this covers the common cases and falls back to the raw code otherwise.
const Map<String, String> _countryNames = {
  'US': 'United States', 'CA': 'Canada', 'GB': 'United Kingdom', 'DE': 'Germany',
  'FR': 'France', 'IT': 'Italy', 'ES': 'Spain', 'NL': 'Netherlands', 'BE': 'Belgium',
  'CH': 'Switzerland', 'AT': 'Austria', 'SE': 'Sweden', 'NO': 'Norway', 'DK': 'Denmark',
  'FI': 'Finland', 'PL': 'Poland', 'PT': 'Portugal', 'IE': 'Ireland', 'GR': 'Greece',
  'RU': 'Russia', 'UA': 'Ukraine', 'TR': 'Turkey', 'IN': 'India', 'CN': 'China',
  'JP': 'Japan', 'KR': 'South Korea', 'SG': 'Singapore', 'HK': 'Hong Kong',
  'TW': 'Taiwan', 'AU': 'Australia', 'NZ': 'New Zealand', 'BR': 'Brazil',
  'MX': 'Mexico', 'AR': 'Argentina', 'CL': 'Chile', 'ZA': 'South Africa',
  'EG': 'Egypt', 'AE': 'United Arab Emirates', 'SA': 'Saudi Arabia', 'IL': 'Israel',
  'ID': 'Indonesia', 'MY': 'Malaysia', 'TH': 'Thailand', 'VN': 'Vietnam',
  'PH': 'Philippines', 'PK': 'Pakistan', 'BD': 'Bangladesh', 'RO': 'Romania',
  'CZ': 'Czechia', 'HU': 'Hungary', 'BG': 'Bulgaria', 'HR': 'Croatia', 'RS': 'Serbia',
  'IS': 'Iceland', 'LU': 'Luxembourg',
};

class IpGeoInfo {
  final String ip;
  final String hostname;
  final String asn;
  final String asOrg;
  final String city;
  final String region;
  final String countryCode;
  final String postal;
  final double? latitude;
  final double? longitude;
  final String timezone;
  final bool anycast;

  const IpGeoInfo({
    required this.ip,
    required this.hostname,
    required this.asn,
    required this.asOrg,
    required this.city,
    required this.region,
    required this.countryCode,
    required this.postal,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.anycast,
  });

  String get countryName => _countryNames[countryCode] ?? countryCode;

  String get location {
    final parts = [city, region, countryCode].where((p) => p.isNotEmpty);
    return parts.join(', ');
  }

  bool get hasCoordinates => latitude != null && longitude != null;

  String get coordinatesLabel {
    if (!hasCoordinates) return '';
    final latDir = latitude! >= 0 ? 'N' : 'S';
    final lonDir = longitude! >= 0 ? 'E' : 'W';
    return '${latitude!.abs().toStringAsFixed(4)} $latDir, ${longitude!.abs().toStringAsFixed(4)} $lonDir';
  }
}

/// Looks up public geolocation/ISP info for a single IP via ipinfo.io,
/// mirroring the API [NetworkDiagnosticsService] already uses for the
/// user's own public IP. Results are cached in memory for the process
/// lifetime since hop IPs are looked up repeatedly (same hop reappears
/// across pings/tabs) and this data doesn't change during a session.
class IpGeoService {
  IpGeoService._();

  static const _cacheTtl = Duration(hours: 1);
  static const _maxCacheEntries = 500;

  static final Map<String, (IpGeoInfo, DateTime)> _cache = {};

  static Future<IpGeoInfo> lookup(String ip, {bool forceRefresh = false}) async {
    if (isPrivateIp(ip)) {
      throw const IpGeoPrivateAddressException();
    }

    if (!forceRefresh) {
      final cached = _cache[ip];
      if (cached != null && DateTime.now().difference(cached.$2) < _cacheTtl) {
        return cached.$1;
      }
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse('https://ipinfo.io/$ip/json'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw IpGeoLookupException('Lookup failed (HTTP ${response.statusCode})');
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['bogon'] == true) {
        throw const IpGeoPrivateAddressException();
      }

      final org = json['org']?.toString() ?? '';
      final asnMatch = RegExp(r'^(AS\d+)\s*(.*)$').firstMatch(org);
      final asn = asnMatch?.group(1) ?? '';
      final asOrg = asnMatch?.group(2) ?? org;

      final loc = json['loc']?.toString() ?? '';
      final locParts = loc.split(',');
      final lat = locParts.length == 2 ? double.tryParse(locParts[0]) : null;
      final lon = locParts.length == 2 ? double.tryParse(locParts[1]) : null;

      final info = IpGeoInfo(
        ip: json['ip']?.toString() ?? ip,
        hostname: json['hostname']?.toString() ?? '',
        asn: asn,
        asOrg: asOrg,
        city: json['city']?.toString() ?? '',
        region: json['region']?.toString() ?? '',
        countryCode: json['country']?.toString() ?? '',
        postal: json['postal']?.toString() ?? '',
        latitude: lat,
        longitude: lon,
        timezone: json['timezone']?.toString() ?? '',
        anycast: json['anycast'] == true,
      );
      if (_cache.length >= _maxCacheEntries && !_cache.containsKey(ip)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[ip] = (info, DateTime.now());
      return info;
    } on IpGeoLookupException {
      rethrow;
    } on IpGeoPrivateAddressException {
      rethrow;
    } catch (e) {
      throw IpGeoLookupException('Could not fetch IP info (offline / timeout)');
    } finally {
      client.close();
    }
  }
}

class IpGeoLookupException implements Exception {
  final String message;
  const IpGeoLookupException(this.message);
  @override
  String toString() => message;
}

class IpGeoPrivateAddressException implements Exception {
  const IpGeoPrivateAddressException();
  @override
  String toString() => 'Private/local addresses have no public geolocation.';
}
