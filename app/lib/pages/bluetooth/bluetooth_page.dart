import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/transfer/bluetooth/bluetooth_provider.dart';
import 'package:localsend_app/provider/transfer/bluetooth/bluetooth_transfer_service.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 蓝牙无网互传页面：发现设备、向对端发送已选文件、或开启接收模式等待对端发送。
class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> with Refena {
  @override
  void initState() {
    super.initState();
    ensureRef((ref) async {
      if (!ref.read(settingsProvider).enableBluetooth) {
        return;
      }
      // Auto-start scanning so nearby devices show up without an extra tap (#2872).
      await ref.notifier(bluetoothProvider).startDiscovery();
    });
  }

  Future<void> _sendTo(String address) async {
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isEmpty) return;
    final items = files
        .map(
          (f) => BluetoothSendItem(
            name: f.name,
            size: f.size,
            read: () async {
              if (f.bytes != null) return Uint8List.fromList(f.bytes!);
              if (f.path != null) return await File(f.path!).readAsBytes();
              throw StateError('No readable data for ${f.name}');
            },
          ),
        )
        .toList();
    await ref.notifier(bluetoothProvider).sendFiles(address: address, items: items);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(bluetoothProvider);
    final selectedCount = context.watch(selectedSendingFilesProvider).length;

    if (!ref.watch(settingsProvider).enableBluetooth) {
      return Scaffold(
        appBar: AppBar(title: Text(t.bluetoothTab.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.bluetoothTab.enablePrompt, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      );
    }

    if (!vm.supported) {
      return Scaffold(
        appBar: AppBar(title: Text(t.bluetoothTab.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.bluetoothTab.unsupported, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.bluetoothTab.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 接收模式
          SwitchListTile(
            title: Text(t.bluetoothTab.receiveMode),
            subtitle: Text(t.bluetoothTab.receiveHint),
            value: vm.receive.listening,
            onChanged: (v) => ref.notifier(bluetoothProvider).setReceiveMode(v),
          ),
          if (vm.receive.listening) _ReceiveProgress(vm: vm),
          const Divider(height: 24),
          // 发送区
          Row(
            children: [
              Expanded(child: Text(t.bluetoothTab.sendTo, style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.icon(
                icon: vm.discovering ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bluetooth_searching),
                label: Text(vm.discovering ? t.bluetoothTab.stopDiscover : t.bluetoothTab.discover),
                onPressed: vm.discovering
                    ? () => ref.notifier(bluetoothProvider).stopDiscovery()
                    : () => ref.notifier(bluetoothProvider).startDiscovery(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (selectedCount == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t.selectedFilesPage.noFiles, style: Theme.of(context).textTheme.bodySmall),
            )
          else if (vm.peers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t.bluetoothTab.deviceCount(count: vm.peers.length)),
            ),
          if (vm.peers.isEmpty && !vm.discovering)
            Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(t.bluetoothTab.noDevices)))
          else
            ...vm.peers.map(
              (peer) => ListTile(
                leading: Icon(peer.bonded ? Icons.bluetooth_connected : Icons.bluetooth),
                title: Text(peer.name),
                subtitle: Text(peer.bonded ? '' : t.bluetoothTab.notPaired),
                trailing: selectedCount == 0
                    ? null
                    : FilledButton(
                        onPressed: () => _sendTo(peer.address),
                        child: const Icon(Icons.send),
                      ),
              ),
            ),
          if (vm.sendError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(vm.sendError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (vm.sendProgress > 0 && vm.sendProgress < 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(value: vm.sendProgress),
            ),
        ],
      ),
    );
  }
}

class _ReceiveProgress extends StatelessWidget {
  final BluetoothState vm;

  const _ReceiveProgress({required this.vm});

  @override
  Widget build(BuildContext context) {
    final r = vm.receive;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.bluetoothTab.receiving, style: Theme.of(context).textTheme.labelLarge),
          if (r.currentFileName != null) ...[
            const SizedBox(height: 4),
            Text('${r.currentFileName} (${r.fileIndex}/${r.totalFiles})'),
            LinearProgressIndicator(value: r.fileProgress),
          ],
          if (r.receivedPaths.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t.bluetoothTab.received),
            ...r.receivedPaths.map((p) => Text(p, style: Theme.of(context).textTheme.bodySmall)),
          ],
          if (r.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(r.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
