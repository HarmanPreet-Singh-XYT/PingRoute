/// Well-known service names for remote ports, so the UI can say "HTTPS"
/// instead of making users decode `443`.
const Map<int, String> _tcpServices = {
  20: 'FTP data',
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  25: 'SMTP',
  53: 'DNS',
  80: 'HTTP',
  110: 'POP3',
  123: 'NTP',
  143: 'IMAP',
  389: 'LDAP',
  443: 'HTTPS',
  445: 'SMB',
  465: 'SMTPS',
  587: 'SMTP',
  636: 'LDAPS',
  853: 'DNS over TLS',
  993: 'IMAPS',
  995: 'POP3S',
  1433: 'SQL Server',
  1883: 'MQTT',
  3306: 'MySQL',
  3389: 'RDP',
  3478: 'STUN',
  5222: 'XMPP',
  5223: 'Apple Push',
  5228: 'Google Push',
  5432: 'PostgreSQL',
  5671: 'AMQPS',
  5672: 'AMQP',
  6379: 'Redis',
  8080: 'HTTP alt',
  8443: 'HTTPS alt',
  8883: 'MQTT TLS',
  9200: 'Elasticsearch',
  27017: 'MongoDB',
};

/// Returns a friendly name for [port], or null when it isn't well known.
/// UDP/443 is QUIC (HTTP/3), which is by far its most common use.
String? serviceNameForPort(int port, {String protocol = 'TCP'}) {
  final udp = protocol.toUpperCase() == 'UDP';
  if (udp) {
    if (port == 443) return 'QUIC';
    if (port == 53) return 'DNS';
    if (port == 123) return 'NTP';
    if (port == 3478) return 'STUN';
    return null;
  }
  return _tcpServices[port];
}

/// Label such as `HTTPS` or, when unknown, `port 9999`.
String serviceLabel(int port, {String protocol = 'TCP'}) =>
    serviceNameForPort(port, protocol: protocol) ?? 'port $port';
