import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/network_config.dart';
import '../providers/app_state.dart';
import '../widgets/port_forward_editor.dart';
import '../widgets/string_list_editor.dart';

class ConfigEditScreen extends StatefulWidget {
  const ConfigEditScreen({
    super.key,
    required this.config,
    required this.isNew,
  });

  final NetworkConfig config;
  final bool isNew;

  @override
  State<ConfigEditScreen> createState() => _ConfigEditScreenState();
}

class _ConfigEditScreenState extends State<ConfigEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late NetworkConfig _cfg;

  @override
  void initState() {
    super.initState();
    _cfg = NetworkConfig.fromJson(widget.config.toJson());
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    if (_cfg.dhcp) {
      _cfg.virtualIpv4 = '';
      _cfg.virtualIpv6 = '';
    }
    if (!_cfg.enableSocks5) {
      _cfg.socks5Proxy = '';
    }
    if (!_cfg.secureModeEnabled) {
      _cfg.localPrivateKey = '';
      _cfg.localPublicKey = '';
    }
    if (!_cfg.enableRelayNetworkWhitelist) {
      _cfg.relayNetworkWhitelist = const ['*'];
    }

    final state = context.read<AppState>();
    if (widget.isNew) {
      state.addConfig(_cfg);
    } else {
      state.updateConfig(_cfg);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Official Config' : 'Edit Official Config'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _Section(
              title: 'Network Identity',
              children: [
                _Field(
                  label: 'Network Name',
                  initial: _cfg.networkName,
                  hint: 'default',
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                  onSaved: (value) => _cfg.networkName = value ?? '',
                ),
                _Field(
                  label: 'Network Secret',
                  initial: _cfg.networkSecret,
                  hint: 'shared secret',
                  obscure: true,
                  onSaved: (value) => _cfg.networkSecret = value ?? '',
                ),
                _Field(
                  label: 'Instance Name',
                  initial: _cfg.instanceName,
                  hint: 'default',
                  onSaved: (value) => _cfg.instanceName = value ?? '',
                ),
                _Field(
                  label: 'Hostname',
                  initial: _cfg.hostname,
                  hint: 'node-a',
                  onSaved: (value) => _cfg.hostname = value ?? '',
                ),
                _Field(
                  label: 'NetNS',
                  initial: _cfg.netns,
                  hint: 'optional',
                  onSaved: (value) => _cfg.netns = value ?? '',
                ),
                SelectableText(
                  'instance_id = ${_cfg.id}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            _Section(
              title: 'Addressing & Listener',
              children: [
                _ToggleRow(
                  title: 'DHCP',
                  subtitle: 'Official `dhcp = true`',
                  value: _cfg.dhcp,
                  onChanged: (value) => setState(() => _cfg.dhcp = value),
                ),
                if (!_cfg.dhcp) ...[
                  _Field(
                    label: 'IPv4',
                    initial: _cfg.virtualIpv4,
                    hint: '10.144.144.10',
                    onSaved: (value) => _cfg.virtualIpv4 = value ?? '',
                  ),
                  _Field(
                    label: 'IPv6',
                    initial: _cfg.virtualIpv6,
                    hint: 'fd00::10',
                    onSaved: (value) => _cfg.virtualIpv6 = value ?? '',
                  ),
                ],
                StringListEditor(
                  label: 'Listeners',
                  hint: 'tcp://0.0.0.0:11010',
                  items: _cfg.listeners,
                  onChanged: (items) => setState(() => _cfg.listeners = items),
                ),
                StringListEditor(
                  label: 'Mapped Listeners',
                  hint: 'tcp://public-ip:11010',
                  items: _cfg.mappedListeners,
                  onChanged: (items) =>
                      setState(() => _cfg.mappedListeners = items),
                ),
                StringListEditor(
                  label: 'Exit Nodes',
                  hint: '100.64.0.2',
                  items: _cfg.exitNodes,
                  onChanged: (items) => setState(() => _cfg.exitNodes = items),
                ),
              ],
            ),
            _Section(
              title: 'Peers & Routing',
              children: [
                StringListEditor(
                  label: 'Peer URIs',
                  hint: 'tcp://1.2.3.4:11010',
                  items: _cfg.peerUrls,
                  onChanged: (items) => setState(() => _cfg.peerUrls = items),
                ),
                StringListEditor(
                  label: 'Routes',
                  hint: '192.168.0.0/16',
                  items: _cfg.manualRoutes,
                  onChanged: (items) =>
                      setState(() => _cfg.manualRoutes = items),
                ),
                StringListEditor(
                  label: 'Proxy Networks',
                  hint: '10.147.223.0/24',
                  items: _cfg.proxyCidrs,
                  onChanged: (items) => setState(() => _cfg.proxyCidrs = items),
                ),
                StringListEditor(
                  label: 'TCP Whitelist',
                  hint: '443',
                  items: _cfg.tcpWhitelist,
                  onChanged: (items) =>
                      setState(() => _cfg.tcpWhitelist = items),
                ),
                StringListEditor(
                  label: 'UDP Whitelist',
                  hint: '3478',
                  items: _cfg.udpWhitelist,
                  onChanged: (items) =>
                      setState(() => _cfg.udpWhitelist = items),
                ),
                StringListEditor(
                  label: 'STUN Servers',
                  hint: 'stun.l.google.com:19302',
                  items: _cfg.stunServers,
                  onChanged: (items) =>
                      setState(() => _cfg.stunServers = items),
                ),
                StringListEditor(
                  label: 'STUN Servers v6',
                  hint: 'txt:stun.easytier.cn',
                  items: _cfg.stunServersV6,
                  onChanged: (items) =>
                      setState(() => _cfg.stunServersV6 = items),
                ),
              ],
            ),
            _Section(
              title: 'Portal & Security',
              children: [
                _ToggleRow(
                  title: 'SOCKS5 Proxy',
                  subtitle: 'Writes official `socks5_proxy` URL',
                  value: _cfg.enableSocks5,
                  onChanged: (value) => setState(() => _cfg.enableSocks5 = value),
                ),
                if (_cfg.enableSocks5)
                  _Field(
                    label: 'SOCKS5 URL',
                    initial: _cfg.socks5Proxy,
                    hint: 'socks5://0.0.0.0:1080',
                    onSaved: (value) => _cfg.socks5Proxy = value ?? '',
                  ),
                _Field(
                  label: 'VPN Portal Client CIDR',
                  initial: _cfg.vpnPortalClientCidr,
                  hint: '10.14.0.0/24',
                  onSaved: (value) => _cfg.vpnPortalClientCidr = value ?? '',
                ),
                _Field(
                  label: 'WireGuard Listen',
                  initial: _cfg.vpnPortalWireguardListen,
                  hint: '0.0.0.0:11011',
                  onSaved: (value) =>
                      _cfg.vpnPortalWireguardListen = value ?? '',
                ),
                _Field(
                  label: 'Credential File',
                  initial: _cfg.credentialFile,
                  hint: '/path/to/credential.json',
                  onSaved: (value) => _cfg.credentialFile = value ?? '',
                ),
                _ToggleRow(
                  title: 'Secure Mode',
                  subtitle: 'Official `[secure_mode].enabled`',
                  value: _cfg.secureModeEnabled,
                  onChanged: (value) =>
                      setState(() => _cfg.secureModeEnabled = value),
                ),
                if (_cfg.secureModeEnabled) ...[
                  _Field(
                    label: 'Local Private Key',
                    initial: _cfg.localPrivateKey,
                    maxLines: 2,
                    onSaved: (value) => _cfg.localPrivateKey = value ?? '',
                  ),
                  _Field(
                    label: 'Local Public Key',
                    initial: _cfg.localPublicKey,
                    maxLines: 2,
                    onSaved: (value) => _cfg.localPublicKey = value ?? '',
                  ),
                ],
                PortForwardEditor(
                  items: _cfg.portForwards,
                  onChanged: (items) =>
                      setState(() => _cfg.portForwards = items),
                ),
              ],
            ),
            _Section(
              title: 'Flags',
              children: [
                _DropdownField(
                  label: 'Default Protocol',
                  value: _cfg.defaultProtocol,
                  items: const {
                    'tcp': 'TCP',
                    'udp': 'UDP',
                    'wg': 'WireGuard',
                    'ws': 'WebSocket',
                    'wss': 'WebSocket TLS',
                  },
                  onChanged: (value) =>
                      setState(() => _cfg.defaultProtocol = value ?? 'tcp'),
                ),
                _DropdownField(
                  label: 'Encryption Algorithm',
                  value: _cfg.encryptionAlgorithm,
                  items: const {
                    'aes-gcm': 'aes-gcm',
                    'aes-256-gcm': 'aes-256-gcm',
                    'chacha20': 'chacha20',
                    'xor': 'xor',
                  },
                  onChanged: (value) => setState(
                    () => _cfg.encryptionAlgorithm = value ?? 'aes-gcm',
                  ),
                ),
                _DropdownField(
                  label: 'Compression',
                  value: _cfg.compression.isEmpty ? 'none' : _cfg.compression,
                  items: const {
                    'none': 'None',
                    'zstd': 'zstd',
                  },
                  onChanged: (value) => setState(
                    () => _cfg.compression =
                        value == null || value == 'none' ? '' : value,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FlagChip(
                      label: 'No TUN',
                      value: _cfg.noTun,
                      onChanged: (v) => setState(() => _cfg.noTun = v),
                    ),
                    _FlagChip(
                      label: 'smoltcp',
                      value: _cfg.useSmoltcp,
                      onChanged: (v) => setState(() => _cfg.useSmoltcp = v),
                    ),
                    _FlagChip(
                      label: 'Latency First',
                      value: _cfg.latencyFirst,
                      onChanged: (v) => setState(() => _cfg.latencyFirst = v),
                    ),
                    _FlagChip(
                      label: 'Exit Node',
                      value: _cfg.enableExitNode,
                      onChanged: (v) => setState(() => _cfg.enableExitNode = v),
                    ),
                    _FlagChip(
                      label: 'Accept DNS',
                      value: _cfg.acceptDns,
                      onChanged: (v) => setState(() => _cfg.acceptDns = v),
                    ),
                    _FlagChip(
                      label: 'Private Mode',
                      value: _cfg.privateMode,
                      onChanged: (v) => setState(() => _cfg.privateMode = v),
                    ),
                    _FlagChip(
                      label: 'Disable P2P',
                      value: _cfg.disableP2p,
                      onChanged: (v) => setState(() => _cfg.disableP2p = v),
                    ),
                    _FlagChip(
                      label: 'Need P2P',
                      value: _cfg.needP2p,
                      onChanged: (v) => setState(() => _cfg.needP2p = v),
                    ),
                    _FlagChip(
                      label: 'Lazy P2P',
                      value: _cfg.lazyP2p,
                      onChanged: (v) => setState(() => _cfg.lazyP2p = v),
                    ),
                    _FlagChip(
                      label: 'P2P Only',
                      value: _cfg.p2pOnly,
                      onChanged: (v) => setState(() => _cfg.p2pOnly = v),
                    ),
                    _FlagChip(
                      label: 'Relay All Peer RPC',
                      value: _cfg.relayAllPeerRpc,
                      onChanged: (v) =>
                          setState(() => _cfg.relayAllPeerRpc = v),
                    ),
                    _FlagChip(
                      label: 'KCP Proxy',
                      value: _cfg.enableKcpProxy,
                      onChanged: (v) => setState(() => _cfg.enableKcpProxy = v),
                    ),
                    _FlagChip(
                      label: 'Disable KCP Input',
                      value: _cfg.disableKcpInput,
                      onChanged: (v) => setState(() => _cfg.disableKcpInput = v),
                    ),
                    _FlagChip(
                      label: 'QUIC Proxy',
                      value: _cfg.enableQuicProxy,
                      onChanged: (v) =>
                          setState(() => _cfg.enableQuicProxy = v),
                    ),
                    _FlagChip(
                      label: 'Disable QUIC Input',
                      value: _cfg.disableQuicInput,
                      onChanged: (v) => setState(() => _cfg.disableQuicInput = v),
                    ),
                    _FlagChip(
                      label: 'Disable IPv6',
                      value: _cfg.disableIpv6,
                      onChanged: (v) => setState(() => _cfg.disableIpv6 = v),
                    ),
                    _FlagChip(
                      label: 'Disable Encryption',
                      value: _cfg.disableEncryption,
                      onChanged: (v) =>
                          setState(() => _cfg.disableEncryption = v),
                    ),
                    _FlagChip(
                      label: 'Multi Thread',
                      value: _cfg.multiThread,
                      onChanged: (v) => setState(() => _cfg.multiThread = v),
                    ),
                    _FlagChip(
                      label: 'Bind Device',
                      value: _cfg.bindDevice,
                      onChanged: (v) => setState(() => _cfg.bindDevice = v),
                    ),
                  ],
                ),
                _Field(
                  label: 'MTU',
                  initial: '${_cfg.mtu}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) => _cfg.mtu = int.tryParse(value ?? '') ?? 1380,
                ),
                _Field(
                  label: 'Multi Thread Count',
                  initial: '${_cfg.multiThreadCount}',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) =>
                      _cfg.multiThreadCount = int.tryParse(value ?? '') ?? 2,
                ),
                _Field(
                  label: 'Device Name',
                  initial: _cfg.devName,
                  onSaved: (value) => _cfg.devName = value ?? '',
                ),
                _Field(
                  label: 'TLD DNS Zone',
                  initial: _cfg.tldDnsZone,
                  onSaved: (value) => _cfg.tldDnsZone = value ?? '',
                ),
                _Field(
                  label: 'Instance Receive BPS Limit',
                  initial: _cfg.instanceRecvBpsLimit > 0
                      ? '${_cfg.instanceRecvBpsLimit}'
                      : '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) => _cfg.instanceRecvBpsLimit =
                      int.tryParse(value ?? '') ?? 0,
                ),
                _Field(
                  label: 'Foreign Relay BPS Limit',
                  initial: _cfg.foreignRelayBpsLimit > 0
                      ? '${_cfg.foreignRelayBpsLimit}'
                      : '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) => _cfg.foreignRelayBpsLimit =
                      int.tryParse(value ?? '') ?? 0,
                ),
                _ToggleRow(
                  title: 'Relay Network Whitelist',
                  subtitle: 'Writes `flags.relay_network_whitelist`',
                  value: _cfg.enableRelayNetworkWhitelist,
                  onChanged: (value) =>
                      setState(() => _cfg.enableRelayNetworkWhitelist = value),
                ),
                if (_cfg.enableRelayNetworkWhitelist)
                  StringListEditor(
                    label: 'Relay Network Whitelist',
                    hint: 'net-a or net-*',
                    items: _cfg.relayNetworkWhitelist,
                    onChanged: (items) =>
                        setState(() => _cfg.relayNetworkWhitelist = items),
                  ),
              ],
            ),
            _Section(
              title: 'Logging & Runtime',
              children: [
                _Field(
                  label: 'Console Logger Level',
                  initial: _cfg.consoleLogLevel,
                  hint: 'info',
                  onSaved: (value) => _cfg.consoleLogLevel = value ?? 'info',
                ),
                _Field(
                  label: 'File Logger Level',
                  initial: _cfg.fileLogLevel,
                  onSaved: (value) => _cfg.fileLogLevel = value ?? '',
                ),
                _Field(
                  label: 'File Logger Name',
                  initial: _cfg.fileLogFile,
                  hint: 'easytier',
                  onSaved: (value) => _cfg.fileLogFile = value ?? '',
                ),
                _Field(
                  label: 'File Logger Dir',
                  initial: _cfg.fileLogDir,
                  onSaved: (value) => _cfg.fileLogDir = value ?? '',
                ),
                _Field(
                  label: 'File Logger Size MB',
                  initial: _cfg.fileLogSizeMb > 0 ? '${_cfg.fileLogSizeMb}' : '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) =>
                      _cfg.fileLogSizeMb = int.tryParse(value ?? '') ?? 0,
                ),
                _Field(
                  label: 'File Logger Count',
                  initial: _cfg.fileLogCount > 0 ? '${_cfg.fileLogCount}' : '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) =>
                      _cfg.fileLogCount = int.tryParse(value ?? '') ?? 0,
                ),
                _Field(
                  label: 'RPC Port',
                  initial: '${_cfg.rpcPort}',
                  helperText:
                      'App runtime parameter appended as `--rpc-portal`; FlEasyTier will auto-reassign if it conflicts',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSaved: (value) =>
                      _cfg.rpcPort = int.tryParse(value ?? '') ?? 15888,
                ),
                StringListEditor(
                  label: 'RPC Portal Whitelist',
                  hint: '127.0.0.1/32',
                  items: _cfg.rpcPortalWhitelist,
                  onChanged: (items) =>
                      setState(() => _cfg.rpcPortalWhitelist = items),
                ),
                _ToggleRow(
                  title: 'Auto Start',
                  subtitle: 'App-level behavior, not part of the TOML',
                  value: _cfg.autoStart,
                  onChanged: (value) => setState(() => _cfg.autoStart = value),
                ),
              ],
            ),
            const SizedBox(height: 80),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children.expand((child) => [child, const SizedBox(height: 12)]).toList()
              ..removeLast(),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    this.initial,
    this.hint,
    this.helperText,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.obscure = false,
    required this.onSaved,
  });

  final String label;
  final String? initial;
  final String? hint;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final bool obscure;
  final FormFieldSetter<String> onSaved;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initial,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSaved: onSaved,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: value,
      label: Text(label),
      onSelected: onChanged,
    );
  }
}
