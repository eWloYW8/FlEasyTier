class NetworkInstance {
  final String configId;
  bool running;
  NodeInfo? nodeInfo;
  List<PeerRouteInfo> routes;
  List<PeerConnInfo> peerConns;
  List<MetricSnapshot> metrics;
  String? errorMessage;
  DateTime? startTime;
  bool managedByService;

  NetworkInstance({
    required this.configId,
    this.running = false,
    this.nodeInfo,
    List<PeerRouteInfo>? routes,
    List<PeerConnInfo>? peerConns,
    List<MetricSnapshot>? metrics,
    this.errorMessage,
    this.startTime,
    this.managedByService = false,
  })  : routes = routes ?? [],
        peerConns = peerConns ?? [],
        metrics = metrics ?? [];

  int get peerCount {
    final ids = <int>{};
    for (final conn in peerConns) {
      ids.add(conn.peerId);
    }
    for (final route in routes) {
      ids.add(route.peerId);
    }
    return ids.length;
  }

  int get totalRxBytes => peerConns.fold(0, (sum, conn) => sum + conn.rxBytes);

  int get totalTxBytes => peerConns.fold(0, (sum, conn) => sum + conn.txBytes);

  int metricValue(String name, [Map<String, String>? labels]) {
    return metrics
        .where((metric) => metric.name == name)
        .where((metric) {
          if (labels == null || labels.isEmpty) return true;
          for (final entry in labels.entries) {
            if (metric.labels[entry.key] != entry.value) return false;
          }
          return true;
        })
        .fold(0, (sum, metric) => sum + metric.value);
  }

  Duration? get uptime =>
      startTime != null ? DateTime.now().difference(startTime!) : null;
}

class NodeInfo {
  final String virtualIpv4;
  final String virtualIpv4Cidr;
  final String hostname;
  final String version;
  final int peerId;
  final List<String> listeners;
  final String udpNatType;
  final String tcpNatType;
  final List<String> publicIps;
  final List<String> interfaceIpv4s;
  final List<String> interfaceIpv6s;
  final String publicIpv6;
  final String instId;
  final String configDump;

  const NodeInfo({
    this.virtualIpv4 = '',
    this.virtualIpv4Cidr = '',
    this.hostname = '',
    this.version = '',
    this.peerId = 0,
    this.listeners = const [],
    this.udpNatType = '',
    this.tcpNatType = '',
    this.publicIps = const [],
    this.interfaceIpv4s = const [],
    this.interfaceIpv6s = const [],
    this.publicIpv6 = '',
    this.instId = '',
    this.configDump = '',
  });
}

class PeerRouteInfo {
  final int peerId;
  final String ipv4Addr;
  final String ipv4Cidr;
  final String ipv6Addr;
  final String hostname;
  final int nextHopPeerId;
  final int cost;
  final double latencyMs;
  final int nextHopPeerIdLatencyFirst;
  final int costLatencyFirst;
  final double pathLatencyLatencyFirstMs;
  final List<String> proxyCidrs;
  final String udpNatType;
  final String tcpNatType;
  final String version;
  final String instId;

  const PeerRouteInfo({
    this.peerId = 0,
    this.ipv4Addr = '',
    this.ipv4Cidr = '',
    this.ipv6Addr = '',
    this.hostname = '',
    this.nextHopPeerId = 0,
    this.cost = 0,
    this.latencyMs = 0,
    this.nextHopPeerIdLatencyFirst = 0,
    this.costLatencyFirst = 0,
    this.pathLatencyLatencyFirstMs = 0,
    this.proxyCidrs = const [],
    this.udpNatType = '',
    this.tcpNatType = '',
    this.version = '',
    this.instId = '',
  });

  bool get isDirect => cost <= 1;

  bool get hasLatencyFirstRoute =>
      nextHopPeerIdLatencyFirst > 0 ||
      costLatencyFirst > 0 ||
      pathLatencyLatencyFirstMs > 0;

  int currentNextHopPeerId(bool latencyFirstEnabled) {
    if (latencyFirstEnabled && nextHopPeerIdLatencyFirst > 0) {
      return nextHopPeerIdLatencyFirst;
    }
    return nextHopPeerId;
  }

  int currentCost(bool latencyFirstEnabled) {
    if (latencyFirstEnabled && costLatencyFirst > 0) {
      return costLatencyFirst;
    }
    return cost;
  }

  double currentLatencyMs(bool latencyFirstEnabled) {
    if (latencyFirstEnabled && pathLatencyLatencyFirstMs > 0) {
      return pathLatencyLatencyFirstMs;
    }
    return latencyMs;
  }
}

class PeerConnInfo {
  final int peerId;
  final int myPeerId;
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
  final bool isDefault;
  final String secureAuthLevel;
  final String peerIdentityType;

  const PeerConnInfo({
    this.peerId = 0,
    this.myPeerId = 0,
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
    this.isDefault = false,
    this.secureAuthLevel = '',
    this.peerIdentityType = '',
  });

  String get tunnelLabel {
    final type = tunnelType.toLowerCase();
    if (type.contains('udp')) return 'UDP';
    if (type.contains('tcp')) return 'TCP';
    if (type.contains('ws') && type.contains('s')) return 'WSS';
    if (type.contains('ws')) return 'WS';
    if (type.contains('quic')) return 'QUIC';
    if (type.contains('ring')) return 'Ring';
    if (type.isEmpty) return 'TCP';
    return tunnelType.toUpperCase();
  }

  int get totalBytes => rxBytes + txBytes;
}

class MetricSnapshot {
  final String name;
  final int value;
  final Map<String, String> labels;

  const MetricSnapshot({
    required this.name,
    required this.value,
    this.labels = const {},
  });
}
