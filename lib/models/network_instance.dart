class NetworkInstance {
  final String configId;
  bool running;
  NodeInfo? nodeInfo;
  List<PeerRouteInfo> routes;
  List<PeerConnInfo> peerConns;
  String? errorMessage;
  DateTime? startTime;

  NetworkInstance({
    required this.configId,
    this.running = false,
    this.nodeInfo,
    List<PeerRouteInfo>? routes,
    List<PeerConnInfo>? peerConns,
    this.errorMessage,
    this.startTime,
  })  : routes = routes ?? [],
        peerConns = peerConns ?? [];

  int get peerCount {
    final ids = <int>{};
    for (final r in routes) {
      ids.add(r.peerId);
    }
    return ids.length;
  }

  int get totalRxBytes => peerConns.fold(0, (sum, c) => sum + c.rxBytes);

  int get totalTxBytes => peerConns.fold(0, (sum, c) => sum + c.txBytes);

  Duration? get uptime =>
      startTime != null ? DateTime.now().difference(startTime!) : null;
}

class NodeInfo {
  final String virtualIpv4;
  final String hostname;
  final String version;
  final int peerId;
  final List<String> listeners;
  final String udpNatType;
  final String tcpNatType;
  final List<String> publicIps;
  final List<int> publicPortRange;

  const NodeInfo({
    this.virtualIpv4 = '',
    this.hostname = '',
    this.version = '',
    this.peerId = 0,
    this.listeners = const [],
    this.udpNatType = '',
    this.tcpNatType = '',
    this.publicIps = const [],
    this.publicPortRange = const [],
  });

  factory NodeInfo.fromJson(Map<String, dynamic> j) {
    final stun = j['stun_info'] as Map<String, dynamic>? ?? {};
    return NodeInfo(
      virtualIpv4: _str(j['virtual_ipv4'] ?? j['virtualIpv4']),
      hostname: _str(j['hostname']),
      version: _str(j['version']),
      peerId: _int(j['peer_id'] ?? j['peerId']),
      listeners: _strList(j['listeners']),
      udpNatType: _natTypeStr(stun['udp_nat_type'] ?? stun['udpNatType']),
      tcpNatType: _natTypeStr(stun['tcp_nat_type'] ?? stun['tcpNatType']),
      publicIps: _strList(stun['public_ips'] ?? stun['publicIps']),
      publicPortRange:
          _intList(stun['public_port_range'] ?? stun['publicPortRange']),
    );
  }
}

class PeerRouteInfo {
  final int peerId;
  final String ipv4Addr;
  final String ipv6Addr;
  final String hostname;
  final int nextHopPeerId;
  final int cost;
  final double latencyMs;
  final List<String> proxyCidrs;
  final String udpNatType;
  final String tcpNatType;
  final String version;
  final int featureFlag;

  const PeerRouteInfo({
    this.peerId = 0,
    this.ipv4Addr = '',
    this.ipv6Addr = '',
    this.hostname = '',
    this.nextHopPeerId = 0,
    this.cost = 0,
    this.latencyMs = 0,
    this.proxyCidrs = const [],
    this.udpNatType = '',
    this.tcpNatType = '',
    this.version = '',
    this.featureFlag = 0,
  });

  bool get isDirect => nextHopPeerId == peerId || nextHopPeerId == 0;

  factory PeerRouteInfo.fromJson(Map<String, dynamic> j) {
    final stun = j['stun_info'] as Map<String, dynamic>? ?? {};
    final latUs = _int(j['path_latency'] ?? j['pathLatency']);
    return PeerRouteInfo(
      peerId: _int(j['peer_id'] ?? j['peerId']),
      ipv4Addr: _extractIp(j['ipv4_addr'] ?? j['ipv4Addr']),
      ipv6Addr: _extractIp(j['ipv6_addr'] ?? j['ipv6Addr']),
      hostname: _str(j['hostname']),
      nextHopPeerId: _int(j['next_hop_peer_id'] ?? j['nextHopPeerId']),
      cost: _int(j['cost']),
      latencyMs: latUs / 1000.0,
      proxyCidrs: _strList(j['proxy_cidrs'] ?? j['proxyCidrs']),
      udpNatType: _natTypeStr(stun['udp_nat_type'] ?? stun['udpNatType']),
      tcpNatType: _natTypeStr(stun['tcp_nat_type'] ?? stun['tcpNatType']),
      version: _str(j['version']),
      featureFlag: _int(j['feature_flag'] ?? j['featureFlag']),
    );
  }
}

