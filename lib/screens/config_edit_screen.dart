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
    _cfg = widget.config.copyWith();
  }

  void _rebuild() => setState(() {});

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    // Enforce mutual exclusion on save
    _enforceMutualExclusion();
    final state = context.read<AppState>();
    if (widget.isNew) {
      state.addConfig(_cfg);
    } else {
      state.updateConfig(_cfg);
    }
    Navigator.of(context).pop();
  }

  void _enforceMutualExclusion() {
    // If P2P is disabled, clear all P2P sub-options
    if (_cfg.disableP2p) {
      _cfg.disableUdpHolePunching = false;
      _cfg.disableTcpHolePunching = false;
      _cfg.disableSymHolePunching = false;
      _cfg.lazyP2p = false;
      _cfg.needP2p = false;
      _cfg.p2pOnly = false;
    }
    // p2pOnly and disableP2p are mutually exclusive
    if (_cfg.p2pOnly) _cfg.disableP2p = false;
    // needP2p and lazyP2p are mutually exclusive
    if (_cfg.needP2p) _cfg.lazyP2p = false;
    // If encryption disabled, clear algorithm
    if (_cfg.disableEncryption) _cfg.encryptionAlgorithm = '';
    // If noListener, clear listeners
    if (_cfg.noListener) _cfg.listeners = [];
    // If DHCP, clear manual IP
    if (_cfg.dhcp) {
      _cfg.virtualIpv4 = '';
      _cfg.virtualIpv6 = '';
    }
    // If socks5 disabled, reset port
    if (!_cfg.enableSocks5) _cfg.socks5Port = 1080;
    // If noTun, clear devName
    if (_cfg.noTun) _cfg.devName = '';
    // If secureMode off, clear keys
    if (!_cfg.secureMode) {
      _cfg.localPrivateKey = '';
      _cfg.localPublicKey = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Network' : 'Edit Network'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          const SizedBox(width: 4),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildIdentity(),
            _gap,
            _buildIpConfig(),
            _gap,
            _buildConnectivity(),
            _gap,
            _buildProxyRouting(),
            _gap,
            _buildPortForwarding(),
            _gap,
            _buildTunnelProtocols(),
            _gap,
            _buildSecurity(),
            _gap,
            _buildP2pNat(),
            _gap,
            _buildRelay(),
            _gap,
            _buildFeatures(),
            _gap,
            _buildPerformance(),
            _gap,
            _buildDevice(),
            _gap,
            _buildWhitelists(),
            _gap,
            _buildStun(),
            _gap,
            _buildRpc(),
            _gap,
            _buildLogging(),
            _gap,
            _buildAppSettings(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: 10);

  // ═══════════════════════════════════════════════════════════════════════
  // 1. Identity
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildIdentity() {
    return _Section(
      title: 'Identity',
      icon: Icons.badge_outlined,
      children: [
        _Field(
          label: 'Config Name',
          hint: 'My Network',
          initial: _cfg.configName,
          helperText: 'Display name in this app only',
          onSaved: (v) => _cfg.configName = v ?? '',
        ),
        _Field(
          label: 'Network Name',
          hint: 'easytier-network',
          initial: _cfg.networkName,
          onSaved: (v) => _cfg.networkName = v ?? '',
          validator: (v) =>
              v == null || v.isEmpty ? 'Network name is required' : null,
        ),
        _Field(
          label: 'Network Secret',
          hint: 'shared-secret',
          initial: _cfg.networkSecret,
          obscure: true,
          helperText: 'Shared passphrase for network authentication',
          onSaved: (v) => _cfg.networkSecret = v ?? '',
        ),
        _Field(
          label: 'Hostname',
          hint: 'my-node',
          initial: _cfg.hostname,
          helperText: 'Node name visible to other peers',
          onSaved: (v) => _cfg.hostname = v ?? '',
        ),
        _Field(
          label: 'Instance Name',
          hint: 'Leave empty for auto',
          initial: _cfg.instanceName,
          helperText: 'Unique name when running multiple instances',
          onSaved: (v) => _cfg.instanceName = v ?? '',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. IP Configuration
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildIpConfig() {
    return _Section(
      title: 'IP Configuration',
      icon: Icons.dns_outlined,
      children: [
        _ToggleRow(
          title: 'DHCP',
          subtitle: 'Auto-assign virtual IP address',
          value: _cfg.dhcp,
          onChanged: (v) {
            _cfg.dhcp = v;
            _rebuild();
          },
        ),
        // IPv4: hidden when DHCP is on
        if (!_cfg.dhcp) ...[
          const SizedBox(height: 8),
          _Field(
            label: 'Virtual IPv4',
            hint: '10.0.0.1',
            initial: _cfg.virtualIpv4,
            helperText: 'Manual virtual IP (ignored when DHCP is on)',
            onSaved: (v) => _cfg.virtualIpv4 = v ?? '',
          ),
        ],
        // IPv6: only shown when DHCP off AND IPv6 not disabled
        if (!_cfg.dhcp && !_cfg.disableIpv6)
          _Field(
            label: 'Virtual IPv6',
            hint: 'fd00::1',
            initial: _cfg.virtualIpv6,
            onSaved: (v) => _cfg.virtualIpv6 = v ?? '',
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. Connectivity
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildConnectivity() {
    return _Section(
      title: 'Connectivity',
      icon: Icons.cable,
      children: [
        StringListEditor(
          label: 'Peer URLs',
          hint: 'tcp://1.2.3.4:11010',
          items: _cfg.peerUrls,
          onChanged: (v) {
            _cfg.peerUrls = v;
            _rebuild();
          },
        ),
        const SizedBox(height: 12),
        _Field(
          label: 'External Node',
          hint: 'tcp://public-node:11010',
          initial: _cfg.externalNode,
          helperText: 'Public relay/connector node URL',
          onSaved: (v) => _cfg.externalNode = v ?? '',
        ),
        const Divider(height: 24),
        _ToggleRow(
          title: 'No Listener',
          subtitle: 'Don\'t listen for incoming connections',
          value: _cfg.noListener,
          onChanged: (v) {
            _cfg.noListener = v;
            _rebuild();
          },
        ),
        // Listeners: hidden when noListener is true
        if (!_cfg.noListener) ...[
          const SizedBox(height: 12),
          StringListEditor(
            label: 'Listeners',
            hint: 'tcp://0.0.0.0:11010',
            items: _cfg.listeners,
            onChanged: (v) {
              _cfg.listeners = v;
              _rebuild();
            },
          ),
          const SizedBox(height: 12),
          StringListEditor(
            label: 'Mapped Listeners',
            hint: 'tcp://public-ip:11010',
            items: _cfg.mappedListeners,
            onChanged: (v) {
              _cfg.mappedListeners = v;
              _rebuild();
            },
          ),
        ],
        const SizedBox(height: 12),
        _DropdownField(
          label: 'Default Protocol',
          value: _cfg.defaultProtocol.isEmpty ? null : _cfg.defaultProtocol,
          items: const {
            '': 'Auto',
            'tcp': 'TCP',
            'udp': 'UDP',
            'ws': 'WebSocket',
            'wss': 'WebSocket TLS',
          },
          onChanged: (v) {
            _cfg.defaultProtocol = v ?? '';
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. Proxy & Routing
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildProxyRouting() {
    return _Section(
      title: 'Proxy & Routing',
      icon: Icons.alt_route,
      children: [
        StringListEditor(
          label: 'Proxy CIDRs',
          hint: '192.168.1.0/24',
          items: _cfg.proxyCidrs,
          onChanged: (v) {
            _cfg.proxyCidrs = v;
            _rebuild();
          },
        ),
        const SizedBox(height: 12),
        _ToggleRow(
          title: 'Proxy Forward by System',
          subtitle: 'Use system routing table for proxy traffic',
          value: _cfg.proxyForwardBySystem,
          onChanged: (v) {
            _cfg.proxyForwardBySystem = v;
            _rebuild();
          },
        ),
        const SizedBox(height: 12),
        StringListEditor(
          label: 'Exit Nodes',
          hint: '10.0.0.2',
          items: _cfg.exitNodes,
          onChanged: (v) {
            _cfg.exitNodes = v;
            _rebuild();
          },
        ),
        _ToggleRow(
          title: 'Enable Exit Node',
          subtitle: 'Allow other peers to route through this node',
          value: _cfg.enableExitNode,
          onChanged: (v) {
            _cfg.enableExitNode = v;
            _rebuild();
          },
        ),
        const SizedBox(height: 12),
        StringListEditor(
          label: 'Manual Routes',
          hint: 'cidr,next_hop_peer_id',
          items: _cfg.manualRoutes,
          onChanged: (v) {
            _cfg.manualRoutes = v;
            _rebuild();
          },
        ),
        _ToggleRow(
          title: 'Latency First',
          subtitle: 'Prefer lowest-latency routes over lowest-cost',
          value: _cfg.latencyFirst,
          onChanged: (v) {
            _cfg.latencyFirst = v;
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. Port Forwarding
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPortForwarding() {
    return _Section(
      title: 'Port Forwarding',
      icon: Icons.swap_calls,
      children: [
        PortForwardEditor(
          items: _cfg.portForwards,
          onChanged: _rebuild,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. Tunnel Protocols
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTunnelProtocols() {
    return _Section(
      title: 'Tunnel Protocols',
      icon: Icons.layers_outlined,
      children: [
        // KCP
        _ToggleRow(
          title: 'Enable KCP Proxy',
          subtitle: 'Use KCP for accelerated TCP-over-UDP',
          value: _cfg.enableKcpProxy,
          onChanged: (v) {
            _cfg.enableKcpProxy = v;
            // If disabling KCP proxy, also clear disable input
            if (!v) _cfg.disableKcpInput = false;
            _rebuild();
          },
        ),
        // disableKcpInput: only meaningful when KCP is enabled
        if (_cfg.enableKcpProxy)
          _ToggleRow(
            title: 'Disable KCP Input',
            subtitle: 'Don\'t accept incoming KCP connections',
            value: _cfg.disableKcpInput,
            onChanged: (v) {
              _cfg.disableKcpInput = v;
              _rebuild();
            },
            indent: true,
          ),
        const Divider(height: 16),
        // QUIC
        _ToggleRow(
          title: 'Enable QUIC Proxy',
          subtitle: 'Use QUIC protocol for tunnels',
          value: _cfg.enableQuicProxy,
          onChanged: (v) {
            _cfg.enableQuicProxy = v;
            if (!v) _cfg.disableQuicInput = false;
            _rebuild();
          },
        ),
        // disableQuicInput: only meaningful when QUIC is enabled
        if (_cfg.enableQuicProxy)
          _ToggleRow(
            title: 'Disable QUIC Input',
            subtitle: 'Don\'t accept incoming QUIC connections',
            value: _cfg.disableQuicInput,
            onChanged: (v) {
              _cfg.disableQuicInput = v;
              _rebuild();
            },
            indent: true,
          ),
        const Divider(height: 16),
        // IPv6
        _ToggleRow(
          title: 'Disable IPv6',
          subtitle: 'Don\'t use IPv6 for tunnels',
          value: _cfg.disableIpv6,
          onChanged: (v) {
            _cfg.disableIpv6 = v;
            // If disabling IPv6, clear manual v6 address
            if (v) _cfg.virtualIpv6 = '';
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 7. Security & Encryption
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSecurity() {
    return _Section(
      title: 'Security & Encryption',
      icon: Icons.shield_outlined,
      children: [
        _ToggleRow(
          title: 'Disable Encryption',
          subtitle: 'NOT recommended - traffic will be unencrypted',
          value: _cfg.disableEncryption,
          warn: true,
          onChanged: (v) {
            _cfg.disableEncryption = v;
            if (v) _cfg.encryptionAlgorithm = '';
            _rebuild();
          },
        ),
        // Algorithm: only when encryption is enabled
        if (!_cfg.disableEncryption) ...[
          const SizedBox(height: 8),
          _DropdownField(
            label: 'Encryption Algorithm',
            value: _cfg.encryptionAlgorithm.isEmpty
                ? null
                : _cfg.encryptionAlgorithm,
            items: const {
              '': 'Default (AES-GCM)',
              'aes-gcm': 'AES-GCM',
              'chacha20-poly1305': 'ChaCha20-Poly1305',
            },
            onChanged: (v) {
              _cfg.encryptionAlgorithm = v ?? '';
              _rebuild();
            },
          ),
        ],
        const Divider(height: 20),
        _ToggleRow(
          title: 'Private Mode',
          subtitle: 'Only accept connections from trusted peers',
          value: _cfg.privateMode,
          onChanged: (v) {
            _cfg.privateMode = v;
            _rebuild();
          },
        ),
        const Divider(height: 20),
        _ToggleRow(
          title: 'Secure Mode',
          subtitle: 'Use X25519 key-pair for node identity',
          value: _cfg.secureMode,
          onChanged: (v) {
            _cfg.secureMode = v;
            if (!v) {
              _cfg.localPrivateKey = '';
              _cfg.localPublicKey = '';
            }
            _rebuild();
          },
        ),
        // Key fields: only when secure mode is enabled
        if (_cfg.secureMode) ...[
          const SizedBox(height: 8),
          _Field(
            label: 'Local Private Key',
            hint: 'X25519 private key (hex/base64)',
            initial: _cfg.localPrivateKey,
            obscure: true,
            onSaved: (v) => _cfg.localPrivateKey = v ?? '',
            indent: true,
          ),
          _Field(
            label: 'Local Public Key',
            hint: 'X25519 public key (hex/base64)',
            initial: _cfg.localPublicKey,
            onSaved: (v) => _cfg.localPublicKey = v ?? '',
            indent: true,
          ),
        ],
        const Divider(height: 20),
        _Field(
          label: 'Credential',
          hint: 'Inline credential token',
          initial: _cfg.credential,
          obscure: true,
          helperText: 'Temporary credential for network access',
          onSaved: (v) => _cfg.credential = v ?? '',
        ),
        _Field(
          label: 'Credential File',
          hint: '/path/to/credential.json',
          initial: _cfg.credentialFile,
          helperText: 'Path to credential file on disk',
          onSaved: (v) => _cfg.credentialFile = v ?? '',
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 8. P2P & NAT Traversal
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildP2pNat() {
    return _Section(
      title: 'P2P & NAT Traversal',
      icon: Icons.hub_outlined,
      children: [
        // Top-level P2P mode selector: these three are mutually exclusive
        _ToggleRow(
          title: 'Disable P2P',
          subtitle: 'Force relay-only mode (no direct connections)',
          value: _cfg.disableP2p,
          // Cannot enable if p2pOnly is on
          onChanged: _cfg.p2pOnly
              ? null
              : (v) {
                  _cfg.disableP2p = v;
                  if (v) {
                    // Clear all P2P sub-options
                    _cfg.needP2p = false;
                    _cfg.lazyP2p = false;
                    _cfg.p2pOnly = false;
                    _cfg.disableUdpHolePunching = false;
                    _cfg.disableTcpHolePunching = false;
                    _cfg.disableSymHolePunching = false;
                  }
                  _rebuild();
                },
        ),
        _ToggleRow(
          title: 'P2P Only',
          subtitle:
              'Only use direct connections, never relay (mutually exclusive with Disable P2P)',
          value: _cfg.p2pOnly,
          // Cannot enable if disableP2p is on
          onChanged: _cfg.disableP2p
              ? null
              : (v) {
                  _cfg.p2pOnly = v;
                  if (v) _cfg.disableP2p = false;
                  _rebuild();
                },
        ),

        // All P2P sub-options: hidden when P2P is disabled
        if (!_cfg.disableP2p) ...[
          const Divider(height: 16),
          // needP2p and lazyP2p are mutually exclusive
          _ToggleRow(
            title: 'Need P2P',
            subtitle:
                'Require P2P connections (fail if unavailable). Mutually exclusive with Lazy P2P',
            value: _cfg.needP2p,
            onChanged: (v) {
              _cfg.needP2p = v;
              if (v) _cfg.lazyP2p = false;
              _rebuild();
            },
          ),
          _ToggleRow(
            title: 'Lazy P2P',
            subtitle:
                'Delay P2P establishment until traffic detected. Mutually exclusive with Need P2P',
            value: _cfg.lazyP2p,
            // Cannot enable if needP2p is on
            onChanged: _cfg.needP2p
                ? null
                : (v) {
                    _cfg.lazyP2p = v;
                    _rebuild();
                  },
          ),

          const Divider(height: 16),
          _SectionSubtitle(text: 'Hole Punching'),
          _ToggleRow(
            title: 'Disable UDP Hole Punching',
            value: _cfg.disableUdpHolePunching,
            onChanged: (v) {
              _cfg.disableUdpHolePunching = v;
              _rebuild();
            },
          ),
          _ToggleRow(
            title: 'Disable TCP Hole Punching',
            value: _cfg.disableTcpHolePunching,
            onChanged: (v) {
              _cfg.disableTcpHolePunching = v;
              _rebuild();
            },
          ),
          _ToggleRow(
            title: 'Disable Symmetric NAT Hole Punching',
            value: _cfg.disableSymHolePunching,
            onChanged: (v) {
              _cfg.disableSymHolePunching = v;
              _rebuild();
            },
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 9. Relay
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildRelay() {
    final hasWhitelist = _cfg.relayNetworkWhitelist.isNotEmpty;

    return _Section(
      title: 'Relay',
      icon: Icons.repeat,
      children: [
        _ToggleRow(
          title: 'Relay All Peer RPC',
          subtitle: 'Forward all peer RPC traffic through relay',
          value: _cfg.relayAllPeerRpc,
          onChanged: (v) {
            _cfg.relayAllPeerRpc = v;
            _rebuild();
          },
        ),
        const Divider(height: 16),
        StringListEditor(
          label:
              'Relay Network Whitelist${hasWhitelist ? " (enabled)" : " (empty = allow all)"}',
          hint: 'network-name',
          items: _cfg.relayNetworkWhitelist,
          onChanged: (v) {
            _cfg.relayNetworkWhitelist = v;
            _rebuild();
          },
        ),
        const Divider(height: 16),
        _SectionSubtitle(text: 'Relay Protocol Control'),
        _ToggleRow(
          title: 'Disable Relay KCP',
          subtitle: 'Don\'t use KCP for relay traffic',
          value: _cfg.disableRelayKcp,
          onChanged: (v) {
            _cfg.disableRelayKcp = v;
            _rebuild();
          },
        ),
        _ToggleRow(
          title: 'Disable Relay QUIC',
          subtitle: 'Don\'t use QUIC for relay traffic',
          value: _cfg.disableRelayQuic,
          onChanged: (v) {
            _cfg.disableRelayQuic = v;
            _rebuild();
          },
        ),
        _ToggleRow(
          title: 'Enable Relay Foreign Network KCP',
          subtitle: 'Use KCP for foreign network relay',
          value: _cfg.enableRelayForeignNetworkKcp,
          onChanged: (v) {
            _cfg.enableRelayForeignNetworkKcp = v;
            _rebuild();
          },
        ),
        _ToggleRow(
          title: 'Enable Relay Foreign Network QUIC',
          subtitle: 'Use QUIC for foreign network relay',
          value: _cfg.enableRelayForeignNetworkQuic,
          onChanged: (v) {
            _cfg.enableRelayForeignNetworkQuic = v;
            _rebuild();
          },
        ),
        const SizedBox(height: 8),
        _Field(
          label: 'Foreign Relay BPS Limit',
          hint: '0 = unlimited',
          initial: _cfg.foreignRelayBpsLimit > 0
              ? '${_cfg.foreignRelayBpsLimit}'
              : '',
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          helperText: 'Bandwidth limit for foreign relay (bytes/sec)',
          onSaved: (v) =>
              _cfg.foreignRelayBpsLimit = int.tryParse(v ?? '') ?? 0,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 10. Features
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFeatures() {
    return _Section(
      title: 'Features',
      icon: Icons.extension_outlined,
      children: [
        // DNS
        _ToggleRow(
          title: 'Enable Magic DNS',
          subtitle: 'Resolve peer hostnames within VPN',
          value: _cfg.enableMagicDns,
          onChanged: (v) {
            _cfg.enableMagicDns = v;
            if (!v) _cfg.acceptDns = false;
            _rebuild();
          },
        ),
        if (_cfg.enableMagicDns) ...[
          _ToggleRow(
            title: 'Accept DNS',
            subtitle: 'Accept DNS records from other peers',
            value: _cfg.acceptDns,
            onChanged: (v) {
              _cfg.acceptDns = v;
              _rebuild();
            },
            indent: true,
          ),
          _Field(
            label: 'TLD DNS Zone',
            hint: 'et',
            initial: _cfg.tldDnsZone,
            helperText: 'Top-level domain zone for magic DNS',
            onSaved: (v) => _cfg.tldDnsZone = v ?? '',
            indent: true,
          ),
        ],
        const Divider(height: 16),
        // SOCKS5
        _ToggleRow(
          title: 'Enable SOCKS5 Proxy',
          subtitle: 'Expose a local SOCKS5 proxy into the VPN',
          value: _cfg.enableSocks5,
          onChanged: (v) {
            _cfg.enableSocks5 = v;
            _rebuild();
          },
        ),
        if (_cfg.enableSocks5)
          _Field(
            label: 'SOCKS5 Port',
            hint: '1080',
            initial: '${_cfg.socks5Port}',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            onSaved: (v) => _cfg.socks5Port = int.tryParse(v ?? '') ?? 1080,
            indent: true,
          ),
        const Divider(height: 16),
        // VPN Portal (WireGuard)
        _Field(
          label: 'VPN Portal',
          hint: '0.0.0.0:11012',
          initial: _cfg.vpnPortal,
          helperText:
              'WireGuard-compatible portal (ip:port). Leave empty to disable',
          onSaved: (v) => _cfg.vpnPortal = v ?? '',
        ),
        const Divider(height: 16),
        // TUN
        _ToggleRow(
          title: 'No TUN',
          subtitle:
              'Don\'t create TUN device (useful for relay-only nodes)',
          value: _cfg.noTun,
          onChanged: (v) {
            _cfg.noTun = v;
            if (v) _cfg.devName = '';
            _rebuild();
          },
        ),
        _ToggleRow(
          title: 'Use smoltcp',
          subtitle: 'Use userspace TCP/IP stack instead of system TUN',
          value: _cfg.useSmoltcp,
          onChanged: (v) {
            _cfg.useSmoltcp = v;
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 11. Performance
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPerformance() {
    return _Section(
      title: 'Performance',
      icon: Icons.speed,
      children: [
        _ToggleRow(
          title: 'Multi-Thread',
          subtitle: 'Enable multi-threaded processing',
          value: _cfg.multiThread,
          onChanged: (v) {
            _cfg.multiThread = v;
            if (!v) _cfg.multiThreadCount = 0;
            _rebuild();
          },
        ),
        if (_cfg.multiThread)
          _Field(
            label: 'Thread Count',
            hint: '0 = auto (num CPUs)',
            initial:
                _cfg.multiThreadCount > 0 ? '${_cfg.multiThreadCount}' : '',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            onSaved: (v) =>
                _cfg.multiThreadCount = int.tryParse(v ?? '') ?? 0,
            indent: true,
          ),
        _Field(
          label: 'MTU',
          hint: '1380',
          initial: '${_cfg.mtu}',
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          helperText: 'Maximum transmission unit for tunnel packets',
          onSaved: (v) => _cfg.mtu = int.tryParse(v ?? '') ?? 1380,
        ),
        _Field(
          label: 'Instance Receive BPS Limit',
          hint: '0 = unlimited',
          initial: _cfg.instanceRecvBpsLimit > 0
              ? '${_cfg.instanceRecvBpsLimit}'
              : '',
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          helperText: 'Bandwidth limit in bytes/sec',
          onSaved: (v) =>
              _cfg.instanceRecvBpsLimit = int.tryParse(v ?? '') ?? 0,
        ),
        const SizedBox(height: 8),
        _DropdownField(
          label: 'Compression',
          value: _cfg.compression.isEmpty ? null : _cfg.compression,
          items: const {
            '': 'None',
            'zstd': 'Zstd',
          },
          onChanged: (v) {
            _cfg.compression = v ?? '';
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 12. Device
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDevice() {
    return _Section(
      title: 'Device',
      icon: Icons.settings_ethernet,
      children: [
        // devName: hidden when noTun is on
        if (!_cfg.noTun)
          _Field(
            label: 'TUN Device Name',
            hint: 'Leave empty for default',
            initial: _cfg.devName,
            helperText: 'Custom name for the TUN network interface',
            onSaved: (v) => _cfg.devName = v ?? '',
          ),
        if (_cfg.noTun)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'TUN device is disabled (No TUN is on)',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ),
        _ToggleRow(
          title: 'Bind Device',
          subtitle: 'Bind tunnel sockets to a specific network device',
          value: _cfg.bindDevice,
          onChanged: (v) {
            _cfg.bindDevice = v;
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 13. Whitelists
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildWhitelists() {
    return _Section(
      title: 'Port Whitelists',
      icon: Icons.checklist,
      children: [
        StringListEditor(
          label: 'TCP Port Whitelist',
          hint: '22,80,443 or 8000-9000',
          items: _cfg.tcpWhitelist,
          onChanged: (v) {
            _cfg.tcpWhitelist = v;
            _rebuild();
          },
        ),
        const SizedBox(height: 12),
        StringListEditor(
          label: 'UDP Port Whitelist',
          hint: '53,51820',
          items: _cfg.udpWhitelist,
          onChanged: (v) {
            _cfg.udpWhitelist = v;
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 14. STUN
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStun() {
    return _Section(
      title: 'STUN Servers',
      icon: Icons.public,
      children: [
        StringListEditor(
          label: 'STUN Servers (IPv4)',
          hint: 'stun.l.google.com:19302',
          items: _cfg.stunServers,
          onChanged: (v) {
            _cfg.stunServers = v;
            _rebuild();
          },
        ),
        // IPv6 STUN: hidden when IPv6 is disabled
        if (!_cfg.disableIpv6) ...[
          const SizedBox(height: 12),
          StringListEditor(
            label: 'STUN Servers (IPv6)',
            hint: 'stun6.l.google.com:19302',
            items: _cfg.stunServersV6,
            onChanged: (v) {
              _cfg.stunServersV6 = v;
              _rebuild();
            },
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 15. RPC
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildRpc() {
    return _Section(
      title: 'RPC Portal',
      icon: Icons.api,
      children: [
        _Field(
          label: 'RPC Port',
          hint: '15888',
          initial: '${_cfg.rpcPort}',
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          helperText: 'Local management RPC port (127.0.0.1:<port>)',
          onSaved: (v) => _cfg.rpcPort = int.tryParse(v ?? '') ?? 15888,
        ),
        StringListEditor(
          label: 'RPC Portal Whitelist',
          hint: '127.0.0.1/32',
          items: _cfg.rpcPortalWhitelist,
          onChanged: (v) {
            _cfg.rpcPortalWhitelist = v;
            _rebuild();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 16. Logging
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLogging() {
    return _Section(
      title: 'Logging',
      icon: Icons.article_outlined,
      children: [
        _DropdownField(
          label: 'Console Log Level',
          value: _cfg.consoleLogLevel,
          items: _logLevels,
          onChanged: (v) {
            _cfg.consoleLogLevel = v ?? 'info';
            _rebuild();
          },
        ),
        const SizedBox(height: 12),
        _DropdownField(
          label: 'File Log Level',
          value: _cfg.fileLogLevel.isEmpty ? null : _cfg.fileLogLevel,
          items: const {
            '': 'Disabled',
            ..._logLevels,
          },
          onChanged: (v) {
            _cfg.fileLogLevel = v ?? '';
            _rebuild();
          },
        ),
        // File logging sub-options: only when file logging is enabled
        if (_cfg.fileLogLevel.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Field(
            label: 'File Log Directory',
            hint: '/var/log/easytier',
            initial: _cfg.fileLogDir,
            helperText: 'Directory for log files',
            onSaved: (v) => _cfg.fileLogDir = v ?? '',
            indent: true,
          ),
          _Field(
            label: 'File Log Size (MB)',
            hint: '10',
            initial:
                _cfg.fileLogSizeMb > 0 ? '${_cfg.fileLogSizeMb}' : '',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            helperText: 'Max size per log file in MB',
            onSaved: (v) =>
                _cfg.fileLogSizeMb = int.tryParse(v ?? '') ?? 0,
            indent: true,
          ),
          _Field(
            label: 'File Log Count',
            hint: '5',
            initial: _cfg.fileLogCount > 0 ? '${_cfg.fileLogCount}' : '',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            helperText: 'Max number of rotated log files',
            onSaved: (v) =>
                _cfg.fileLogCount = int.tryParse(v ?? '') ?? 0,
            indent: true,
          ),
        ],
      ],
    );
  }

  static const _logLevels = {
    'trace': 'Trace',
    'debug': 'Debug',
    'info': 'Info',
    'warn': 'Warn',
    'error': 'Error',
  };

  // ═══════════════════════════════════════════════════════════════════════
  // 17. App Settings
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAppSettings() {
    return _Section(
      title: 'App Settings',
      icon: Icons.tune,
      children: [
        _ToggleRow(
          title: 'Auto-start',
          subtitle: 'Automatically start this network when the app launches',
          value: _cfg.autoStart,
          onChanged: (v) {
            _cfg.autoStart = v;
            _rebuild();
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═══════════════════════════════════════════════════════════════════════════

class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child:
                        Icon(Icons.expand_more, size: 20, color: cs.outline),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.warn = false,
    this.indent = false,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool warn;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: indent ? 24 : 0),
      child: SwitchListTile(
        title: Text(title,
            style: TextStyle(
              color: disabled ? cs.outline : null,
              decoration: disabled ? TextDecoration.lineThrough : null,
            )),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(
                    fontSize: 12,
                    color: warn && value ? cs.error : cs.outline))
            : null,
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }
}

class _SectionSubtitle extends StatelessWidget {
  const _SectionSubtitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    this.hint,
    this.initial,
    this.obscure = false,
    this.keyboard,
    this.formatters,
    this.onSaved,
    this.validator,
    this.helperText,
    this.indent = false,
  });
  final String label;
  final String? hint;
  final String? initial;
  final bool obscure;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String?>? onSaved;
  final FormFieldValidator<String>? validator;
  final String? helperText;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12, left: indent ? 24 : 0),
      child: TextFormField(
        initialValue: initial,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: formatters,
        onSaved: onSaved,
        validator: validator,
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
    // Ensure value exists in items or fallback to first key
    final effectiveValue =
        items.containsKey(value) ? value : items.keys.first;

    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
