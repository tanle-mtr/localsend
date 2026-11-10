/// 蓝牙发现的远端对等设备。
class BluetoothPeer {
  final String address; // MAC 地址，作为连接与去重的唯一标识
  final String name;
  final bool bonded; // 是否已配对

  const BluetoothPeer({
    required this.address,
    required this.name,
    required this.bonded,
  });

  @override
  bool operator ==(Object other) => other is BluetoothPeer && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'BluetoothPeer($name @ $address${bonded ? ' [paired]' : ''})';
}

/// 一次蓝牙接收会话的进度快照。
class BluetoothReceiveState {
  final bool listening;
  final String? peerName;
  final String? currentFileName;
  final int fileIndex;
  final int totalFiles;
  final double fileProgress; // 0..1
  final List<String> receivedPaths;
  final String? errorMessage;

  const BluetoothReceiveState({
    this.listening = false,
    this.peerName,
    this.currentFileName,
    this.fileIndex = 0,
    this.totalFiles = 0,
    this.fileProgress = 0,
    this.receivedPaths = const [],
    this.errorMessage,
  });

  BluetoothReceiveState copyWith({
    bool? listening,
    String? peerName,
    String? currentFileName,
    int? fileIndex,
    int? totalFiles,
    double? fileProgress,
    List<String>? receivedPaths,
    String? errorMessage,
    bool clearPeerName = false,
    bool clearCurrentFileName = false,
    bool clearErrorMessage = false,
  }) {
    return BluetoothReceiveState(
      listening: listening ?? this.listening,
      peerName: clearPeerName ? null : (peerName ?? this.peerName),
      currentFileName: clearCurrentFileName ? null : (currentFileName ?? this.currentFileName),
      fileIndex: fileIndex ?? this.fileIndex,
      totalFiles: totalFiles ?? this.totalFiles,
      fileProgress: fileProgress ?? this.fileProgress,
      receivedPaths: receivedPaths ?? this.receivedPaths,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