class PeerConnInfo {
  final int peerId;
  final String connId;
  final String tunnelType;
  final String localAddr;
  final String remoteAddr;
  final int rxBytes;
  final int txBytes;
  final int rxPackets;
  final int txPackets;
  final double latencyMs;
  final double lossRate;
  final List<String> features;
  final String networkName;
  final bool isClient;
  final bool isClosed;

  const PeerConnInfo({
    this.peerId = 0,
    this.connId = '',
    this.tunnelType = '',
    this.localAddr = '',
    this.remoteAddr = '',
    this.rxBytes = 0,
    this.txBytes = 0,
    this.rxPackets = 0,
    this.txPackets = 0,
    this.latencyMs = 0,
    this.lossRate = 0,
    this.features = const [],
    this.networkName = '',
    this.isClient = false,
    this.isClosed = false,
  });

  factory PeerConnInfo.fromJson(Map<String, dynamic> j) {
    final tunnel = j['tunnel'] as Map<String, dynamic>? ?? {};
    final stats = j['stats'] as Map<String, dynamic>? ?? {};
    final latUs = _int(stats['latency_us'] ?? stats['latencyUs']);
    return PeerConnInfo(
      peerId: _int(j['peer_id'] ?? j['peerId']),
      connId: _str(j['conn_id'] ?? j['connId']),
      tunnelType: _str(tunnel['tunnel_type'] ?? tunnel['tunnelType']),
      localAddr: _str(tunnel['local_addr'] ?? tunnel['localAddr']),
      remoteAddr: _str(tunnel['remote_addr'] ?? tunnel['remoteAddr']),
      rxBytes: _int(stats['rx_bytes'] ?? stats['rxBytes']),
      txBytes: _int(stats['tx_bytes'] ?? stats['txBytes']),
      rxPackets: _int(stats['rx_packets'] ?? stats['rxPackets']),
      txPackets: _int(stats['tx_packets'] ?? stats['txPackets']),
      latencyMs: latUs / 1000.0,
      lossRate: _double(j['loss_rate'] ?? j['lossRate']),
      features: _strList(j['features']),
      networkName: _str(j['network_name'] ?? j['networkName']),
      isClient: j['is_client'] as bool? ?? j['isClient'] as bool? ?? false,
      isClosed: j['is_closed'] as bool? ?? j['isClosed'] as bool? ?? false,
    );
  }

  /// Human-friendly tunnel protocol name.
  String get tunnelLabel {
    final t = tunnelType.toLowerCase();
    if (t.contains('udp')) return 'UDP';
    if (t.contains('tcp')) return 'TCP';
    if (t.contains('ws') && t.contains('s')) return 'WSS';
    if (t.contains('ws')) return 'WS';
    if (t.contains('quic')) return 'QUIC';
    if (t.contains('ring')) return 'Ring';
    if (t.isEmpty) return 'TCP';
    return tunnelType.toUpperCase();
  }

  /// Total traffic (RX + TX).
  int get totalBytes => rxBytes + txBytes;
}

// ── Helpers ──

String _str(dynamic v) => v?.toString() ?? '';

int _int(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _double(dynamic v) {
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

List<String> _strList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return [];
}

List<int> _intList(dynamic v) {
  if (v is List) {
    return v.map((e) {
      if (e is int) return e;
      if (e is double) return e.toInt();
      return int.tryParse(e.toString()) ?? 0;
    }).toList();
  }
  return [];
}

String _extractIp(dynamic v) {
  if (v is String) return v.split('/').first;
  if (v is Map) {
    final addr = v['addr'] ?? v['address'];
    if (addr != null) return addr.toString().split('/').first;
  }
  return '';
}

const _natTypeNames = {
  0: 'Unknown',
  1: 'Open Internet',
  2: 'No PAT',
  3: 'Full Cone',
  4: 'Restricted',
  5: 'Port Restricted',
  6: 'Symmetric',
  7: 'Sym UDP Firewall',
  8: 'Sym Easy Inc',
  9: 'Sym Easy Dec',
};

String _natTypeStr(dynamic v) {
  if (v is String) return v;
  if (v is int) return _natTypeNames[v] ?? 'Unknown';
  return '';
}
