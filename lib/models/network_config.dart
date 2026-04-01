import 'package:uuid/uuid.dart';

/// Port forwarding rule: local bind → remote destination.
class PortForwardConfig {
  String bindIp;
  int bindPort;
  String dstIp;
  int dstPort;
  String proto; // tcp | udp

  PortForwardConfig({
    this.bindIp = '0.0.0.0',
    this.bindPort = 0,
    this.dstIp = '',
    this.dstPort = 0,
    this.proto = 'tcp',
  });

  PortForwardConfig copy() => PortForwardConfig(
        bindIp: bindIp,
        bindPort: bindPort,
        dstIp: dstIp,
        dstPort: dstPort,
        proto: proto,
      );

  Map<String, dynamic> toJson() => {
        'bind_ip': bindIp,
        'bind_port': bindPort,
        'dst_ip': dstIp,
        'dst_port': dstPort,
        'proto': proto,
      };

  factory PortForwardConfig.fromJson(Map<String, dynamic> j) =>
      PortForwardConfig(
        bindIp: j['bind_ip'] as String? ?? '0.0.0.0',
        bindPort: j['bind_port'] as int? ?? 0,
        dstIp: j['dst_ip'] as String? ?? '',
        dstPort: j['dst_port'] as int? ?? 0,
        proto: j['proto'] as String? ?? 'tcp',
      );

  /// Format for --port-forward: proto://bind_ip:bind_port/dst_ip:dst_port
  String toCliUrl() => '$proto://$bindIp:$bindPort/$dstIp:$dstPort';

  String get displayText => '$proto  $bindIp:$bindPort → $dstIp:$dstPort';
}

/// Full EasyTier network configuration covering all CLI flags.
class NetworkConfig {
  final String id;

  // ── Identity ──
  String configName;
  String networkName;
  String networkSecret;
  String hostname;
  String instanceName;

  // ── IP ──
  String virtualIpv4;
  String virtualIpv6;
  bool dhcp;

  // ── Connectivity ──
  List<String> peerUrls;
  List<String> listeners;
  List<String> mappedListeners;
  bool noListener;
  String externalNode;
  String defaultProtocol;

  // ── Proxy & Routing ──
  List<String> proxyCidrs;
  List<String> exitNodes;
  bool enableExitNode;
  bool proxyForwardBySystem;
  List<String> manualRoutes;

  // ── Port Forwarding ──
  List<PortForwardConfig> portForwards;

  // ── Tunnel Protocols ──
  bool enableKcpProxy;
  bool disableKcpInput;
  bool enableQuicProxy;
  bool disableQuicInput;
  bool disableIpv6;

  // ── Security & Encryption ──
  bool disableEncryption;
  String encryptionAlgorithm; // '' | 'aes-gcm' | 'chacha20-poly1305'
  bool secureMode;
  String localPrivateKey;
  String localPublicKey;
  String credential;
  String credentialFile;
  bool privateMode;

  // ── P2P & NAT ──
  bool disableP2p;
  bool disableUdpHolePunching;
  bool disableTcpHolePunching;
  bool disableSymHolePunching;
  bool lazyP2p;
  bool needP2p;
  bool p2pOnly;

  // ── Relay ──
  bool relayAllPeerRpc;
  List<String> relayNetworkWhitelist;
  bool disableRelayKcp;
  bool disableRelayQuic;
  bool enableRelayForeignNetworkKcp;
  bool enableRelayForeignNetworkQuic;
  int foreignRelayBpsLimit;

  // ── Features ──
  bool enableMagicDns;
  bool acceptDns;
  String tldDnsZone;
  bool enableSocks5;
  int socks5Port;
  String vpnPortal; // ip:port for WireGuard portal
  bool noTun;
  bool useSmoltcp;

  // ── Performance ──
  bool latencyFirst;
  bool multiThread;
  int multiThreadCount;
  int mtu;
  int instanceRecvBpsLimit;
  String compression; // '' | 'zstd'

  // ── Device ──
  String devName;
  bool bindDevice;

  // ── Whitelists ──
  List<String> tcpWhitelist;
  List<String> udpWhitelist;

  // ── STUN ──
  List<String> stunServers;
  List<String> stunServersV6;

  // ── RPC ──
  int rpcPort;
  List<String> rpcPortalWhitelist;

  // ── Logging ──
  String consoleLogLevel;
  String fileLogLevel;
  String fileLogDir;
  int fileLogSizeMb;
  int fileLogCount;

  // ── App state ──
  bool autoStart;

