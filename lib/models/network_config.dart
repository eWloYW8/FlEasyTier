import 'package:toml/toml.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
final Map<String, dynamic> _defaultFlags = {
  'default_protocol': 'tcp',
  'dev_name': '',
  'enable_encryption': true,
  'enable_ipv6': true,
  'mtu': 1380,
  'latency_first': false,
  'enable_exit_node': false,
  'proxy_forward_by_system': false,
  'no_tun': false,
  'use_smoltcp': false,
  'relay_network_whitelist': '*',
  'disable_p2p': false,
  'p2p_only': false,
  'lazy_p2p': false,
  'relay_all_peer_rpc': false,
  'disable_tcp_hole_punching': false,
  'disable_udp_hole_punching': false,
  'multi_thread': true,
  'data_compress_algo': 1,
  'bind_device': true,
  'enable_kcp_proxy': false,
  'disable_kcp_input': false,
  'disable_relay_kcp': false,
  'enable_relay_foreign_network_kcp': false,
  'accept_dns': false,
  'private_mode': false,
  'enable_quic_proxy': false,
  'disable_quic_input': false,
  'disable_relay_quic': false,
  'enable_relay_foreign_network_quic': false,
  'multi_thread_count': 2,
  'encryption_algorithm': 'aes-gcm',
  'disable_sym_hole_punching': false,
  'tld_dns_zone': 'et.net.',
  'quic_listen_port': 4294967295,
  'need_p2p': false,
};

class OfficialPeerConfig {
  String uri;
  String peerPublicKey;

  OfficialPeerConfig({
    this.uri = '',
    this.peerPublicKey = '',
  });

  factory OfficialPeerConfig.fromTomlMap(Map<String, dynamic> map) =>
      OfficialPeerConfig(
        uri: _asString(map['uri']),
        peerPublicKey: _asString(map['peer_public_key']),
      );

  OfficialPeerConfig copy() => OfficialPeerConfig(
        uri: uri,
        peerPublicKey: peerPublicKey,
      );

  Map<String, dynamic> toTomlMap() {
    final map = <String, dynamic>{};
    if (uri.trim().isNotEmpty) map['uri'] = uri.trim();
    if (peerPublicKey.trim().isNotEmpty) {
      map['peer_public_key'] = peerPublicKey.trim();
    }
    return map;
  }
}

class OfficialProxyNetworkConfig {
  String cidr;
  String mappedCidr;
  List<String> allow;

  OfficialProxyNetworkConfig({
    this.cidr = '',
    this.mappedCidr = '',
    List<String>? allow,
  }) : allow = allow ?? <String>[];

  factory OfficialProxyNetworkConfig.fromTomlMap(Map<String, dynamic> map) =>
      OfficialProxyNetworkConfig(
        cidr: _asString(map['cidr']),
        mappedCidr: _asString(map['mapped_cidr']),
        allow: _asStringList(map['allow']),
      );

  OfficialProxyNetworkConfig copy() => OfficialProxyNetworkConfig(
        cidr: cidr,
        mappedCidr: mappedCidr,
        allow: List<String>.from(allow),
      );

  Map<String, dynamic> toTomlMap() {
    final map = <String, dynamic>{};
    if (cidr.trim().isNotEmpty) map['cidr'] = cidr.trim();
    if (mappedCidr.trim().isNotEmpty) map['mapped_cidr'] = mappedCidr.trim();
    if (allow.isNotEmpty) {
      map['allow'] =
          allow.map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
    }
    return map;
  }
}

class PortForwardConfig {
  String bindAddr;
  String dstAddr;
  String proto;

  PortForwardConfig({
    String? bindAddr,
    String? dstAddr,
    String bindIp = '0.0.0.0',
    int bindPort = 0,
    String dstIp = '',
    int dstPort = 0,
    this.proto = 'tcp',
  })  : bindAddr = bindAddr ?? _joinHostPort(bindIp, bindPort),
        dstAddr = dstAddr ?? _joinHostPort(dstIp, dstPort);

  factory PortForwardConfig.fromTomlMap(Map<String, dynamic> map) =>
      PortForwardConfig(
        bindAddr: _asString(map['bind_addr']),
        dstAddr: _asString(map['dst_addr']),
        proto: _asString(map['proto'], fallback: 'tcp'),
      );

  PortForwardConfig copy() => PortForwardConfig(
        bindAddr: bindAddr,
        dstAddr: dstAddr,
        proto: proto,
      );

