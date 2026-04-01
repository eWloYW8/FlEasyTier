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

  Future<NodeInfo?> getNodeInfo() async {
    try {
      final raw = await _client.call(EtRpc.showNodeInfo, _emptyRequest);
      if (raw.isEmpty) return null;
      final fields = ProtoReader.decode(raw);
      final nodeMsg = fields.getMessage(1);
      if (nodeMsg == null) return null;
      return _parseNodeInfo(nodeMsg);
    } on RpcException {
      return null;
    }
  }

  Future<List<PeerConnInfo>> listPeers() async {
    try {
      final raw = await _client.call(EtRpc.listPeer, _emptyRequest);
      if (raw.isEmpty) return [];
      final fields = ProtoReader.decode(raw);
      final peerInfos = fields.getRepeatedMessage(1);
      final conns = <PeerConnInfo>[];

      for (final peerMsg in peerInfos) {
        final peerId = peerMsg.getVarint(1);
        final defaultConnId = _parseUuid(peerMsg.getMessage(3));
        final connMsgs = peerMsg.getRepeatedMessage(2);
        for (final connMsg in connMsgs) {
          conns.add(_parsePeerConn(connMsg, peerId, defaultConnId));
        }
      }
      return conns;
    } on RpcException {
      return [];
    }
  }

  Future<List<PeerRouteInfo>> listRoutes() async {
    try {
      final raw = await _client.call(EtRpc.listRoute, _emptyRequest);
      if (raw.isEmpty) return [];
      final fields = ProtoReader.decode(raw);
      return fields.getRepeatedMessage(1).map(_parseRoute).toList();
    } on RpcException {
      return [];
    }
  }

  Future<List<MetricSnapshot>> getStats() async {
    try {
      final raw = await _client.call(EtRpc.getStats, _emptyRequest);
      if (raw.isEmpty) return [];
      final fields = ProtoReader.decode(raw);
      return fields.getRepeatedMessage(1).map(_parseMetric).toList();
    } on RpcException {
      return [];
    }
  }

  NodeInfo _parseNodeInfo(ProtoFields fields) {
    final ipv4Cidr = fields.getString(2);
    final stun = fields.getMessage(5);
    final ipList = fields.getMessage(11);

    return NodeInfo(
      peerId: fields.getVarint(1),
      virtualIpv4Cidr: ipv4Cidr,
      virtualIpv4: ipv4Cidr.split('/').first,
      hostname: fields.getString(4),
      udpNatType: _natTypeStr(stun?.getVarint(1) ?? 0),
      tcpNatType: _natTypeStr(stun?.getVarint(2) ?? 0),
      publicIps: [
        if (_parseIpv4(ipList?.getMessage(1)).isNotEmpty)
          _parseIpv4(ipList?.getMessage(1)),
        ..._readRepeatedIpv4(ipList, 2),
      ],
      publicIpv6: _parseIpv6(ipList?.getMessage(3)),
      interfaceIpv4s: _readRepeatedIpv4(ipList, 2),
      interfaceIpv6s: _readRepeatedIpv6(ipList, 4),
      listeners: {
        ...fields.getRepeatedString(7),
        ..._readRepeatedUrl(ipList, 5),
      }.toList(),
      instId: fields.getString(6),
      configDump: fields.getString(8),
      version: fields.getString(9),
    );
  }

  PeerConnInfo _parsePeerConn(
    ProtoFields fields,
    int peerIdHint,
    String defaultConnId,
  ) {
    final tunnelMsg = fields.getMessage(5);
    final statsMsg = fields.getMessage(6);
    final lossBytes = fields.getBytes(7);

    double lossRate = 0;
    if (lossBytes.length == 4) {
      lossRate = ByteData.sublistView(lossBytes).getFloat32(0, Endian.little);
    }

    final connId = fields.getString(1);
    return PeerConnInfo(
      connId: connId,
      myPeerId: fields.getVarint(2),
      peerId: fields.getVarint(3, peerIdHint),
      features: fields.getRepeatedString(4),
      tunnelType: tunnelMsg?.getString(1) ?? '',
      localAddr: _parseUrl(tunnelMsg?.getMessage(2)),
      remoteAddr: _parseUrl(tunnelMsg?.getMessage(3)),
      rxBytes: statsMsg?.getVarint(1) ?? 0,
      txBytes: statsMsg?.getVarint(2) ?? 0,
      rxPackets: statsMsg?.getVarint(3) ?? 0,
      txPackets: statsMsg?.getVarint(4) ?? 0,
      latencyMs: (statsMsg?.getVarint(5) ?? 0) / 1000.0,
      lossRate: lossRate,
      isClient: fields.getBool(8),
      networkName: fields.getString(9),
      isClosed: fields.getBool(10),
      isDefault: defaultConnId.isNotEmpty && defaultConnId == connId,
      secureAuthLevel: _secureAuthLevel(fields.getVarint(13)),
      peerIdentityType: _peerIdentityType(fields.getVarint(14)),
    );
  }

  PeerRouteInfo _parseRoute(ProtoFields fields) {
    final ipv4Inet = fields.getMessage(2);
    final ipv6Inet = fields.getMessage(15);
    final stun = fields.getMessage(7);

    final ipv4Addr = _parseIpv4(ipv4Inet?.getMessage(1));
    final ipv4Cidr = ipv4Addr.isEmpty
        ? ''
        : '$ipv4Addr/${ipv4Inet?.getVarint(2) ?? 0}';

    return PeerRouteInfo(
      peerId: fields.getVarint(1),
      ipv4Addr: ipv4Addr,
      ipv4Cidr: ipv4Cidr,
      ipv6Addr: _parseIpv6(ipv6Inet?.getMessage(1)),
      nextHopPeerId: fields.getVarint(3),
      cost: fields.getVarint(4),
      latencyMs: fields.getVarint(11).toDouble(),
      proxyCidrs: fields.getRepeatedString(5),
      hostname: fields.getString(6),
      udpNatType: _natTypeStr(stun?.getVarint(1) ?? 0),
      tcpNatType: _natTypeStr(stun?.getVarint(2) ?? 0),
      instId: fields.getString(8),
      version: fields.getString(9),
      nextHopPeerIdLatencyFirst: fields.getVarint(12),
      costLatencyFirst: fields.getVarint(13),
      pathLatencyLatencyFirstMs: fields.getVarint(14).toDouble(),
    );
  }

  MetricSnapshot _parseMetric(ProtoFields fields) {
    final labels = <String, String>{};
    for (final labelMsg in fields.getRepeatedMessage(3)) {
      final key = labelMsg.getString(1);
      if (key.isEmpty) continue;
      labels[key] = labelMsg.getString(2);
    }

    return MetricSnapshot(
      name: fields.getString(1),
      value: fields.getVarint(2),
      labels: labels,
    );
  }

  String _parseUrl(ProtoFields? fields) => fields?.getString(1) ?? '';

  String _parseIpv4(ProtoFields? fields) {
    if (fields == null) return '';
    final addr = fields.getVarint(1);
    return _uint32ToIpv4(addr);
  }

  List<String> _readRepeatedIpv4(ProtoFields? parent, int fieldNumber) {
    if (parent == null) return const [];
    return parent
        .getRepeatedMessage(fieldNumber)
        .map(_parseIpv4)
        .where((ip) => ip.isNotEmpty)
        .toList();
  }

  String _parseIpv6(ProtoFields? fields) {
    if (fields == null) return '';
    final p1 = fields.getVarint(1);
    final p2 = fields.getVarint(2);
    final p3 = fields.getVarint(3);
    final p4 = fields.getVarint(4);
    if (p1 == 0 && p2 == 0 && p3 == 0 && p4 == 0) return '';
    String group(int v, int shift) => ((v >> shift) & 0xFFFF).toRadixString(16);
    return '${group(p1, 16)}:${group(p1, 0)}:${group(p2, 16)}:${group(p2, 0)}'
        ':${group(p3, 16)}:${group(p3, 0)}:${group(p4, 16)}:${group(p4, 0)}';
  }

  List<String> _readRepeatedIpv6(ProtoFields? parent, int fieldNumber) {
    if (parent == null) return const [];
    return parent
        .getRepeatedMessage(fieldNumber)
        .map(_parseIpv6)
        .where((ip) => ip.isNotEmpty)
        .toList();
  }

  List<String> _readRepeatedUrl(ProtoFields? parent, int fieldNumber) {
    if (parent == null) return const [];
    return parent
        .getRepeatedMessage(fieldNumber)
        .map(_parseUrl)
        .where((url) => url.isNotEmpty)
        .toList();
  }

  String _parseUuid(ProtoFields? fields) {
    if (fields == null) return '';
    final p1 = fields.getVarint(1).toRadixString(16).padLeft(8, '0');
    final p2 = fields.getVarint(2).toRadixString(16).padLeft(8, '0');
    final p3 = fields.getVarint(3).toRadixString(16).padLeft(8, '0');
    final p4 = fields.getVarint(4).toRadixString(16).padLeft(8, '0');
    final hex = '$p1$p2$p3$p4';
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  String _uint32ToIpv4(int addr) {
    if (addr == 0) return '';
    return '${(addr >> 24) & 0xFF}.${(addr >> 16) & 0xFF}.'
        '${(addr >> 8) & 0xFF}.${addr & 0xFF}';
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

String _natTypeStr(int value) => _natTypeNames[value] ?? 'Unknown';

String _secureAuthLevel(int value) => switch (value) {
      1 => 'Encrypted',
      2 => 'Peer Verified',
      3 => 'Secret Confirmed',
      _ => 'None',
    };

String _peerIdentityType(int value) => switch (value) {
      1 => 'Credential',
      2 => 'Shared Node',
      _ => 'Admin',
    };