  NetworkConfig({
    String? id,
    this.configName = '',
    this.networkName = '',
    this.networkSecret = '',
    this.hostname = '',
    this.instanceName = '',
    this.virtualIpv4 = '',
    this.virtualIpv6 = '',
    this.dhcp = true,
    List<String>? peerUrls,
    List<String>? listeners,
    List<String>? mappedListeners,
    this.noListener = false,
    this.externalNode = '',
    this.defaultProtocol = '',
    List<String>? proxyCidrs,
    List<String>? exitNodes,
    this.enableExitNode = false,
    this.proxyForwardBySystem = false,
    List<String>? manualRoutes,
    List<PortForwardConfig>? portForwards,
    this.enableKcpProxy = false,
    this.disableKcpInput = false,
    this.enableQuicProxy = false,
    this.disableQuicInput = false,
    this.disableIpv6 = false,
    this.disableEncryption = false,
    this.encryptionAlgorithm = '',
    this.secureMode = false,
    this.localPrivateKey = '',
    this.localPublicKey = '',
    this.credential = '',
    this.credentialFile = '',
    this.privateMode = false,
    this.disableP2p = false,
    this.disableUdpHolePunching = false,
    this.disableTcpHolePunching = false,
    this.disableSymHolePunching = false,
    this.lazyP2p = false,
    this.needP2p = false,
    this.p2pOnly = false,
    this.relayAllPeerRpc = false,
    List<String>? relayNetworkWhitelist,
    this.disableRelayKcp = false,
    this.disableRelayQuic = false,
    this.enableRelayForeignNetworkKcp = false,
    this.enableRelayForeignNetworkQuic = false,
    this.foreignRelayBpsLimit = 0,
    this.enableMagicDns = false,
    this.acceptDns = false,
    this.tldDnsZone = '',
    this.enableSocks5 = false,
    this.socks5Port = 1080,
    this.vpnPortal = '',
    this.noTun = false,
    this.useSmoltcp = false,
    this.latencyFirst = false,
    this.multiThread = false,
    this.multiThreadCount = 0,
    this.mtu = 1380,
    this.instanceRecvBpsLimit = 0,
    this.compression = '',
    this.devName = '',
    this.bindDevice = false,
    List<String>? tcpWhitelist,
    List<String>? udpWhitelist,
    List<String>? stunServers,
    List<String>? stunServersV6,
    this.rpcPort = 15888,
    List<String>? rpcPortalWhitelist,
    this.consoleLogLevel = 'info',
    this.fileLogLevel = '',
    this.fileLogDir = '',
    this.fileLogSizeMb = 0,
    this.fileLogCount = 0,
    this.autoStart = false,
  })  : id = id ?? const Uuid().v4(),
        peerUrls = peerUrls ?? [],
        listeners = listeners ?? [],
        mappedListeners = mappedListeners ?? [],
        proxyCidrs = proxyCidrs ?? [],
        exitNodes = exitNodes ?? [],
        manualRoutes = manualRoutes ?? [],
        portForwards = portForwards ?? [],
        relayNetworkWhitelist = relayNetworkWhitelist ?? [],
        tcpWhitelist = tcpWhitelist ?? [],
        udpWhitelist = udpWhitelist ?? [],
        stunServers = stunServers ?? [],
        stunServersV6 = stunServersV6 ?? [],
        rpcPortalWhitelist = rpcPortalWhitelist ?? [];

  // ── JSON serialization ──