  Map<String, dynamic> toTomlMap() {
    final map = <String, dynamic>{};
    if (bindAddr.trim().isNotEmpty) map['bind_addr'] = bindAddr.trim();
    if (dstAddr.trim().isNotEmpty) map['dst_addr'] = dstAddr.trim();
    if (proto.trim().isNotEmpty) map['proto'] = proto.trim();
    return map;
  }

  String get bindIp => _splitHostPort(bindAddr).$1;
  set bindIp(String value) => bindAddr = _joinHostPort(value, bindPort);

  int get bindPort => _splitHostPort(bindAddr).$2;
  set bindPort(int value) => bindAddr = _joinHostPort(bindIp, value);

  String get dstIp => _splitHostPort(dstAddr).$1;
  set dstIp(String value) => dstAddr = _joinHostPort(value, dstPort);

  int get dstPort => _splitHostPort(dstAddr).$2;
  set dstPort(int value) => dstAddr = _joinHostPort(dstIp, value);

  String get displayText => '$proto  $bindAddr -> $dstAddr';
}

class NetworkConfig {
  final String id;
  final Map<String, dynamic> _tomlData;
  String configName = '';
  String externalNode = '';
  String credential = '';

  bool autoStart;
  bool serviceEnabled;
  int rpcPort;
  List<String> rpcPortalWhitelist;

  NetworkConfig({
    String? id,
    Map<String, dynamic>? tomlData,
    this.autoStart = false,
    this.serviceEnabled = false,
    this.rpcPort = 15888,
    List<String>? rpcPortalWhitelist,
  })  : id = _normalizeId(id),
        _tomlData = _deepCopyMap(tomlData ?? <String, dynamic>{}),
        rpcPortalWhitelist = rpcPortalWhitelist ?? <String>[] {
    _setTopLevel('instance_id', this.id, removeIfEmpty: false);
  }

  factory NetworkConfig.fromJson(Map<String, dynamic> json) {
    final rawToml = json['toml_data'];
    return NetworkConfig(
      id: json['id'] as String?,
      tomlData: rawToml is Map ? rawToml.cast<String, dynamic>() : null,
      autoStart: json['auto_start'] as bool? ?? false,
      serviceEnabled: json['service_enabled'] as bool? ?? false,
      rpcPort: json['rpc_port'] as int? ?? 15888,
      rpcPortalWhitelist: _asStringList(json['rpc_portal_whitelist']),
    );
  }

