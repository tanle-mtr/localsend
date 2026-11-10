import 'package:localsend_app/util/qr/connect_payload.dart';
import 'package:test/test.dart';

void main() {
  group('buildConnectQrData / tryParseConnectQr', () {
    test('round-trips ip, port and https flag', () {
      final data = buildConnectQrData(ip: '192.168.1.42', port: 53317, https: false, alias: 'My Phone');
      final parsed = tryParseConnectQr(data);
      expect(parsed, isNotNull);
      expect(parsed!.ip, '192.168.1.42');
      expect(parsed.port, 53317);
      expect(parsed.https, isFalse);
    });

    test('parses https=1 as true', () {
      final data = buildConnectQrData(ip: '10.0.0.5', port: 443, https: true);
      final parsed = tryParseConnectQr(data);
      expect(parsed, isNotNull);
      expect(parsed!.https, isTrue);
      expect(parsed.port, 443);
    });

    test('round-trips the optional hotspot SSID', () {
      final data = buildConnectQrData(
        ip: '192.168.43.1',
        port: 53317,
        https: false,
        alias: 'My Phone',
        ssid: 'MyPhone-Hotspot',
      );
      final parsed = tryParseConnectQr(data);
      expect(parsed, isNotNull);
      expect(parsed!.ssid, 'MyPhone-Hotspot');
    });

    test('omits ssid when not provided', () {
      final data = buildConnectQrData(ip: '192.168.1.2', port: 53317, https: false);
      expect(data.contains('ssid'), isFalse);
      final parsed = tryParseConnectQr(data);
      expect(parsed!.ssid, isNull);
    });

    test('returns null for unrelated text', () {
      expect(tryParseConnectQr('https://localsend.org'), isNull);
      expect(tryParseConnectQr('hello world'), isNull);
      expect(tryParseConnectQr(null), isNull);
      expect(tryParseConnectQr(''), isNull);
    });

    test('returns null for malformed localsendqr uri', () {
      // correct scheme but missing port
      expect(tryParseConnectQr('localsendqr://c?ip=192.168.1.1'), isNull);
      // correct scheme/host but out-of-range port
      expect(tryParseConnectQr('localsendqr://c?ip=192.168.1.1&port=70000'), isNull);
      // wrong host
      expect(tryParseConnectQr('localsendqr://x?ip=192.168.1.1&port=53317'), isNull);
    });
  });
}