  Map<String, dynamic> toJson() => {
        'id': id,
        'config_name': configName,
        'network_name': networkName,
        'network_secret': networkSecret,
        'hostname': hostname,
        'instance_name': instanceName,
        'virtual_ipv4': virtualIpv4,
        'virtual_ipv6': virtualIpv6,
        'dhcp': dhcp,
        'peer_urls': peerUrls,
        'listeners': listeners,
        'mapped_listeners': mappedListeners,
        'no_listener': noListener,
        'external_node': externalNode,
        'default_protocol': defaultProtocol,
        'proxy_cidrs': proxyCidrs,
        'exit_nodes': exitNodes,
        'enable_exit_node': enableExitNode,
        'proxy_forward_by_system': proxyForwardBySystem,
        'manual_routes': manualRoutes,
        'port_forwards': portForwards.map((e) => e.toJson()).toList(),
        'enable_kcp_proxy': enableKcpProxy,
        'disable_kcp_input': disableKcpInput,
        'enable_quic_proxy': enableQuicProxy,
        'disable_quic_input': disableQuicInput,
        'disable_ipv6': disableIpv6,
        'disable_encryption': disableEncryption,
        'encryption_algorithm': encryptionAlgorithm,
        'secure_mode': secureMode,
        'local_private_key': localPrivateKey,
        'local_public_key': localPublicKey,
        'credential': credential,
        'credential_file': credentialFile,
        'private_mode': privateMode,
        'disable_p2p': disableP2p,
        'disable_udp_hole_punching': disableUdpHolePunching,
        'disable_tcp_hole_punching': disableTcpHolePunching,
        'disable_sym_hole_punching': disableSymHolePunching,
        'lazy_p2p': lazyP2p,
        'need_p2p': needP2p,
        'p2p_only': p2pOnly,
        'relay_all_peer_rpc': relayAllPeerRpc,
        'relay_network_whitelist': relayNetworkWhitelist,
        'disable_relay_kcp': disableRelayKcp,
        'disable_relay_quic': disableRelayQuic,
        'enable_relay_foreign_network_kcp': enableRelayForeignNetworkKcp,
        'enable_relay_foreign_network_quic': enableRelayForeignNetworkQuic,
        'foreign_relay_bps_limit': foreignRelayBpsLimit,
        'enable_magic_dns': enableMagicDns,
        'accept_dns': acceptDns,
        'tld_dns_zone': tldDnsZone,
        'enable_socks5': enableSocks5,
        'socks5_port': socks5Port,
        'vpn_portal': vpnPortal,
        'no_tun': noTun,
        'use_smoltcp': useSmoltcp,
        'latency_first': latencyFirst,
        'multi_thread': multiThread,
        'multi_thread_count': multiThreadCount,
        'mtu': mtu,
        'instance_recv_bps_limit': instanceRecvBpsLimit,
        'compression': compression,
        'dev_name': devName,
        'bind_device': bindDevice,
        'tcp_whitelist': tcpWhitelist,
        'udp_whitelist': udpWhitelist,
        'stun_servers': stunServers,
        'stun_servers_v6': stunServersV6,
        'rpc_port': rpcPort,
        'rpc_portal_whitelist': rpcPortalWhitelist,
        'console_log_level': consoleLogLevel,
        'file_log_level': fileLogLevel,
        'file_log_dir': fileLogDir,
        'file_log_size_mb': fileLogSizeMb,
        'file_log_count': fileLogCount,
        'auto_start': autoStart,
      };