  factory NetworkConfig.fromToml(
    String toml, {
    String? id,
    bool autoStart = false,
    bool serviceEnabled = false,
    int rpcPort = 15888,
    List<String>? rpcPortalWhitelist,
  }) {
    final parsed = TomlDocument.parse(toml).toMap();
    final rawId = _asString(parsed['instance_id']);
    final effectiveId = id ?? _normalizeId(rawId.isEmpty ? null : rawId);
    return NetworkConfig(
      id: effectiveId,
      tomlData: parsed,
      autoStart: autoStart,
      serviceEnabled: serviceEnabled,
      rpcPort: rpcPort,
      rpcPortalWhitelist: rpcPortalWhitelist,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'auto_start': autoStart,
        'service_enabled': serviceEnabled,
        'rpc_port': rpcPort,
        'rpc_portal_whitelist': List<String>.from(rpcPortalWhitelist),
        'toml_data': tomlData,
      };

  Map<String, dynamic> get tomlData => _deepCopyMap(_tomlData);

  String toToml() {
    final data = _deepCopyMap(_tomlData);
    data['instance_id'] = id;
    _removeDefaultFlags(data);
    _pruneEmptyValues(data);
    return TomlDocument.fromMap(data).toString();
  }

  NetworkConfig copyWith({
    bool? autoStart,
    bool? serviceEnabled,
    int? rpcPort,
    List<String>? rpcPortalWhitelist,
    Map<String, dynamic>? tomlData,
  }) {
    return NetworkConfig(
      id: id,
      tomlData: tomlData ?? _tomlData,
      autoStart: autoStart ?? this.autoStart,
      serviceEnabled: serviceEnabled ?? this.serviceEnabled,
      rpcPort: rpcPort ?? this.rpcPort,
      rpcPortalWhitelist: rpcPortalWhitelist ?? this.rpcPortalWhitelist,
    );
  }

  String get displayName {
    if (configName.trim().isNotEmpty) return configName.trim();
    if (instanceName.isNotEmpty) return instanceName;
    if (networkName.isNotEmpty) return networkName;
    if (hostname.isNotEmpty) return hostname;
    return id;
  }

  String get networkName => _getStringPath(const ['network_identity', 'network_name']);
  set networkName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _removePath(const ['network_identity', 'network_name']);
      return;
    }
    _setStringPath(const ['network_identity', 'network_name'], trimmed);
  }

  String get networkSecret =>
      _getStringPath(const ['network_identity', 'network_secret']);
  set networkSecret(String value) {
    final identity = _ensureMapPath(const ['network_identity']);
    identity['network_secret'] = value;
  }

  String get hostname => _getStringPath(const ['hostname']);
  set hostname(String value) => _setTopLevel('hostname', value.trim());

  String get instanceName => _getStringPath(const ['instance_name']);
  set instanceName(String value) => _setTopLevel('instance_name', value.trim());

  String get netns => _getStringPath(const ['netns']);
  set netns(String value) => _setTopLevel('netns', value.trim());

  String get virtualIpv4 => _getStringPath(const ['ipv4']);
  set virtualIpv4(String value) => _setTopLevel('ipv4', value.trim());

  String get virtualIpv6 => _getStringPath(const ['ipv6']);
  set virtualIpv6(String value) => _setTopLevel('ipv6', value.trim());

  bool get dhcp => _getBoolPath(const ['dhcp']);
  set dhcp(bool value) => _setTopLevel('dhcp', value, removeIfFalse: true);

  List<String> get listeners => _getStringListPath(const ['listeners']);
  set listeners(List<String> value) => _setTopLevel('listeners', _cleanList(value));

  List<String> get mappedListeners =>
      _getStringListPath(const ['mapped_listeners']);
  set mappedListeners(List<String> value) =>
      _setTopLevel('mapped_listeners', _cleanList(value));

  bool get noListener => listeners.isEmpty;
  set noListener(bool value) {
    if (value) {
      listeners = const <String>[];
    }
  }

  List<String> get exitNodes => _getStringListPath(const ['exit_nodes']);
  set exitNodes(List<String> value) => _setTopLevel('exit_nodes', _cleanList(value));

  List<String> get manualRoutes => _getStringListPath(const ['routes']);
  set manualRoutes(List<String> value) => _setTopLevel('routes', _cleanList(value));

  List<String> get tcpWhitelist => _getStringListPath(const ['tcp_whitelist']);
  set tcpWhitelist(List<String> value) =>
      _setTopLevel('tcp_whitelist', _cleanList(value));

  List<String> get udpWhitelist => _getStringListPath(const ['udp_whitelist']);
  set udpWhitelist(List<String> value) =>
      _setTopLevel('udp_whitelist', _cleanList(value));

  List<String> get stunServers => _getStringListPath(const ['stun_servers']);
  set stunServers(List<String> value) =>
      _setTopLevel('stun_servers', _cleanList(value));

  List<String> get stunServersV6 => _getStringListPath(const ['stun_servers_v6']);
  set stunServersV6(List<String> value) =>
      _setTopLevel('stun_servers_v6', _cleanList(value));

  List<OfficialPeerConfig> get peers => _getMapListPath(
        const ['peer'],
      ).map(OfficialPeerConfig.fromTomlMap).toList();
  set peers(List<OfficialPeerConfig> value) => _setTopLevel(
        'peer',
        value.map((entry) => entry.toTomlMap()).where((entry) => entry.isNotEmpty).toList(),
      );

  List<String> get peerUrls => peers.map((entry) => entry.uri).where((entry) => entry.isNotEmpty).toList();
  set peerUrls(List<String> value) {
    peers = value
        .map((uri) => OfficialPeerConfig(uri: uri.trim()))
        .where((entry) => entry.uri.isNotEmpty)
        .toList();
  }

  List<OfficialProxyNetworkConfig> get proxyNetworks => _getMapListPath(
        const ['proxy_network'],
      ).map(OfficialProxyNetworkConfig.fromTomlMap).toList();
  set proxyNetworks(List<OfficialProxyNetworkConfig> value) => _setTopLevel(
        'proxy_network',
        value.map((entry) => entry.toTomlMap()).where((entry) => entry.isNotEmpty).toList(),
      );

  List<String> get proxyCidrs =>
      proxyNetworks.map((entry) => entry.cidr).where((entry) => entry.isNotEmpty).toList();
  set proxyCidrs(List<String> value) {
    proxyNetworks = value
        .map((cidr) => OfficialProxyNetworkConfig(cidr: cidr.trim()))
        .where((entry) => entry.cidr.isNotEmpty)
        .toList();
  }

  String get socks5Proxy => _getStringPath(const ['socks5_proxy']);
  set socks5Proxy(String value) => _setTopLevel('socks5_proxy', value.trim());

  bool get enableSocks5 => socks5Proxy.isNotEmpty;
  set enableSocks5(bool value) {
    if (!value) {
      socks5Proxy = '';
      return;
    }
    if (socks5Proxy.isEmpty) {
      socks5Proxy = 'socks5://0.0.0.0:1080';
    }
  }

  int get socks5Port => _splitHostPort(_uriHostPort(socks5Proxy)).$2;
  set socks5Port(int value) {
    final host = _splitHostPort(_uriHostPort(socks5Proxy.isNotEmpty ? socks5Proxy : 'socks5://0.0.0.0:1080')).$1;
    socks5Proxy = 'socks5://${_joinHostPort(host.isEmpty ? '0.0.0.0' : host, value)}';
  }

  String get vpnPortalClientCidr =>
      _getStringPath(const ['vpn_portal_config', 'client_cidr']);
  set vpnPortalClientCidr(String value) =>
      _setStringPath(const ['vpn_portal_config', 'client_cidr'], value.trim());

  String get vpnPortalWireguardListen =>
      _getStringPath(const ['vpn_portal_config', 'wireguard_listen']);
  set vpnPortalWireguardListen(String value) => _setStringPath(
        const ['vpn_portal_config', 'wireguard_listen'],
        value.trim(),
      );

  String get vpnPortal {
    if (vpnPortalClientCidr.isEmpty && vpnPortalWireguardListen.isEmpty) return '';
    return '$vpnPortalClientCidr @ $vpnPortalWireguardListen'.trim();
  }

  set vpnPortal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      vpnPortalClientCidr = '';
      vpnPortalWireguardListen = '';
      return;
    }
    final parts = trimmed.split('@');
    if (parts.length == 2) {
      vpnPortalClientCidr = parts.first.trim();
      vpnPortalWireguardListen = parts.last.trim();
    } else {
      vpnPortalWireguardListen = trimmed;
    }
  }

  List<PortForwardConfig> get portForwards => _getMapListPath(
        const ['port_forward'],
      ).map(PortForwardConfig.fromTomlMap).toList();
  set portForwards(List<PortForwardConfig> value) => _setTopLevel(
        'port_forward',
        value.map((entry) => entry.toTomlMap()).where((entry) => entry.isNotEmpty).toList(),
      );

  String get credentialFile => _getStringPath(const ['credential_file']);
  set credentialFile(String value) => _setTopLevel('credential_file', value.trim());

  bool get secureModeEnabled => _getBoolPath(const ['secure_mode', 'enabled']);
  set secureModeEnabled(bool value) =>
      _setBoolPath(const ['secure_mode', 'enabled'], value);

  bool get secureMode => secureModeEnabled;
  set secureMode(bool value) => secureModeEnabled = value;

  String get localPrivateKey =>
      _getStringPath(const ['secure_mode', 'local_private_key']);
  set localPrivateKey(String value) => _setStringPath(
        const ['secure_mode', 'local_private_key'],
        value.trim(),
      );

  String get localPublicKey =>
      _getStringPath(const ['secure_mode', 'local_public_key']);
  set localPublicKey(String value) =>
      _setStringPath(const ['secure_mode', 'local_public_key'], value.trim());

  String get consoleLogLevel =>
      _getStringPath(const ['console_logger', 'level'], fallback: 'info');
  set consoleLogLevel(String value) =>
      _setStringPath(const ['console_logger', 'level'], value.trim());

  String get fileLogLevel => _getStringPath(const ['file_logger', 'level']);
  set fileLogLevel(String value) =>
      _setStringPath(const ['file_logger', 'level'], value.trim());

  String get fileLogFile => _getStringPath(const ['file_logger', 'file']);
  set fileLogFile(String value) =>
      _setStringPath(const ['file_logger', 'file'], value.trim());

  String get fileLogDir => _getStringPath(const ['file_logger', 'dir']);
  set fileLogDir(String value) =>
      _setStringPath(const ['file_logger', 'dir'], value.trim());

  int get fileLogSizeMb => _getIntPath(const ['file_logger', 'size_mb']);
  set fileLogSizeMb(int value) =>
      _setIntPath(const ['file_logger', 'size_mb'], value);

  int get fileLogCount => _getIntPath(const ['file_logger', 'count']);
  set fileLogCount(int value) => _setIntPath(const ['file_logger', 'count'], value);

  String get defaultProtocol =>
      _getFlagString('default_protocol', fallback: 'tcp');
  set defaultProtocol(String value) => _setFlagValue('default_protocol', value.trim());

  bool get enableExitNode => _getFlagBool('enable_exit_node');
  set enableExitNode(bool value) => _setFlagValue('enable_exit_node', value);

  bool get proxyForwardBySystem => _getFlagBool('proxy_forward_by_system');
  set proxyForwardBySystem(bool value) =>
      _setFlagValue('proxy_forward_by_system', value);

  bool get noTun => _getFlagBool('no_tun');
  set noTun(bool value) => _setFlagValue('no_tun', value);

  bool get useSmoltcp => _getFlagBool('use_smoltcp');
  set useSmoltcp(bool value) => _setFlagValue('use_smoltcp', value);

  bool get latencyFirst => _getFlagBool('latency_first');
  set latencyFirst(bool value) => _setFlagValue('latency_first', value);

  bool get multiThread => _getFlagBool('multi_thread', fallback: true);
  set multiThread(bool value) => _setFlagValue('multi_thread', value);

  int get multiThreadCount => _getFlagInt('multi_thread_count', fallback: 2);
  set multiThreadCount(int value) => _setFlagValue('multi_thread_count', value);

  int get mtu => _getFlagInt('mtu', fallback: 1380);
  set mtu(int value) => _setFlagValue('mtu', value);

  int get instanceRecvBpsLimit {
    final raw = _getFlagInt('instance_recv_bps_limit', fallback: 0);
    return raw <= 0 ? 0 : raw;
  }

  set instanceRecvBpsLimit(int value) {
    if (value <= 0) {
      _removeFlagValue('instance_recv_bps_limit');
      return;
    }
    _setFlagValue('instance_recv_bps_limit', value);
  }

  String get devName => _getFlagString('dev_name');
  set devName(String value) => _setFlagValue('dev_name', value.trim());

  bool get bindDevice => _getFlagBool('bind_device', fallback: true);
  set bindDevice(bool value) => _setFlagValue('bind_device', value);

  bool get enableKcpProxy => _getFlagBool('enable_kcp_proxy');
  set enableKcpProxy(bool value) => _setFlagValue('enable_kcp_proxy', value);

  bool get disableKcpInput => _getFlagBool('disable_kcp_input');
  set disableKcpInput(bool value) => _setFlagValue('disable_kcp_input', value);

  bool get enableQuicProxy => _getFlagBool('enable_quic_proxy');
  set enableQuicProxy(bool value) => _setFlagValue('enable_quic_proxy', value);

  bool get disableQuicInput => _getFlagBool('disable_quic_input');
  set disableQuicInput(bool value) =>
      _setFlagValue('disable_quic_input', value);

  bool get disableRelayKcp => _getFlagBool('disable_relay_kcp');
  set disableRelayKcp(bool value) => _setFlagValue('disable_relay_kcp', value);

  bool get disableRelayQuic => _getFlagBool('disable_relay_quic');
  set disableRelayQuic(bool value) => _setFlagValue('disable_relay_quic', value);

  bool get enableRelayForeignNetworkKcp =>
      _getFlagBool('enable_relay_foreign_network_kcp');
  set enableRelayForeignNetworkKcp(bool value) =>
      _setFlagValue('enable_relay_foreign_network_kcp', value);

  bool get enableRelayForeignNetworkQuic =>
      _getFlagBool('enable_relay_foreign_network_quic');
  set enableRelayForeignNetworkQuic(bool value) =>
      _setFlagValue('enable_relay_foreign_network_quic', value);

  int get foreignRelayBpsLimit {
    final raw = _getFlagInt('foreign_relay_bps_limit', fallback: 0);
    return raw <= 0 ? 0 : raw;
  }

  set foreignRelayBpsLimit(int value) {
    if (value <= 0) {
      _removeFlagValue('foreign_relay_bps_limit');
      return;
    }
    _setFlagValue('foreign_relay_bps_limit', value);
  }

  bool get acceptDns => _getFlagBool('accept_dns');
  set acceptDns(bool value) => _setFlagValue('accept_dns', value);

  bool get enableMagicDns => acceptDns;
  set enableMagicDns(bool value) => acceptDns = value;

  bool get privateMode => _getFlagBool('private_mode');
  set privateMode(bool value) => _setFlagValue('private_mode', value);

  bool get disableP2p => _getFlagBool('disable_p2p');
  set disableP2p(bool value) => _setFlagValue('disable_p2p', value);

  bool get p2pOnly => _getFlagBool('p2p_only');
  set p2pOnly(bool value) => _setFlagValue('p2p_only', value);

  bool get lazyP2p => _getFlagBool('lazy_p2p');
  set lazyP2p(bool value) => _setFlagValue('lazy_p2p', value);

  bool get needP2p => _getFlagBool('need_p2p');
  set needP2p(bool value) => _setFlagValue('need_p2p', value);

  bool get relayAllPeerRpc => _getFlagBool('relay_all_peer_rpc');
  set relayAllPeerRpc(bool value) => _setFlagValue('relay_all_peer_rpc', value);

  bool get disableTcpHolePunching =>
      _getFlagBool('disable_tcp_hole_punching');
  set disableTcpHolePunching(bool value) =>
      _setFlagValue('disable_tcp_hole_punching', value);

  bool get disableUdpHolePunching =>
      _getFlagBool('disable_udp_hole_punching');
  set disableUdpHolePunching(bool value) =>
      _setFlagValue('disable_udp_hole_punching', value);

  bool get disableSymHolePunching =>
      _getFlagBool('disable_sym_hole_punching');
  set disableSymHolePunching(bool value) =>
      _setFlagValue('disable_sym_hole_punching', value);

  bool get disableIpv6 => !_getFlagBool('enable_ipv6', fallback: true);
  set disableIpv6(bool value) => _setFlagValue('enable_ipv6', !value);

  bool get disableEncryption => !_getFlagBool('enable_encryption', fallback: true);
  set disableEncryption(bool value) => _setFlagValue('enable_encryption', !value);

  String get encryptionAlgorithm =>
      _getFlagString('encryption_algorithm', fallback: 'aes-gcm');
  set encryptionAlgorithm(String value) =>
      _setFlagValue('encryption_algorithm', value.trim());

  List<String> get relayNetworkWhitelist {
    final raw = _getFlagString('relay_network_whitelist', fallback: '*').trim();
    if (raw.isEmpty) return const <String>[];
    return raw.split(RegExp(r'[\s,]+')).where((item) => item.isNotEmpty).toList();
  }

  set relayNetworkWhitelist(List<String> value) {
    final normalized = _cleanList(value);
    _setFlagValue(
      'relay_network_whitelist',
      normalized.isEmpty ? '' : normalized.join(' '),
    );
  }

  bool get enableRelayNetworkWhitelist {
    final items = relayNetworkWhitelist;
    return items.isNotEmpty && !(items.length == 1 && items.first == '*');
  }

  set enableRelayNetworkWhitelist(bool value) {
    if (!value) {
      _setFlagValue('relay_network_whitelist', '*');
    } else if (!enableRelayNetworkWhitelist) {
      _setFlagValue('relay_network_whitelist', '');
    }
  }

  String get tldDnsZone => _getFlagString('tld_dns_zone', fallback: 'et.net.');
  set tldDnsZone(String value) => _setFlagValue('tld_dns_zone', value.trim());

  String get compression {
    final value = _getFlagInt('data_compress_algo', fallback: 1);
    return switch (value) {
      2 => 'zstd',
      _ => '',
    };
  }

  set compression(String value) {
    final normalized = value.trim().toLowerCase();
    final raw = switch (normalized) {
      'zstd' => 2,
      _ => 1,
    };
    _setFlagValue('data_compress_algo', raw);
  }

  Map<String, dynamic>? _getMapPath(List<String> path) {
    dynamic current = _tomlData;
    for (final segment in path) {
      if (current is Map && current[segment] is Map) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current.cast<String, dynamic>();
  }

  Map<String, dynamic> _ensureMapPath(List<String> path) {
    Map<String, dynamic> current = _tomlData;
    for (final segment in path) {
      final next = current[segment];
      if (next is Map<String, dynamic>) {
        current = next;
        continue;
      }
      if (next is Map) {
        current = next.cast<String, dynamic>();
        continue;
      }
      final created = <String, dynamic>{};
      current[segment] = created;
      current = created;
    }
    return current;
  }

  String _getStringPath(List<String> path, {String fallback = ''}) {
    dynamic current = _tomlData;
    for (final segment in path) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return fallback;
      }
    }
    return _asString(current, fallback: fallback);
  }

  List<String> _getStringListPath(List<String> path) {
    dynamic current = _tomlData;
    for (final segment in path) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return const <String>[];
      }
    }
    return _asStringList(current);
  }

  List<Map<String, dynamic>> _getMapListPath(List<String> path) {
    dynamic current = _tomlData;
    for (final segment in path) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return const <Map<String, dynamic>>[];
      }
    }
    if (current is! List) return const <Map<String, dynamic>>[];
    return current
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();
  }

  bool _getBoolPath(List<String> path, {bool fallback = false}) {
    dynamic current = _tomlData;
    for (final segment in path) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return fallback;
      }
    }
    return current is bool ? current : fallback;
  }

  int _getIntPath(List<String> path, {int fallback = 0}) {
    dynamic current = _tomlData;
    for (final segment in path) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return fallback;
      }
    }
    return _asInt(current, fallback: fallback);
  }

  void _setStringPath(List<String> path, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _removePath(path);
      return;
    }
    final parent = _ensureMapPath(path.sublist(0, path.length - 1));
    parent[path.last] = trimmed;
  }

  void _setBoolPath(List<String> path, bool value) {
    final parent = _ensureMapPath(path.sublist(0, path.length - 1));
    parent[path.last] = value;
    if (!value) {
      _removePath(path);
    }
  }

  void _setIntPath(List<String> path, int value) {
    if (value <= 0) {
      _removePath(path);
      return;
    }
    final parent = _ensureMapPath(path.sublist(0, path.length - 1));
    parent[path.last] = value;
  }

  void _setTopLevel(
    String key,
    dynamic value, {
    bool removeIfEmpty = true,
    bool removeIfFalse = false,
  }) {
    if (value == null) {
      _tomlData.remove(key);
      return;
    }
    if (removeIfEmpty && value is String && value.trim().isEmpty) {
      _tomlData.remove(key);
      return;
    }
    if (removeIfEmpty && value is List && value.isEmpty) {
      _tomlData.remove(key);
      return;
    }
    if (removeIfFalse && value == false) {
      _tomlData.remove(key);
      return;
    }
    _tomlData[key] = value;
  }

  void _removePath(List<String> path) {
    if (path.isEmpty) return;
    final parents = <Map<String, dynamic>>[];
    Map<String, dynamic>? current = _tomlData;
    for (int i = 0; i < path.length - 1; i++) {
      final next = current?[path[i]];
      if (next is Map<String, dynamic>) {
        parents.add(current!);
        current = next;
        continue;
      }
      if (next is Map) {
        parents.add(current!);
        current = next.cast<String, dynamic>();
        continue;
      }
      return;
    }
    current?.remove(path.last);
    for (int i = path.length - 2; i >= 0; i--) {
      final parent = i == 0 ? _tomlData : parents[i - 1][path[i - 1]] as Map<String, dynamic>;
      final childKey = path[i];
      final child = parent[childKey];
      if (child is Map && child.isEmpty) {
        parent.remove(childKey);
      }
    }
  }

  Map<String, dynamic> _flags() {
    final existing = _tomlData['flags'];
    if (existing is Map<String, dynamic>) return existing;
    if (existing is Map) return existing.cast<String, dynamic>();
    final created = <String, dynamic>{};
    _tomlData['flags'] = created;
    return created;
  }

  bool _getFlagBool(String key, {bool fallback = false}) {
    final flags = _getMapPath(const ['flags']);
    final value = flags?[key];
    if (value is bool) return value;
    final defaultValue = _defaultFlags[key];
    if (defaultValue is bool) return defaultValue;
    return fallback;
  }

  int _getFlagInt(String key, {int fallback = 0}) {
    final flags = _getMapPath(const ['flags']);
    final value = flags?[key];
    if (value != null) return _asInt(value, fallback: fallback);
    final defaultValue = _defaultFlags[key];
    if (defaultValue != null) return _asInt(defaultValue, fallback: fallback);
    return fallback;
  }

  String _getFlagString(String key, {String fallback = ''}) {
    final flags = _getMapPath(const ['flags']);
    final value = flags?[key];
    if (value != null) return _asString(value, fallback: fallback);
    final defaultValue = _defaultFlags[key];
    if (defaultValue != null) return _asString(defaultValue, fallback: fallback);
    return fallback;
  }

  void _setFlagValue(String key, dynamic value) {
    final flags = _flags();
    final defaultValue = _defaultFlags[key];
    if (_flagEquals(value, defaultValue)) {
      flags.remove(key);
    } else {
      flags[key] = value;
    }
    if (flags.isEmpty) {
      _tomlData.remove('flags');
    }
  }

  void _removeFlagValue(String key) {
    final flags = _getMapPath(const ['flags']);
    if (flags == null) return;
    flags.remove(key);
    if (flags.isEmpty) {
      _tomlData.remove('flags');
    }
  }
}

