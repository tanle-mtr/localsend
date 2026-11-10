import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:localsend_app/model/bluetooth/bluetooth_device.dart';
import 'package:localsend_app/provider/transfer/bluetooth/bluetooth_protocol.dart';
import 'package:localsend_app/util/native/bluetooth/bluetooth_channel.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _logger = Logger('BluetoothTransfer');

/// 单个待发送的蓝牙文件。字节延迟读取，避免大文件一次性读入内存。
class BluetoothSendItem {
  final String name;
  final int size;
  final Future<Uint8List> Function() read;

  const BluetoothSendItem({required this.name, required this.size, required this.read});
}

/// 蓝牙无网互传的传输层。
///
/// - 发现 / 连接 / 发送：使用 [FlutterBluetoothSerial]（经典蓝牙 RFCOMM 客户端，安卓可用）。
/// - 接收：启动原生 RFCOMM 服务端（见 MainActivity.kt），原生把字节流回传，
///   这里用 [BluetoothFrameReader] 解析协议并落盘。
///
/// iOS 不支持第三方 App 的蓝牙文件传输，所有方法在 iOS 上会抛出 [UnsupportedError]，
/// 由 UI 捕获并提示。
class BluetoothTransferService {
  static const int chunkSize = 32 * 1024; // 32 KiB 每片

  BluetoothTransferService._();

  /// 当前平台是否支持（安卓 true）。
  static Future<bool> isSupported() => BluetoothNative.isSupported();

  /// 开启蓝牙适配器（若未开启则请求授权）。返回是否成功。
  static Future<bool> ensureEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final state = await FlutterBluetoothSerial.instance.state;
      if (state == BluetoothState.STATE_ON) return true;
      return await FlutterBluetoothSerial.instance.requestEnable() ?? false;
    } catch (e) {
      _logger.warning('开启蓝牙失败', e);
      return false;
    }
  }

  /// 开始发现附近的蓝牙设备。iOS 返回空流。
  static Stream<BluetoothPeer> discover() {
    if (!Platform.isAndroid) return Stream<BluetoothPeer>.empty();
    return FlutterBluetoothSerial.instance
        .startDiscovery()
        .map((result) {
          final device = result.device;
          return BluetoothPeer(
            address: device.address,
            name: device.name ?? device.address,
            bonded: device.bondState == BluetoothBondState.bonded,
          );
        })
        .distinct();
  }

  static Future<void> cancelDiscovery() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (_) {}
  }

  /// 作为客户端，连接指定地址并发送全部文件。
  static Future<void> sendFiles({
    required String address,
    required List<BluetoothSendItem> items,
    required void Function(int fileIndex, int totalFiles, double progress) onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('蓝牙文件传输仅支持 Android');
    }
    final connection = await BluetoothConnection.toAddress(address);
    try {
      final out = connection.output;
      out.add(
        encodeFrame(
          BluetoothProtocol.frameHello,
          utf8.encode(jsonEncode({'version': BluetoothProtocol.version, 'total': items.length})),
        ),
      );
      await out.allSent;

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final bytes = await item.read();
        out.add(
          encodeFrame(
            BluetoothProtocol.frameFileMeta,
            utf8.encode(jsonEncode({'id': i, 'name': item.name, 'size': bytes.length})),
          ),
        );
        await out.allSent;

        var offset = 0;
        while (offset < bytes.length) {
          final end = min(offset + chunkSize, bytes.length);
          out.add(encodeFrame(BluetoothProtocol.frameFileChunk, bytes.sublist(offset, end)));
          offset = end;
          onProgress(i, items.length, bytes.isEmpty ? 1 : offset / bytes.length);
          if (offset % (chunkSize * 16) == 0) await out.allSent;
        }
        await out.allSent;
        out.add(encodeFrame(BluetoothProtocol.frameFileEnd, utf8.encode(jsonEncode({'id': i}))));
        await out.allSent;
      }

      out.add(encodeFrame(BluetoothProtocol.frameBye, Uint8List(0)));
      await out.allSent;
    } finally {
      try {
        await connection.close();
      } catch (_) {}
    }
  }

  /// 启动接收：开启原生服务端，解析回传的字节流并落盘。
  /// 收到的文件保存在 `<外部存储>/LocalSend/Bluetooth/` 下。
  static Future<StreamSubscription<Uint8List>> startReceive({
    required void Function() onConnected,
    required void Function(String fileName, int fileIndex, int total, double progress) onProgress,
    required void Function(String savedPath) onFileSaved,
    required void Function(String error) onError,
  }) async {
    if (!Platform.isAndroid) {
      onError('蓝牙文件传输暂不支持 iOS');
      return Stream<Uint8List>.empty().listen((_) {});
    }

    final dir = await _receiveDir();
    await dir.create(recursive: true);
    await BluetoothNative.startServer();

    final reader = BluetoothFrameReader();
    File? currentFile;
    String? currentPath;
    int currentTotal = 0;
    int received = 0;
    int fileIndex = 0;
    int totalFiles = 0;

    final subscription = BluetoothNative.receiveBytes().listen(
      (chunk) {
        try {
          final frames = reader.consume(chunk);
          for (final frame in frames) {
            switch (frame.type) {
              case BluetoothProtocol.frameHello:
                totalFiles = frame.json['total'] as int? ?? totalFiles;
                onConnected();
                break;
              case BluetoothProtocol.frameFileMeta:
                final meta = frame.json;
                totalFiles = meta['total'] as int? ?? totalFiles;
                final name = meta['name'] as String;
                currentTotal = meta['size'] as int;
                received = 0;
                currentPath = p.join(dir.path, _safeName(name));
                currentFile = File(currentPath!);
                fileIndex++;
                onProgress(name, fileIndex, totalFiles, 0);
                break;
              case BluetoothProtocol.frameFileChunk:
                if (currentFile != null) {
                  currentFile!.writeAsBytesSync(frame.payload, mode: FileMode.append);
                  received += frame.payload.length;
                  onProgress(p.basename(currentPath!), fileIndex, totalFiles, currentTotal == 0 ? 1 : received / currentTotal);
                }
                break;
              case BluetoothProtocol.frameFileEnd:
                // 通过 writeAsBytesSync 写入时文件已即写即关，无需显式 close。
                if (currentPath != null) onFileSaved(currentPath!);
                currentFile = null;
                currentPath = null;
                break;
              case BluetoothProtocol.frameBye:
                unawaited(BluetoothNative.stopServer());
                break;
            }
          }
        } catch (e) {
          _logger.warning('蓝牙接收解析失败', e);
          onError(e.toString());
        }
      },
      onError: (e) {
        _logger.warning('蓝牙接收流错误', e);
        onError(e.toString());
      },
    );
    return subscription;
  }

  static Future<void> stopReceive() => BluetoothNative.stopServer();

  static Future<Directory> _receiveDir() async {
    final base = await getExternalStorageDirectory();
    return Directory(p.join(base?.path ?? (await getTemporaryDirectory()).path, 'LocalSend', 'Bluetooth'));
  }

  /// 防止路径穿越：只保留文件名本身。
  static String _safeName(String name) {
    final base = p.basename(name);
    return base.isEmpty ? 'bluetooth_file' : base;
  }
}