  factory NetworkConfig.fromJson(Map<String, dynamic> j) => NetworkConfig(
        id: j['id'] as String?,
        configName: j['config_name'] as String? ?? '',
        networkName: j['network_name'] as String? ?? '',
        networkSecret: j['network_secret'] as String? ?? '',
        hostname: j['hostname'] as String? ?? '',
        instanceName: j['instance_name'] as String? ?? '',
        virtualIpv4: j['virtual_ipv4'] as String? ?? '',
        virtualIpv6: j['virtual_ipv6'] as String? ?? '',
        dhcp: j['dhcp'] as bool? ?? true,
        peerUrls: _strList(j['peer_urls']),
        listeners: _strList(j['listeners']),
        mappedListeners: _strList(j['mapped_listeners']),
        noListener: j['no_listener'] as bool? ?? false,
        externalNode: j['external_node'] as String? ?? '',
        defaultProtocol: j['default_protocol'] as String? ?? '',
        proxyCidrs: _strList(j['proxy_cidrs']),
        exitNodes: _strList(j['exit_nodes']),
        enableExitNode: j['enable_exit_node'] as bool? ?? false,
        proxyForwardBySystem: j['proxy_forward_by_system'] as bool? ?? false,
        manualRoutes: _strList(j['manual_routes']),
        portForwards: _pfList(j['port_forwards']),
        enableKcpProxy: j['enable_kcp_proxy'] as bool? ?? false,
        disableKcpInput: j['disable_kcp_input'] as bool? ?? false,
        enableQuicProxy: j['enable_quic_proxy'] as bool? ?? false,
        disableQuicInput: j['disable_quic_input'] as bool? ?? false,
        disableIpv6: j['disable_ipv6'] as bool? ?? false,
        disableEncryption: j['disable_encryption'] as bool? ?? false,
        encryptionAlgorithm: j['encryption_algorithm'] as String? ?? '',
        secureMode: j['secure_mode'] as bool? ?? false,
        localPrivateKey: j['local_private_key'] as String? ?? '',
        localPublicKey: j['local_public_key'] as String? ?? '',
        credential: j['credential'] as String? ?? '',
        credentialFile: j['credential_file'] as String? ?? '',
        privateMode: j['private_mode'] as bool? ?? false,
        disableP2p: j['disable_p2p'] as bool? ?? false,
        disableUdpHolePunching:
            j['disable_udp_hole_punching'] as bool? ?? false,
        disableTcpHolePunching:
            j['disable_tcp_hole_punching'] as bool? ?? false,
        disableSymHolePunching:
            j['disable_sym_hole_punching'] as bool? ?? false,
        lazyP2p: j['lazy_p2p'] as bool? ?? false,
        needP2p: j['need_p2p'] as bool? ?? false,
        p2pOnly: j['p2p_only'] as bool? ?? false,
        relayAllPeerRpc: j['relay_all_peer_rpc'] as bool? ?? false,
        relayNetworkWhitelist: _strList(j['relay_network_whitelist']),
        disableRelayKcp: j['disable_relay_kcp'] as bool? ?? false,
        disableRelayQuic: j['disable_relay_quic'] as bool? ?? false,
        enableRelayForeignNetworkKcp:
            j['enable_relay_foreign_network_kcp'] as bool? ?? false,
        enableRelayForeignNetworkQuic:
            j['enable_relay_foreign_network_quic'] as bool? ?? false,
        foreignRelayBpsLimit: j['foreign_relay_bps_limit'] as int? ?? 0,
        enableMagicDns: j['enable_magic_dns'] as bool? ?? false,
        acceptDns: j['accept_dns'] as bool? ?? false,
        tldDnsZone: j['tld_dns_zone'] as String? ?? '',
        enableSocks5: j['enable_socks5'] as bool? ?? false,
        socks5Port: j['socks5_port'] as int? ?? 1080,
        vpnPortal: j['vpn_portal'] as String? ?? '',
        noTun: j['no_tun'] as bool? ?? false,
        useSmoltcp: j['use_smoltcp'] as bool? ?? false,
        latencyFirst: j['latency_first'] as bool? ?? false,
        multiThread: j['multi_thread'] as bool? ?? false,
        multiThreadCount: j['multi_thread_count'] as int? ?? 0,
        mtu: j['mtu'] as int? ?? 1380,
        instanceRecvBpsLimit: j['instance_recv_bps_limit'] as int? ?? 0,
        compression: j['compression'] as String? ?? '',
        devName: j['dev_name'] as String? ?? '',
        bindDevice: j['bind_device'] as bool? ?? false,
        tcpWhitelist: _strList(j['tcp_whitelist']),
        udpWhitelist: _strList(j['udp_whitelist']),
        stunServers: _strList(j['stun_servers']),
        stunServersV6: _strList(j['stun_servers_v6']),
        rpcPort: j['rpc_port'] as int? ?? 15888,
        rpcPortalWhitelist: _strList(j['rpc_portal_whitelist']),
        consoleLogLevel: j['console_log_level'] as String? ?? 'info',
        fileLogLevel: j['file_log_level'] as String? ?? '',
        fileLogDir: j['file_log_dir'] as String? ?? '',
        fileLogSizeMb: j['file_log_size_mb'] as int? ?? 0,
        fileLogCount: j['file_log_count'] as int? ?? 0,
        autoStart: j['auto_start'] as bool? ?? false,
      );

  static List<String> _strList(dynamic v) {
    if (v is List) return v.cast<String>();
    return [];
  }

