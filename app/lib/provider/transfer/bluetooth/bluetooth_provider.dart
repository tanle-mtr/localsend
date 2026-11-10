import 'dart:async';

import 'package:localsend_app/model/bluetooth/bluetooth_device.dart';
import 'package:localsend_app/provider/transfer/bluetooth/bluetooth_transfer_service.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 蓝牙模块的运行时状态。
class BluetoothState {
  /// 当前平台是否支持蓝牙文件传输（安卓 true）。
  final bool supported;

  /// 蓝牙适配器是否已开启。
  final bool enabled;

  /// 是否正在扫描。
  final bool discovering;

  /// 已发现的设备。
  final List<BluetoothPeer> peers;

  /// 接收状态。
  final BluetoothReceiveState receive;

  /// 最近一次发送错误（用于 UI 提示）。
  final String? sendError;

  /// 整体发送进度 0..1。
  final double sendProgress;

  const BluetoothState({
    this.supported = false,
    this.enabled = false,
    this.discovering = false,
    this.peers = const [],
    this.receive = const BluetoothReceiveState(),
    this.sendError,
    this.sendProgress = 0,
  });

  BluetoothState copyWith({
    bool? supported,
    bool? enabled,
    bool? discovering,
    List<BluetoothPeer>? peers,
    BluetoothReceiveState? receive,
    String? sendError,
    double? sendProgress,
    bool clearSendError = false,
  }) {
    return BluetoothState(
      supported: supported ?? this.supported,
      enabled: enabled ?? this.enabled,
      discovering: discovering ?? this.discovering,
      peers: peers ?? this.peers,
      receive: receive ?? this.receive,
      sendError: clearSendError ? null : (sendError ?? this.sendError),
      sendProgress: sendProgress ?? this.sendProgress,
    );
  }
}

/// 管理蓝牙发现、连接与接收。
final bluetoothProvider = NotifierProvider<BluetoothNotifier, BluetoothState>((ref) {
  return BluetoothNotifier();
});

class BluetoothNotifier extends Notifier<BluetoothState> {
  StreamSubscription<BluetoothPeer>? _discoverySub;
  StreamSubscription<dynamic>? _receiveSub;

  @override
  BluetoothState init() => const BluetoothState();

  /// 检查平台支持与适配器状态（进入蓝牙页面时调用）。
  Future<void> refresh() async {
    final supported = await BluetoothTransferService.isSupported();
    final enabled = supported && await BluetoothTransferService.ensureEnabled();
    state = state.copyWith(supported: supported, enabled: enabled);
  }

  /// 开始扫描附近设备。
  Future<void> startDiscovery() async {
    if (!state.supported) return;
    await refresh();
    if (!state.enabled) return;
    state = state.copyWith(discovering: true, peers: []);
    await _discoverySub?.cancel();
    _discoverySub = BluetoothTransferService.discover().listen(
      (peer) {
        final peers = [...state.peers];
        final idx = peers.indexWhere((p) => p.address == peer.address);
        if (idx >= 0) {
          peers[idx] = peer;
        } else {
          peers.add(peer);
        }
        state = state.copyWith(peers: peers);
      },
      onError: (e) {
        state = state.copyWith(discovering: false, sendError: e.toString());
      },
      onDone: () => state = state.copyWith(discovering: false),
    );
  }

  Future<void> stopDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    await BluetoothTransferService.cancelDiscovery();
    state = state.copyWith(discovering: false);
  }

  /// 向指定设备发送文件。
  Future<void> sendFiles({
    required String address,
    required List<BluetoothSendItem> items,
  }) async {
    state = state.copyWith(clearSendError: true, sendProgress: 0);
    try {
      await BluetoothTransferService.sendFiles(
        address: address,
        items: items,
        onProgress: (fileIndex, total, progress) {
          // 粗略的整体进度：已完成的文件 + 当前文件进度，再除以总数。
          final overall = (fileIndex + progress) / (total == 0 ? 1 : total);
          state = state.copyWith(sendProgress: overall.clamp(0, 1));
        },
      );
      state = state.copyWith(sendProgress: 1);
    } catch (e) {
      state = state.copyWith(sendError: e.toString());
    }
  }

  /// 切换接收模式（开启原生 RFCOMM 监听）。
  Future<void> setReceiveMode(bool on) async {
    if (!state.supported) return;
    if (on) {
      if (!state.enabled) await refresh();
      state = state.copyWith(receive: const BluetoothReceiveState(listening: true));
      try {
        _receiveSub = await BluetoothTransferService.startReceive(
          onConnected: () {},
          onProgress: (fileName, fileIndex, total, progress) {
            state = state.copyWith(
              receive: state.receive.copyWith(
                fileIndex: fileIndex,
                totalFiles: total,
                currentFileName: fileName,
                fileProgress: progress,
              ),
            );
          },
          onFileSaved: (path) {
            state = state.copyWith(
              receive: state.receive.copyWith(
                receivedPaths: [...state.receive.receivedPaths, path],
                fileProgress: 0,
                clearCurrentFileName: true,
              ),
            );
          },
          onError: (error) {
            state = state.copyWith(
              receive: state.receive.copyWith(listening: false, errorMessage: error),
            );
          },
        );
      } catch (e) {
        state = state.copyWith(receive: state.receive.copyWith(listening: false, errorMessage: e.toString()));
      }
    } else {
      await _receiveSub?.cancel();
      _receiveSub = null;
      await BluetoothTransferService.stopReceive();
      state = state.copyWith(receive: const BluetoothReceiveState());
    }
  }

  @override
  void dispose() {
    unawaited(_discoverySub?.cancel());
    unawaited(_receiveSub?.cancel());
    super.dispose();
  }
}
