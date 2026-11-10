/// Connection info encoded into a QR code so a sender can reach the receiver
/// without relying on mDNS / network discovery.
///
/// This is the backbone of the "扫码互传" (scan-to-transfer) feature: the
/// receiver displays a QR containing its local HTTP endpoint, and the sender
/// scans it, then performs the normal LocalSend discovery handshake over the
/// local network (or a personal hotspot). Works fully offline and on every
/// platform LocalSend already supports — including iOS, where classic
/// Bluetooth file transfer is impossible.
///
/// Wire format (a plain URI, easy to parse from any QR scanner):
///   localsendqr://c?ip=192.168.x.x&port=53317&https=0&alias=Phone
class ParsedConnectQr {
  final String ip;
  final int port;
  final bool https;
  final String? ssid;

  const ParsedConnectQr({
    required this.ip,
    required this.port,
    required this.https,
    this.ssid,
  });
}

const String _qrScheme = 'localsendqr';
const String _qrHost = 'c';

/// Builds the string that should be rendered as a QR code by the receiver.
///
/// [ssid] is optional: when the receiver is sharing its own personal hotspot,
/// embedding its SSID lets the sender know which network to join for a truly
/// network-less transfer (see the "一键热点引导" enhancement).
String buildConnectQrData({
  required String ip,
  required int port,
  required bool https,
  String? alias,
  String? ssid,
}) {
  return Uri(
    scheme: _qrScheme,
    host: _qrHost,
    queryParameters: <String, String>{
      'ip': ip,
      'port': port.toString(),
      'https': https ? '1' : '0',
      if (alias != null && alias.isNotEmpty) 'alias': alias,
      if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
    },
  ).toString();
}

/// Parses a scanned QR string. Returns `null` when it is not a LocalSend
/// connection code, so callers can show a "not a LocalSend QR" message.
ParsedConnectQr? tryParseConnectQr(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme != _qrScheme || uri.host != _qrHost) return null;

  final ip = uri.queryParameters['ip'];
  final portStr = uri.queryParameters['port'];
  final httpsStr = uri.queryParameters['https'];
  if (ip == null || ip.isEmpty || portStr == null) return null;

  final port = int.tryParse(portStr);
  if (port == null || port <= 0 || port > 65535) return null;

  final ssid = uri.queryParameters['ssid'];
  return ParsedConnectQr(
    ip: ip,
    port: port,
    https: httpsStr == '1',
    ssid: (ssid != null && ssid.isNotEmpty) ? ssid : null,
  );
}
