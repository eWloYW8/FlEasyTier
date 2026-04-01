/// High-level EasyTier API — translates RPC responses into model objects.
///
/// Proto field mappings verified against:
///   easytier/src/proto/api_instance.proto
///   easytier/src/proto/common.proto
library;

import 'dart:typed_data';

import '../models/network_instance.dart';
import 'protobuf.dart';
import 'rpc_client.dart';
import 'rpc_types.dart';

class EasyTierApi {
  final RpcClient _client;

  EasyTierApi({required String host, required int port})
      : _client = RpcClient(host: host, port: port);

  bool get connected => _client.connected;

  Future<void> connect() => _client.connect();
  Future<void> close() => _client.close();

  static final _emptyRequest = Uint8List(0);

  // ═══════════════════════════════════════════════════════════════════════
  // Node Info (ShowNodeInfo → ShowNodeInfoResponse { NodeInfo node_info=1 })
  // ═══════════════════════════════════════════════════════════════════════

  Future<NodeInfo?> getNodeInfo() async {
    try {
      final raw = await _client.call(EtRpc.showNodeInfo, _emptyRequest);
      if (raw.isEmpty) return null;
      final f = ProtoReader.decode(raw);
      // ShowNodeInfoResponse: field 1 = NodeInfo
      final nodeMsg = f.getMessage(1);
      if (nodeMsg == null) return null;
      return _parseNodeInfo(nodeMsg);
    } on RpcException {
      return null;
    }
  }