String _normalizeId(String? id) {
  if (id != null && id.trim().isNotEmpty) return id.trim();
  return _uuid.v4();
}

bool _flagEquals(dynamic value, dynamic defaultValue) {
  if (value is String && defaultValue is String) {
    return value.trim() == defaultValue.trim();
  }
  return value == defaultValue;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value?.toString() ?? '';
  final direct = int.tryParse(text);
  if (direct != null) return direct;
  try {
    final big = BigInt.parse(text);
    if (big > BigInt.from(0x7fffffffffffffff)) {
      return fallback;
    }
    return big.toInt();
  } catch (_) {
    return fallback;
  }
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList();
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> input) {
  final output = <String, dynamic>{};
  input.forEach((key, value) {
    output[key] = _deepCopyValue(value);
  });
  return output;
}

dynamic _deepCopyValue(dynamic value) {
  if (value is Map<String, dynamic>) return _deepCopyMap(value);
  if (value is Map) {
    return _deepCopyMap(value.cast<String, dynamic>());
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList();
  }
  return value;
}

List<String> _cleanList(List<String> values) {
  return values.map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
}

void _removeDefaultFlags(Map<String, dynamic> data) {
  final rawFlags = data['flags'];
  if (rawFlags is! Map) return;
  final flags = rawFlags.cast<String, dynamic>();
  final toRemove = <String>[];
  flags.forEach((key, value) {
    if (_flagEquals(value, _defaultFlags[key])) {
      toRemove.add(key);
    }
  });
  for (final key in toRemove) {
    flags.remove(key);
  }
  if (flags.isEmpty) {
    data.remove('flags');
  }
}

