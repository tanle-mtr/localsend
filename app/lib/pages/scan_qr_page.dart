import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/last_devices.provider.dart';
import 'package:localsend_app/util/qr/connect_payload.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';
import 'package:system_settings_2/system_settings_2.dart';

/// Scanner that reads a LocalSend connection QR code (see [buildConnectQrData])
/// and connects to the receiver by performing the normal discovery handshake.
///
/// On success it pops with the resolved [Device], exactly like
/// [AddressInputDialog] does, so the caller can start a send session.
class ScanQrPage extends StatefulWidget {
  const ScanQrPage();

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> with Refena {
  final MobileScannerController _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );

  bool _busy = false;
  String? _error;
  String? _lastRaw;
  String? _lockedRaw;

  Future<void> _connect(String raw) async {
    if (_busy) return;
    // Ignore repeated detections of the same QR that already failed, until the
    // user explicitly retries or scans a different code.
    if (_lockedRaw != null && _lockedRaw == raw) return;
    final parsed = tryParseConnectQr(raw);
    if (parsed == null) {
      if (mounted) {
        setState(() => _error = t.qrConnect.invalid);
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _lastRaw = raw;
    });

    try {
      final https = parsed.https;
      final payload = ref.read(deviceFullInfoProvider).toRegisterDto();
      final response = await ref.read(httpProvider).discovery.register(
            protocol: https ? ProtocolType.https : ProtocolType.http,
            ip: parsed.ip,
            port: parsed.port,
            payload: payload,
          );
      final device = response.body.toDevice(parsed.ip, parsed.port, https);
      ref.redux(lastDevicesProvider).dispatch(AddLastDeviceAction(device));
      if (mounted) {
        context.pop(device);
      }
    } catch (e) {
      if (mounted) {
        final ssidHint = parsed.ssid != null ? ' (${t.qrConnect.hotspot}: ${parsed.ssid})' : '';
        setState(() {
          _busy = false;
          _error = '${t.qrConnect.notFound}$ssidHint';
          _lockedRaw = raw;
        });
      }
    }
  }

  Future<void> _openWifiSettings() async {
    if (Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.qrConnect.iosHotspotHint)),
        );
      }
      return;
    }
    try {
      unawaited(SystemSettings.wifi());
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.qrConnect.scan),
        actions: [
          IconButton(
            tooltip: t.qrConnect.torch,
            icon: const Icon(Icons.flashlight_on),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
              } catch (_) {
                // Some devices have no torch; ignore.
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) async {
              final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (code != null) {
                await _connect(code);
              }
            },
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t.qrConnect.cameraError,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          // Scanning guide overlay.
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Text(
              t.qrConnect.scanHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openWifiSettings,
                          icon: const Icon(Icons.wifi),
                          label: Text(t.qrConnect.openWifiSettings),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        FilledButton(
                          onPressed: _lastRaw == null
                              ? null
                              : () async {
                                  _lockedRaw = null;
                                  await _connect(_lastRaw!);
                                },
                          child: Text(t.qrConnect.joinHotspot),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