  static List<PortForwardConfig> _pfList(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map<String, dynamic>>()
          .map(PortForwardConfig.fromJson)
          .toList();
    }
    return [];
  }

  // ── CLI args generation ──

  List<String> toCliArgs() {
    final a = <String>[];

    void flag(bool v, String name) {
      if (v) a.add(name);
    }

    void opt(String v, String name) {
      if (v.isNotEmpty) a.addAll([name, v]);
    }

    void optInt(int v, String name) {
      if (v > 0) a.addAll([name, '$v']);
    }

    void list(List<String> v, String name) {
      for (final item in v) {
        if (item.isNotEmpty) a.addAll([name, item]);
      }
    }

    // Identity
    opt(networkName, '--network-name');
    opt(networkSecret, '--network-secret');
    opt(hostname, '--hostname');
    opt(instanceName, '--instance-name');

    // IP
    opt(virtualIpv4, '--ipv4');
    opt(virtualIpv6, '--ipv6');
    if (dhcp) a.add('--dhcp');

    // Connectivity
    list(peerUrls, '--peers');
    if (!noListener) {
      list(listeners, '--listeners');
    }
    list(mappedListeners, '--mapped-listeners');
    flag(noListener, '--no-listener');
    opt(externalNode, '--external-node');
    opt(defaultProtocol, '--default-protocol');

    // Proxy & Routing
    list(proxyCidrs, '--proxy-networks');
    list(exitNodes, '--exit-nodes');
    flag(enableExitNode, '--enable-exit-node');
    flag(proxyForwardBySystem, '--proxy-forward-by-system');
    list(manualRoutes, '--manual-routes');

    // Port Forwarding
    for (final pf in portForwards) {
      a.addAll(['--port-forward', pf.toCliUrl()]);
    }

    // Tunnel Protocols
    flag(enableKcpProxy, '--enable-kcp-proxy');
    flag(disableKcpInput, '--disable-kcp-input');
    flag(enableQuicProxy, '--enable-quic-proxy');
    flag(disableQuicInput, '--disable-quic-input');
    flag(disableIpv6, '--disable-ipv6');

    // Security
    flag(disableEncryption, '--disable-encryption');
    opt(encryptionAlgorithm, '--encryption-algorithm');
    flag(secureMode, '--secure-mode');
    opt(localPrivateKey, '--local-private-key');
    opt(localPublicKey, '--local-public-key');
    opt(credential, '--credential');
    opt(credentialFile, '--credential-file');
    flag(privateMode, '--private-mode');

    // P2P & NAT
    flag(disableP2p, '--disable-p2p');
    if (!disableP2p) {
      flag(disableUdpHolePunching, '--disable-udp-hole-punching');
      flag(disableTcpHolePunching, '--disable-tcp-hole-punching');
      flag(disableSymHolePunching, '--disable-sym-hole-punching');
      flag(lazyP2p, '--lazy-p2p');
      flag(needP2p, '--need-p2p');
      flag(p2pOnly, '--p2p-only');
    }

    // Relay
    flag(relayAllPeerRpc, '--relay-all-peer-rpc');
    if (relayNetworkWhitelist.isNotEmpty) {
      a.addAll([
        '--relay-network-whitelist',
        relayNetworkWhitelist.join(','),
      ]);
    }
    flag(disableRelayKcp, '--disable-relay-kcp');
    flag(disableRelayQuic, '--disable-relay-quic');
    flag(enableRelayForeignNetworkKcp, '--enable-relay-foreign-network-kcp');
    flag(
        enableRelayForeignNetworkQuic, '--enable-relay-foreign-network-quic');
    optInt(foreignRelayBpsLimit, '--foreign-relay-bps-limit');

    // Features
    flag(enableMagicDns, '--accept-dns');
    if (acceptDns) a.add('--accept-dns');
    opt(tldDnsZone, '--tld-dns-zone');
    if (enableSocks5) {
      a.addAll(['--socks5', '$socks5Port']);
    }
    opt(vpnPortal, '--vpn-portal');
    flag(noTun, '--no-tun');
    flag(useSmoltcp, '--use-smoltcp');

    // Performance
    flag(latencyFirst, '--latency-first');
    flag(multiThread, '--multi-thread');
    optInt(multiThreadCount, '--multi-thread-count');
    if (mtu != 1380) a.addAll(['--mtu', '$mtu']);
    optInt(instanceRecvBpsLimit, '--instance-recv-bps-limit');
    opt(compression, '--compression');

    // Device
    opt(devName, '--dev-name');
    flag(bindDevice, '--bind-device');

    // Whitelists
    if (tcpWhitelist.isNotEmpty) {
      a.addAll(['--tcp-whitelist', tcpWhitelist.join(',')]);
    }
    if (udpWhitelist.isNotEmpty) {
      a.addAll(['--udp-whitelist', udpWhitelist.join(',')]);
    }

    // STUN
    if (stunServers.isNotEmpty) {
      a.addAll(['--stun-servers', stunServers.join(',')]);
    }
    if (stunServersV6.isNotEmpty) {
      a.addAll(['--stun-servers-v6', stunServersV6.join(',')]);
    }

    // RPC
    a.addAll(['--rpc-portal', '127.0.0.1:$rpcPort']);
    if (rpcPortalWhitelist.isNotEmpty) {
      a.addAll(['--rpc-portal-whitelist', rpcPortalWhitelist.join(',')]);
    }

    // Logging
    if (consoleLogLevel != 'info') {
      a.addAll(['--console-log-level', consoleLogLevel]);
    }
    opt(fileLogLevel, '--file-log-level');
    opt(fileLogDir, '--file-log-dir');
    optInt(fileLogSizeMb, '--file-log-size');
    optInt(fileLogCount, '--file-log-count');

    return a;
  }

  // ── TOML generation (matches easytier-core config file format) ──

  String toToml() {
    final b = StringBuffer();

    if (hostname.isNotEmpty) b.writeln('hostname = "$hostname"');
    if (instanceName.isNotEmpty) b.writeln('instance_name = "$instanceName"');
    if (virtualIpv4.isNotEmpty) b.writeln('ipv4 = "$virtualIpv4"');
    if (virtualIpv6.isNotEmpty) b.writeln('ipv6 = "$virtualIpv6"');
    if (dhcp) b.writeln('dhcp = true');
    if (listeners.isNotEmpty) {
      b.writeln('listeners = [');
      for (final l in listeners) {
        b.writeln('  "$l",');
      }
      b.writeln(']');
    }
    if (mappedListeners.isNotEmpty) {
      b.writeln('mapped_listeners = [');
      for (final l in mappedListeners) {
        b.writeln('  "$l",');
      }
      b.writeln(']');
    }
    b.writeln('rpc_portal = "127.0.0.1:$rpcPort"');
    if (exitNodes.isNotEmpty) {
      b.writeln('exit_nodes = [');
      for (final n in exitNodes) {
        b.writeln('  "$n",');
      }
      b.writeln(']');
    }
    if (proxyCidrs.isNotEmpty) {
      b.writeln('proxy_networks = [');
      for (final c in proxyCidrs) {
        b.writeln('  "$c",');
      }
      b.writeln(']');
    }
    if (manualRoutes.isNotEmpty) {
      b.writeln('routes = [');
      for (final r in manualRoutes) {
        b.writeln('  "$r",');
      }
      b.writeln(']');
    }
    if (tcpWhitelist.isNotEmpty) {
      b.writeln(
          'tcp_whitelist = [${tcpWhitelist.map((e) => '"$e"').join(', ')}]');
    } else {
      b.writeln('tcp_whitelist = []');
    }
    if (udpWhitelist.isNotEmpty) {
      b.writeln(
          'udp_whitelist = [${udpWhitelist.map((e) => '"$e"').join(', ')}]');
    } else {
      b.writeln('udp_whitelist = []');
    }
    if (vpnPortal.isNotEmpty) b.writeln('vpn_portal = "$vpnPortal"');

    // Network identity
    b.writeln();
    b.writeln('[network_identity]');
    b.writeln('network_name = "$networkName"');
    b.writeln('network_secret = "$networkSecret"');

    // Peers
    for (final p in peerUrls) {
      if (p.isNotEmpty) {
        b.writeln();
        b.writeln('[[peer]]');
        b.writeln('uri = "$p"');
      }
    }

    // Port forwards
    for (final pf in portForwards) {
      b.writeln();
      b.writeln('[[port_forward]]');
      b.writeln('bind = "${pf.bindIp}:${pf.bindPort}"');
      b.writeln('dst = "${pf.dstIp}:${pf.dstPort}"');
      b.writeln('proto = "${pf.proto}"');
    }

    // Flags
    b.writeln();
    b.writeln('[flags]');
    if (devName.isNotEmpty) b.writeln('dev_name = "$devName"');
    if (!disableEncryption) {
      b.writeln('enable_encryption = true');
    } else {
      b.writeln('enable_encryption = false');
    }
    if (!disableIpv6) b.writeln('enable_ipv6 = true');
    if (mtu != 1380) b.writeln('mtu = $mtu');
    if (latencyFirst) b.writeln('latency_first = true');
    if (enableExitNode) b.writeln('enable_exit_node = true');
    if (noTun) b.writeln('no_tun = true');
    if (useSmoltcp) b.writeln('use_smoltcp = true');
    if (disableP2p) b.writeln('disable_p2p = true');
    if (relayAllPeerRpc) b.writeln('relay_all_peer_rpc = true');
    if (disableUdpHolePunching) b.writeln('disable_udp_hole_punching = true');
    if (multiThread) b.writeln('multi_thread = true');
    if (multiThreadCount > 0) {
      b.writeln('multi_thread_count = $multiThreadCount');
    }
    if (enableKcpProxy) b.writeln('enable_kcp_proxy = true');
    if (disableKcpInput) b.writeln('disable_kcp_input = true');
    if (enableQuicProxy) b.writeln('enable_quic_proxy = true');
    if (disableQuicInput) b.writeln('disable_quic_input = true');
    if (proxyForwardBySystem) b.writeln('proxy_forward_by_system = true');
    if (acceptDns) b.writeln('accept_dns = true');
    if (privateMode) b.writeln('private_mode = true');
    if (foreignRelayBpsLimit > 0) {
      b.writeln('foreign_relay_bps_limit = $foreignRelayBpsLimit');
    }
    if (instanceRecvBpsLimit > 0) {
      b.writeln('instance_recv_bps_limit = $instanceRecvBpsLimit');
    }
    if (encryptionAlgorithm.isNotEmpty) {
      b.writeln('encryption_algorithm = "$encryptionAlgorithm"');
    }
    if (disableSymHolePunching) {
      b.writeln('disable_sym_hole_punching = true');
    }
    if (tldDnsZone.isNotEmpty) b.writeln('tld_dns_zone = "$tldDnsZone"');
    if (p2pOnly) b.writeln('p2p_only = true');
    if (disableTcpHolePunching) {
      b.writeln('disable_tcp_hole_punching = true');
    }
    if (disableRelayKcp) b.writeln('disable_relay_kcp = true');
    if (disableRelayQuic) b.writeln('disable_relay_quic = true');
    if (enableRelayForeignNetworkKcp) {
      b.writeln('enable_relay_foreign_network_kcp = true');
    }
    if (enableRelayForeignNetworkQuic) {
      b.writeln('enable_relay_foreign_network_quic = true');
    }
    if (lazyP2p) b.writeln('lazy_p2p = true');
    if (needP2p) b.writeln('need_p2p = true');
    if (bindDevice) b.writeln('bind_device = true');
    if (compression.isNotEmpty) {
      b.writeln('data_compress_algo = "$compression"');
    }
    if (noListener) b.writeln('no_listener = true');
    if (enableSocks5) b.writeln('socks5 = $socks5Port');

    return b.toString();
  }

  // ── copyWith ──

  NetworkConfig copyWith({
    String? configName,
    String? networkName,
    String? networkSecret,
    String? hostname,
    String? instanceName,
    String? virtualIpv4,
    String? virtualIpv6,
    bool? dhcp,
    List<String>? peerUrls,
    List<String>? listeners,
    List<String>? mappedListeners,
    bool? noListener,
    String? externalNode,
    String? defaultProtocol,
    List<String>? proxyCidrs,
    List<String>? exitNodes,
    bool? enableExitNode,
    bool? proxyForwardBySystem,
    List<String>? manualRoutes,
    List<PortForwardConfig>? portForwards,
    bool? enableKcpProxy,
    bool? disableKcpInput,
    bool? enableQuicProxy,
    bool? disableQuicInput,
    bool? disableIpv6,
    bool? disableEncryption,
    String? encryptionAlgorithm,
    bool? secureMode,
    String? localPrivateKey,
    String? localPublicKey,
    String? credential,
    String? credentialFile,
    bool? privateMode,
    bool? disableP2p,
    bool? disableUdpHolePunching,
    bool? disableTcpHolePunching,
    bool? disableSymHolePunching,
    bool? lazyP2p,
    bool? needP2p,
    bool? p2pOnly,
    bool? relayAllPeerRpc,
    List<String>? relayNetworkWhitelist,
    bool? disableRelayKcp,
    bool? disableRelayQuic,
    bool? enableRelayForeignNetworkKcp,
    bool? enableRelayForeignNetworkQuic,
    int? foreignRelayBpsLimit,
    bool? enableMagicDns,
    bool? acceptDns,
    String? tldDnsZone,
    bool? enableSocks5,
    int? socks5Port,
    String? vpnPortal,
    bool? noTun,
    bool? useSmoltcp,
    bool? latencyFirst,
    bool? multiThread,
    int? multiThreadCount,
    int? mtu,
    int? instanceRecvBpsLimit,
    String? compression,
    String? devName,
    bool? bindDevice,
    List<String>? tcpWhitelist,
    List<String>? udpWhitelist,
    List<String>? stunServers,
    List<String>? stunServersV6,
    int? rpcPort,
    List<String>? rpcPortalWhitelist,
    String? consoleLogLevel,
    String? fileLogLevel,
    String? fileLogDir,
    int? fileLogSizeMb,
    int? fileLogCount,
    bool? autoStart,
  }) {
    return NetworkConfig(
      id: id,
      configName: configName ?? this.configName,
      networkName: networkName ?? this.networkName,
      networkSecret: networkSecret ?? this.networkSecret,
      hostname: hostname ?? this.hostname,
      instanceName: instanceName ?? this.instanceName,
      virtualIpv4: virtualIpv4 ?? this.virtualIpv4,
      virtualIpv6: virtualIpv6 ?? this.virtualIpv6,
      dhcp: dhcp ?? this.dhcp,
      peerUrls: peerUrls ?? List.of(this.peerUrls),
      listeners: listeners ?? List.of(this.listeners),
      mappedListeners: mappedListeners ?? List.of(this.mappedListeners),
      noListener: noListener ?? this.noListener,
      externalNode: externalNode ?? this.externalNode,
      defaultProtocol: defaultProtocol ?? this.defaultProtocol,
      proxyCidrs: proxyCidrs ?? List.of(this.proxyCidrs),
      exitNodes: exitNodes ?? List.of(this.exitNodes),
      enableExitNode: enableExitNode ?? this.enableExitNode,
      proxyForwardBySystem:
          proxyForwardBySystem ?? this.proxyForwardBySystem,
      manualRoutes: manualRoutes ?? List.of(this.manualRoutes),
      portForwards:
          portForwards ?? this.portForwards.map((e) => e.copy()).toList(),
      enableKcpProxy: enableKcpProxy ?? this.enableKcpProxy,
      disableKcpInput: disableKcpInput ?? this.disableKcpInput,
      enableQuicProxy: enableQuicProxy ?? this.enableQuicProxy,
      disableQuicInput: disableQuicInput ?? this.disableQuicInput,
      disableIpv6: disableIpv6 ?? this.disableIpv6,
      disableEncryption: disableEncryption ?? this.disableEncryption,
      encryptionAlgorithm:
          encryptionAlgorithm ?? this.encryptionAlgorithm,
      secureMode: secureMode ?? this.secureMode,
      localPrivateKey: localPrivateKey ?? this.localPrivateKey,
      localPublicKey: localPublicKey ?? this.localPublicKey,
      credential: credential ?? this.credential,
      credentialFile: credentialFile ?? this.credentialFile,
      privateMode: privateMode ?? this.privateMode,
      disableP2p: disableP2p ?? this.disableP2p,
      disableUdpHolePunching:
          disableUdpHolePunching ?? this.disableUdpHolePunching,
      disableTcpHolePunching:
          disableTcpHolePunching ?? this.disableTcpHolePunching,
      disableSymHolePunching:
          disableSymHolePunching ?? this.disableSymHolePunching,
      lazyP2p: lazyP2p ?? this.lazyP2p,
      needP2p: needP2p ?? this.needP2p,
      p2pOnly: p2pOnly ?? this.p2pOnly,
      relayAllPeerRpc: relayAllPeerRpc ?? this.relayAllPeerRpc,
      relayNetworkWhitelist:
          relayNetworkWhitelist ?? List.of(this.relayNetworkWhitelist),
      disableRelayKcp: disableRelayKcp ?? this.disableRelayKcp,
      disableRelayQuic: disableRelayQuic ?? this.disableRelayQuic,
      enableRelayForeignNetworkKcp:
          enableRelayForeignNetworkKcp ?? this.enableRelayForeignNetworkKcp,
      enableRelayForeignNetworkQuic: enableRelayForeignNetworkQuic ??
          this.enableRelayForeignNetworkQuic,
      foreignRelayBpsLimit:
          foreignRelayBpsLimit ?? this.foreignRelayBpsLimit,
      enableMagicDns: enableMagicDns ?? this.enableMagicDns,
      acceptDns: acceptDns ?? this.acceptDns,
      tldDnsZone: tldDnsZone ?? this.tldDnsZone,
      enableSocks5: enableSocks5 ?? this.enableSocks5,
      socks5Port: socks5Port ?? this.socks5Port,
      vpnPortal: vpnPortal ?? this.vpnPortal,
      noTun: noTun ?? this.noTun,
      useSmoltcp: useSmoltcp ?? this.useSmoltcp,
      latencyFirst: latencyFirst ?? this.latencyFirst,
      multiThread: multiThread ?? this.multiThread,
      multiThreadCount: multiThreadCount ?? this.multiThreadCount,
      mtu: mtu ?? this.mtu,
      instanceRecvBpsLimit:
          instanceRecvBpsLimit ?? this.instanceRecvBpsLimit,
      compression: compression ?? this.compression,
      devName: devName ?? this.devName,
      bindDevice: bindDevice ?? this.bindDevice,
      tcpWhitelist: tcpWhitelist ?? List.of(this.tcpWhitelist),
      udpWhitelist: udpWhitelist ?? List.of(this.udpWhitelist),
      stunServers: stunServers ?? List.of(this.stunServers),
      stunServersV6: stunServersV6 ?? List.of(this.stunServersV6),
      rpcPort: rpcPort ?? this.rpcPort,
      rpcPortalWhitelist:
          rpcPortalWhitelist ?? List.of(this.rpcPortalWhitelist),
      consoleLogLevel: consoleLogLevel ?? this.consoleLogLevel,
      fileLogLevel: fileLogLevel ?? this.fileLogLevel,
      fileLogDir: fileLogDir ?? this.fileLogDir,
      fileLogSizeMb: fileLogSizeMb ?? this.fileLogSizeMb,
      fileLogCount: fileLogCount ?? this.fileLogCount,
      autoStart: autoStart ?? this.autoStart,
    );
  }

  String get displayName => configName.isNotEmpty
      ? configName
      : (networkName.isNotEmpty ? networkName : 'Unnamed');
}