void _pruneEmptyValues(Map<String, dynamic> data) {
  final toRemove = <String>[];
  data.forEach((key, value) {
    final normalized = _pruneValue(value);
    if (normalized == null) {
      toRemove.add(key);
    } else {
      data[key] = normalized;
    }
  });
  for (final key in toRemove) {
    data.remove(key);
  }
}

dynamic _pruneValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    _pruneEmptyValues(value);
    return value.isEmpty ? null : value;
  }
  if (value is Map) {
    final casted = value.cast<String, dynamic>();
    _pruneEmptyValues(casted);
    return casted.isEmpty ? null : casted;
  }
  if (value is List) {
    final normalized = value
        .map(_pruneValue)
        .where((item) => item != null)
        .toList();
    return normalized.isEmpty ? null : normalized;
  }
  if (value is String) {
    return value.trim().isEmpty ? null : value;
  }
  return value;
}

(String, int) _splitHostPort(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return ('', 0);
  final idx = trimmed.lastIndexOf(':');
  if (idx <= 0 || idx >= trimmed.length - 1) return (trimmed, 0);
  final host = trimmed.substring(0, idx);
  final port = int.tryParse(trimmed.substring(idx + 1)) ?? 0;
  return (host, port);
}

String _joinHostPort(String host, int port) {
  final trimmedHost = host.trim();
  if (trimmedHost.isEmpty && port <= 0) return '';
  if (port <= 0) return trimmedHost;
  return '$trimmedHost:$port';
}

String _uriHostPort(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  try {
    final uri = Uri.parse(trimmed);
    if (uri.host.isEmpty) return trimmed;
    final hasPort = uri.hasPort && uri.port > 0;
    return hasPort ? '${uri.host}:${uri.port}' : uri.host;
  } catch (_) {
    return trimmed;
  }
}
