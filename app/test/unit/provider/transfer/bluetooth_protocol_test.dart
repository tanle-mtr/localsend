import 'dart:convert';
import 'dart:typed_data';

import 'package:localsend_app/provider/transfer/bluetooth/bluetooth_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('encodeFrame', () {
    test('writes magic, version, type and big-endian length', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final frame = encodeFrame(BluetoothProtocol.frameFileMeta, payload);

      // magic "LSBT" (4) + version (1) + type (1) + length (4) = 10 header bytes
      expect(frame.length, equals(BluetoothProtocol.headerLength + payload.length));
      expect(String.fromCharCodes(frame.sublist(0, 4)), equals('LSBT'));
      expect(frame[4], equals(BluetoothProtocol.version));
      expect(frame[5], equals(BluetoothProtocol.frameFileMeta));
      final len = ByteData.sublistView(frame, 6, 10).getUint32(0, Endian.big);
      expect(len, equals(payload.length));
      expect(frame.sublist(10), equals(payload));
    });
  });

  group('BluetoothFrameReader', () {
    test('parses a complete frame in one chunk', () {
      final reader = BluetoothFrameReader();
      final frames = reader.consume(
        encodeFrame(BluetoothProtocol.frameHello, utf8.encode('{"total":3}')),
      );
      expect(frames, hasLength(1));
      expect(frames.first.type, equals(BluetoothProtocol.frameHello));
      expect(frames.first.json['total'], equals(3));
    });

    test('reassembles a frame split across multiple chunks', () {
      final reader = BluetoothFrameReader();
      final raw = encodeFrame(
        BluetoothProtocol.frameFileChunk,
        Uint8List.fromList(List.generate(20, (i) => i)),
      );

      // Feed one byte at a time to stress the buffer reassembly.
      final all = <BluetoothFrame>[];
      for (var i = 0; i < raw.length; i++) {
        all.addAll(reader.consume(Uint8List.fromList([raw[i]])));
      }
      expect(all, hasLength(1));
      expect(all.first.type, equals(BluetoothProtocol.frameFileChunk));
      expect(all.first.payload, equals(raw.sublist(10)));
    });

    test('parses multiple frames delivered together', () {
      final reader = BluetoothFrameReader();
      final a = encodeFrame(BluetoothProtocol.frameFileMeta, utf8.encode('{}'));
      final b = encodeFrame(BluetoothProtocol.frameFileEnd, utf8.encode('{"id":0}'));
      final merged = Uint8List(a.length + b.length);
      merged.setRange(0, a.length, a);
      merged.setRange(a.length, merged.length, b);

      final frames = reader.consume(merged);
      expect(frames, hasLength(2));
      expect(frames[0].type, equals(BluetoothProtocol.frameFileMeta));
      expect(frames[1].type, equals(BluetoothProtocol.frameFileEnd));
      expect(frames[1].json['id'], equals(0));
    });

    test('drops buffer on protocol desync', () {
      final reader = BluetoothFrameReader();
      // Corrupt magic followed by a valid frame.
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 0, 0, 0, 0, 0, 0]);
      final valid = encodeFrame(BluetoothProtocol.frameBye, Uint8List(0));
      final first = reader.consume(corrupt);
      expect(first, isEmpty);
      final second = reader.consume(valid);
      expect(second, hasLength(1));
      expect(second.first.type, equals(BluetoothProtocol.frameBye));
    });
  });
}
