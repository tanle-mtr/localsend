import 'dart:convert';
import 'dart:typed_data';

/// 蓝牙无网互传的轻量线协议。
///
/// 在 RFCOMM 串口通道之上，所有数据都以"帧"为单位传输：
///   [4B magic "LSBT"][1B version][1B frameType][4B big-endian payloadLength][payload]
///
/// 一次会话的消息序列：
///   发送端 → HELLO → (对每个文件：FILE_META → FILE_CHUNK×N → FILE_END) → BYE
///   接收端据此落盘。
///
/// 该协议与 LocalSend 的 HTTP 协议完全独立：蓝牙 peers 之间只通过蓝牙互传，
/// 不依赖任何网络（这正是"无网互传"的含义）。

class BluetoothProtocol {
  static const String magic = 'LSBT';
  static const int version = 1;

  /// 帧类型。
  static const int frameHello = 0x01;
  static const int frameFileMeta = 0x02;
  static const int frameFileChunk = 0x03;
  static const int frameFileEnd = 0x04;
  static const int frameBye = 0x05;

  static const int headerLength = 4 + 1 + 1 + 4; // magic + version + type + length

  BluetoothProtocol._();
}

/// 一个已解析的协议帧。
class BluetoothFrame {
  final int type;
  final Uint8List payload;

  const BluetoothFrame(this.type, this.payload);

  Map<String, dynamic> get json => jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
}

/// 把一帧编码为可写入 socket 的字节。
Uint8List encodeFrame(int type, Uint8List payload) {
  final out = ByteData(BluetoothProtocol.headerLength + payload.length);
  final magicBytes = Uint8List.fromList(utf8.encode(BluetoothProtocol.magic));
  out.setUint8(0, magicBytes[0]);
  out.setUint8(1, magicBytes[1]);
  out.setUint8(2, magicBytes[2]);
  out.setUint8(3, magicBytes[3]);
  out.setUint8(4, BluetoothProtocol.version);
  out.setUint8(5, type);
  out.setUint32(6, payload.length, Endian.big);
  out.buffer.asUint8List().setRange(BluetoothProtocol.headerLength, BluetoothProtocol.headerLength + payload.length, payload);
  return out.buffer.asUint8List();
}

/// 流式的帧解析器：把任意到达的字节块拼成完整帧。
///
/// 由于 RFCOMM 是裸字节流，一次 `read` 可能只到半个帧、或一次到多个帧，
/// 这里维护一个内部缓冲，调用 [consume] 返回本次能解析出的完整帧，余下部分留存。
class BluetoothFrameReader {
  Uint8List _buffer = Uint8List(0);

  /// 喂入新到达的字节，返回解析出的完整帧（可能为空、一个或多个）。
  List<BluetoothFrame> consume(Uint8List chunk) {
    final merged = Uint8List(_buffer.length + chunk.length);
    merged.setRange(0, _buffer.length, _buffer);
    merged.setRange(_buffer.length, merged.length, chunk);

    final frames = <BluetoothFrame>[];
    var offset = 0;
    while (offset + BluetoothProtocol.headerLength <= merged.length) {
      // 校验魔术字。
      if (utf8.decode(merged.sublist(offset, offset + 4)) != BluetoothProtocol.magic) {
        // 协议不同步：丢弃整个缓冲，避免死循环。
        _buffer = Uint8List(0);
        return frames;
      }
      final version = merged[offset + 4];
      final type = merged[offset + 5];
      final length = ByteData.sublistView(merged, offset + 6, offset + 10).getUint32(0, Endian.big);
      if (version != BluetoothProtocol.version) {
        _buffer = Uint8List(0);
        return frames;
      }
      if (offset + BluetoothProtocol.headerLength + length > merged.length) {
        break; // 帧尚未到齐，等待更多字节。
      }
      final payload = merged.sublist(
        offset + BluetoothProtocol.headerLength,
        offset + BluetoothProtocol.headerLength + length,
      );
      frames.add(BluetoothFrame(type, payload));
      offset += BluetoothProtocol.headerLength + length;
    }
    _buffer = merged.sublist(offset);
    return frames;
  }
}
