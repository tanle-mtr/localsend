import 'package:flutter/services.dart';

/// 与安卓原生 RFCOMM 服务端通信的桥。
///
/// - MethodChannel：控制服务端启停、能力查询。
/// - EventChannel：原生把 RFCOMM 收到的原始字节流实时回传给 Dart，
///   Dart 侧用 [BluetoothFrameReader] 解析协议并落盘（职责分离，原生只做"搬字节"）。
///
/// iOS 上该插件无实现，`isSupported` 返回 false，UI 会提示"蓝牙文件传输暂不支持 iOS"。
const _methodChannel = MethodChannel('localsend_bluetooth/methods');
const _eventChannel = EventChannel('localsend_bluetooth/events');

class BluetoothNative {
  BluetoothNative._();

  /// 当前平台是否支持蓝牙文件传输（安卓 true，iOS false）。
  static Future<bool> isSupported() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 启动原生 RFCOMM 监听，等待对端连接。
  static Future<void> startServer() => _methodChannel.invokeMethod('startServer');

  /// 停止监听并关闭连接。
  static Future<void> stopServer() => _methodChannel.invokeMethod('stopServer');

  /// 原生回传的 RFCOMM 原始字节流。
  static Stream<Uint8List> receiveBytes() =>
      _eventChannel.receiveBroadcastStream().where((e) => e is Uint8List).cast<Uint8List>();
}
