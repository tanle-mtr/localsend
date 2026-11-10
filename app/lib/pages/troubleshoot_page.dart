import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/cmd_helper.dart';
import 'package:localsend_app/util/native/macos_channel.dart' as macos_channel;
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/dialogs/not_available_on_platform_dialog.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:refena_flutter/refena_flutter.dart';

class TroubleshootPage extends StatelessWidget {
  const TroubleshootPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.troubleshootPage.title),
      ),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 30),
        children: [
          Text(t.troubleshootPage.subTitle, textAlign: TextAlign.center),
          const SizedBox(height: 5),
          const _DiagnosticsCard(),
          const SizedBox(height: 10),
          if (checkPlatformIsDesktop())
            _TroubleshootItem(
              symptomText: t.troubleshootPage.firewall.symptom,
              solutionText: t.troubleshootPage.firewall.solution(port: settings.port),
              primaryButton: _FixButton(
                label: t.troubleshootPage.fixButton,
                onTapMap: {
                  TargetPlatform.windows: _CommandFixAction(
                    adminPrivileges: true,
                    commands: [
                      'netsh advfirewall firewall add rule name="LocalSend" dir=in action=allow protocol=TCP localport=${settings.port}',
                      'netsh advfirewall firewall add rule name="LocalSend" dir=in action=allow protocol=UDP localport=${settings.port}',
                    ],
                  ),
                },
              ),
              secondaryButton: _FixButton(
                label: t.troubleshootPage.firewall.openFirewall,
                onTapMap: {
                  TargetPlatform.windows: _CommandFixAction(
                    adminPrivileges: false,
                    commands: ['wf'],
                  ),
                  TargetPlatform.macOS: _NativeFixAction(() => macos_channel.openFirewallSettings()),
                },
              ),
            ),
          _TroubleshootItem(
            symptomText: t.troubleshootPage.noDiscovery.symptom,
            solutionText: t.troubleshootPage.noDiscovery.solution,
          ),
          _TroubleshootItem(
            symptomText: t.troubleshootPage.noConnection.symptom,
            solutionText: t.troubleshootPage.noConnection.solution,
          ),
        ],
      ),
    );
  }
}

class _TroubleshootItem extends StatefulWidget {
  final String symptomText;
  final String solutionText;
  final _FixButton? primaryButton;
  final _FixButton? secondaryButton;

  const _TroubleshootItem({
    required this.symptomText,
    required this.solutionText,
    this.primaryButton,
    this.secondaryButton,
  });

  @override
  State<_TroubleshootItem> createState() => _TroubleshootItemState();
}

class _TroubleshootItemState extends State<_TroubleshootItem> {
  bool _showCommands = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.symptomText, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Text(t.troubleshootPage.solution),
              Text(widget.solutionText),
              if (widget.primaryButton?.onTap != null || widget.secondaryButton?.onTap != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  runSpacing: 10,
                  children: [
                    if (widget.primaryButton?.onTap != null) widget.primaryButton!,
                    if (widget.secondaryButton?.onTap != null) ...[
                      if (widget.primaryButton?.onTap != null) const SizedBox(width: 10),
                      widget.secondaryButton!,
                    ],
                    if (widget.primaryButton?.onTap?.commands != null) ...[
                      const SizedBox(width: 10),
                      CustomIconButton(
                        onPressed: () {
                          setState(() => _showCommands = !_showCommands);
                        },
                        child: const Icon(Icons.info),
                      ),
                    ],
                  ],
                ),
                AnimatedCrossFade(
                  crossFadeState: _showCommands ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                  firstChild: Container(),
                  secondChild: SelectionArea(
                    child: Column(
                      children: [
                        ...?widget.primaryButton?.onTap?.commands?.map((cmd) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(cmd, style: const TextStyle(fontFamily: 'RobotoMono')),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FixButton extends StatelessWidget {
  final String label;
  final Map<TargetPlatform, _FixAction> onTapMap;
  final _FixAction? onTap;

  _FixButton({
    required this.label,
    required this.onTapMap,
  }) : onTap = onTapMap[defaultTargetPlatform];

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      onPressed: () async {
        if (onTap != null) {
          onTap!.runFix();
        } else {
          await showDialog(
            context: context,
            builder: (_) => NotAvailableOnPlatformDialog(platforms: onTapMap.keys.toList()),
          );
        }
      },
      child: Text(label),
    );
  }
}

abstract class _FixAction {
  void runFix();

  List<String>? get commands;
}

class _CommandFixAction extends _FixAction {
  final bool adminPrivileges;

  @override
  final List<String> commands;

  _CommandFixAction({
    required this.adminPrivileges,
    required this.commands,
  });

  @override
  void runFix() async {
    if (adminPrivileges) {
      if (checkPlatform([TargetPlatform.windows])) {
        await runWindowsCommandAsAdmin(commands);
      } else {
        throw 'Admin privileges are only implemented on Windows.';
      }
    } else {
      for (final c in commands) {
        await Process.run(c, [], runInShell: true);
      }
    }
  }
}

class _NativeFixAction extends _FixAction {
  final Future<void> Function() action;

  _NativeFixAction(this.action);

  @override
  List<String>? get commands => null;

  @override
  void runFix() async {
    await action();
  }
}

/// Shows live network state and one-tap recovery actions.
/// This turns the "cannot discover / cannot connect" reports into
/// self-service checks instead of support tickets.
class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final server = ref.watch(serverProvider);
    final ips = ref.watch(localIpProvider).localIps;
    final deviceCount = ref.watch(nearbyDevicesProvider.select((state) => state.devices.length));
    final hasVirtualIp = ips.any(_isVirtualIp);
    final summary = 'LocalSend diagnostics\n'
        'server: ${server == null ? 'stopped' : 'running :${server.port}'}\n'
        'ips: ${ips.join(', ')}\n'
        'devices: $deviceCount\n'
        'virtual_ip: $hasVirtualIp';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.troubleshootPage.diagnostics.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _DiagnosticRow(
              icon: Icons.dns,
              text: server == null
                  ? t.troubleshootPage.diagnostics.serverStopped
                  : t.troubleshootPage.diagnostics.serverRunning(port: server.port),
              color: server == null ? Colors.orange : Colors.green,
            ),
            if (ips.isNotEmpty)
              _DiagnosticRow(
                icon: Icons.lan,
                text: t.troubleshootPage.diagnostics.localIps(ips: ips.join(', ')),
              ),
            _DiagnosticRow(
              icon: Icons.devices,
              text: t.troubleshootPage.diagnostics.discovered(n: deviceCount),
            ),
            if (hasVirtualIp)
              _DiagnosticRow(
                icon: Icons.vpn_key,
                text: t.troubleshootPage.diagnostics.vpnWarning,
                color: Colors.orange,
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await ref.notifier(serverProvider).restartServerFromSettings();
                    } catch (_) {
                      // The status row above reflects whether the restart worked.
                    }
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: Text(t.troubleshootPage.diagnostics.restartServer),
                ),
                TextButton.icon(
                  onPressed: () {
                    ref.redux(parentIsolateProvider).dispatch(IsolateDiscoveryRestartAction());
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(t.troubleshootPage.diagnostics.restartDiscovery),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: summary));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.troubleshootPage.diagnostics.copied)),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(t.troubleshootPage.diagnostics.copy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _DiagnosticRow({
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: color == null ? null : TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

bool _isVirtualIp(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) {
    return false;
  }
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) {
    return false;
  }
  // Tailscale and some CGNAT networks use 100.64.0.0/10.
  return a == 100 && b >= 64 && b <= 127;
}