  /// NodeInfo proto:
  /// ```
  /// uint32 peer_id = 1;
  /// string ipv4_addr = 2;          // "10.1.2.66/24"
  /// repeated string proxy_cidrs = 3;
  /// string hostname = 4;
  /// common.StunInfo stun_info = 5;
  /// string inst_id = 6;
  /// repeated string listeners = 7;  // plain strings
  /// string config = 8;
  /// string version = 9;
  /// common.PeerFeatureFlag feature_flag = 10;
  /// ```
  NodeInfo _parseNodeInfo(ProtoFields f) {
    final peerId = f.getVarint(1);
    final ipv4Addr = f.getString(2); // e.g. "10.1.2.66/24"
    final virtualIpv4 = ipv4Addr.split('/').first;
    final hostname = f.getString(4);
    final listeners = f.getRepeatedString(7);
    final version = f.getString(9);

    // StunInfo: udp_nat_type=1, tcp_nat_type=2, public_ip=4(repeated string)
    String udpNatType = '';
    String tcpNatType = '';
    List<String> publicIps = [];
    final stunMsg = f.getMessage(5);
    if (stunMsg != null) {
      udpNatType = _natTypeStr(stunMsg.getVarint(1));
      tcpNatType = _natTypeStr(stunMsg.getVarint(2));
      publicIps = stunMsg.getRepeatedString(4);
    }

    return NodeInfo(
      virtualIpv4: virtualIpv4,
      hostname: hostname,
      version: version,
      peerId: peerId,
      listeners: listeners,
      udpNatType: udpNatType,
      tcpNatType: tcpNatType,
      publicIps: publicIps,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Peers (ListPeer → ListPeerResponse { repeated PeerInfo peer_infos=1 })
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<PeerConnInfo>> listPeers() async {
    try {
      final raw = await _client.call(EtRpc.listPeer, _emptyRequest);
      if (raw.isEmpty) return [];
      final f = ProtoReader.decode(raw);
      // ListPeerResponse: field 1 = repeated PeerInfo
      final peerInfos = f.getRepeatedMessage(1);
      final conns = <PeerConnInfo>[];

      for (final peerMsg in peerInfos) {
        // PeerInfo: peer_id=1, repeated PeerConnInfo conns=2
        final peerId = peerMsg.getVarint(1);
        final connMsgs = peerMsg.getRepeatedMessage(2);
        for (final connMsg in connMsgs) {
          conns.add(_parsePeerConn(connMsg, peerId));
        }
      }
      return conns;
    } on RpcException {
      return [];
    }
  }

  /// PeerConnInfo proto:
  /// ```
  /// string conn_id = 1;
  /// uint32 my_peer_id = 2;
  /// uint32 peer_id = 3;
  /// repeated string features = 4;
  /// common.TunnelInfo tunnel = 5;
  /// PeerConnStats stats = 6;
  /// float loss_rate = 7;
  /// bool is_client = 8;
  /// string network_name = 9;
  /// bool is_closed = 10;
  /// ```
  PeerConnInfo _parsePeerConn(ProtoFields f, int peerIdHint) {
    final connId = f.getString(1);
    final peerId = f.getVarint(3, peerIdHint);
    final features = f.getRepeatedString(4);

    // TunnelInfo: tunnel_type=1, local_addr=2(Url), remote_addr=3(Url)
    String tunnelType = '';
    String localAddr = '';
    String remoteAddr = '';
    final tunnelMsg = f.getMessage(5);
    if (tunnelMsg != null) {
      tunnelType = tunnelMsg.getString(1);
      localAddr = _parseUrl(tunnelMsg.getMessage(2));
      remoteAddr = _parseUrl(tunnelMsg.getMessage(3));
    }

    // PeerConnStats: rx_bytes=1, tx_bytes=2, rx_packets=3, tx_packets=4, latency_us=5
    int rxBytes = 0, txBytes = 0, rxPackets = 0, txPackets = 0;
    double latencyMs = 0;
    final statsMsg = f.getMessage(6);
    if (statsMsg != null) {
      rxBytes = statsMsg.getVarint(1);
      txBytes = statsMsg.getVarint(2);
      rxPackets = statsMsg.getVarint(3);
      txPackets = statsMsg.getVarint(4);
      latencyMs = statsMsg.getVarint(5) / 1000.0;
    }

    // loss_rate is float (wire type fixed32)
    double lossRate = 0;
    final lossBytes = f.getBytes(7);
    if (lossBytes.length == 4) {
      lossRate = ByteData.sublistView(lossBytes).getFloat32(0, Endian.little);
    }

    return PeerConnInfo(
      peerId: peerId,
      connId: connId,
      tunnelType: tunnelType,
      localAddr: localAddr,
      remoteAddr: remoteAddr,
      rxBytes: rxBytes,
      txBytes: txBytes,
      rxPackets: rxPackets,
      txPackets: txPackets,
      latencyMs: latencyMs,
      lossRate: lossRate,
      features: features,
      networkName: f.getString(9),
      isClient: f.getBool(8),
      isClosed: f.getBool(10),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Routes (ListRoute → ListRouteResponse { repeated Route routes=1 })
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<PeerRouteInfo>> listRoutes() async {
    try {
      final raw = await _client.call(EtRpc.listRoute, _emptyRequest);
      if (raw.isEmpty) return [];
      final f = ProtoReader.decode(raw);
      final routeMsgs = f.getRepeatedMessage(1);
      return routeMsgs.map(_parseRoute).toList();
    } on RpcException {
      return [];
    }
  }

  /// Route proto:
  /// ```
  /// uint32 peer_id = 1;
  /// common.Ipv4Inet ipv4_addr = 2;
  /// uint32 next_hop_peer_id = 3;
  /// int32 cost = 4;
  /// repeated string proxy_cidrs = 5;
  /// string hostname = 6;
  /// common.StunInfo stun_info = 7;
  /// string inst_id = 8;
  /// string version = 9;
  /// common.PeerFeatureFlag feature_flag = 10;
  /// int32 path_latency = 11;          // microseconds
  /// common.Ipv6Inet ipv6_addr = 15;
  /// ```
  PeerRouteInfo _parseRoute(ProtoFields f) {
    final peerId = f.getVarint(1);

    // Ipv4Inet: Ipv4Addr addr=1 { uint32 addr=1 }, uint32 network_length=2
    String ipv4 = '';
    final ipv4Msg = f.getMessage(2);
    if (ipv4Msg != null) {
      final addrMsg = ipv4Msg.getMessage(1);
      if (addrMsg != null) {
        ipv4 = _uint32ToIpv4(addrMsg.getVarint(1));
      }
    }

    final nextHop = f.getVarint(3);
    final cost = f.getVarint(4);
    final proxyCidrs = f.getRepeatedString(5);
    final hostname = f.getString(6);
    final version = f.getString(9);
    final latUs = f.getVarint(11);

    // StunInfo
    String udpNatType = '';
    String tcpNatType = '';
    final stunMsg = f.getMessage(7);
    if (stunMsg != null) {
      udpNatType = _natTypeStr(stunMsg.getVarint(1));
      tcpNatType = _natTypeStr(stunMsg.getVarint(2));
    }

    // Ipv6Inet ipv6_addr = 15 → { Ipv6Addr address=1, uint32 network_length=2 }
    // Ipv6Addr { uint32 part1=1, uint32 part2=2, uint32 part3=3, uint32 part4=4 }
    String ipv6 = '';
    final ipv6Msg = f.getMessage(15);
    if (ipv6Msg != null) {
      final addrMsg = ipv6Msg.getMessage(1);
      if (addrMsg != null) {
        ipv6 = _ipv6FromParts(addrMsg);
      }
    }

    return PeerRouteInfo(
      peerId: peerId,
      ipv4Addr: ipv4,
      ipv6Addr: ipv6,
      hostname: hostname,
      nextHopPeerId: nextHop,
      cost: cost,
      latencyMs: latUs / 1000.0,
      proxyCidrs: proxyCidrs,
      udpNatType: udpNatType,
      tcpNatType: tcpNatType,
      version: version,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  /// Url message: field 1 = string url
  String _parseUrl(ProtoFields? f) => f?.getString(1) ?? '';

  /// Convert big-endian u32 to dotted IPv4 string.
  String _uint32ToIpv4(int addr) {
    if (addr == 0) return '';
    return '${(addr >> 24) & 0xFF}.${(addr >> 16) & 0xFF}'
        '.${(addr >> 8) & 0xFF}.${addr & 0xFF}';
  }

  /// Ipv6Addr { uint32 part1=1, part2=2, part3=3, part4=4 }
  /// Each part is a big-endian 32-bit chunk of the 128-bit address.
  String _ipv6FromParts(ProtoFields addrMsg) {
    final p1 = addrMsg.getVarint(1);
    final p2 = addrMsg.getVarint(2);
    final p3 = addrMsg.getVarint(3);
    final p4 = addrMsg.getVarint(4);
    if (p1 == 0 && p2 == 0 && p3 == 0 && p4 == 0) return '';

    String h(int v, int shift) =>
        ((v >> shift) & 0xFFFF).toRadixString(16);

    return '${h(p1, 16)}:${h(p1, 0)}:${h(p2, 16)}:${h(p2, 0)}'
        ':${h(p3, 16)}:${h(p3, 0)}:${h(p4, 16)}:${h(p4, 0)}';
  }
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

String _natTypeStr(int v) => _natTypeNames[v] ?? 'Unknown';
