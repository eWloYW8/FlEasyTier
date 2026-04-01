// ignore_for_file: avoid_print
// Comprehensive RPC integration test — run: dart run test/rpc_diag.dart
import 'dart:io';

import 'package:fleasytier/rpc/easytier_api.dart';

Future<void> main() async {
  const host = '127.0.0.1';
  const port = 15888;

  print('=== EasyTier RPC Integration Test ===\n');

  final api = EasyTierApi(host: host, port: port);

  try {
    await api.connect();
    print('[OK] Connected to $host:$port\n');
  } catch (e) {
    print('[FAIL] Connection failed: $e');
    exit(1);
  }

  // ── Test 1: ShowNodeInfo ──
  print('--- Test 1: ShowNodeInfo ---');
  final nodeInfo = await api.getNodeInfo();
  if (nodeInfo == null) {
    print('[FAIL] getNodeInfo returned null');
  } else {
    print('[OK] NodeInfo received:');
    print('  peer_id:     ${nodeInfo.peerId}');
    print('  virtual_ipv4: ${nodeInfo.virtualIpv4}');
    print('  hostname:    ${nodeInfo.hostname}');
    print('  version:     ${nodeInfo.version}');
    print('  listeners:   ${nodeInfo.listeners}');
    print('  udp_nat:     ${nodeInfo.udpNatType}');
    print('  tcp_nat:     ${nodeInfo.tcpNatType}');
    print('  public_ips:  ${nodeInfo.publicIps}');

    // Validate
    assert(nodeInfo.peerId > 0, 'peer_id should be > 0');
    assert(nodeInfo.virtualIpv4.isNotEmpty, 'virtualIpv4 should not be empty');
    assert(nodeInfo.hostname.isNotEmpty, 'hostname should not be empty');
    assert(nodeInfo.version.isNotEmpty, 'version should not be empty');
    print('[OK] All NodeInfo fields validated\n');
  }

  // ── Test 2: ListPeer ──
  print('--- Test 2: ListPeer ---');
  final conns = await api.listPeers();
  print('[OK] ${conns.length} connections received:');
  for (final c in conns) {
    print('  peer=${c.peerId} tunnel=${c.tunnelLabel} '
        'remote=${c.remoteAddr} local=${c.localAddr} '
        'rx=${c.rxBytes} tx=${c.txBytes} '
        'lat=${c.latencyMs}ms loss=${c.lossRate} '
        'client=${c.isClient} closed=${c.isClosed} '
        'features=${c.features}');

    // Validate
    assert(c.peerId > 0, 'conn peer_id should be > 0');
    assert(c.remoteAddr.isNotEmpty || c.localAddr.isNotEmpty,
        'at least one addr should be non-empty');
  }
  print('[OK] All PeerConnInfo validated\n');

  // ── Test 3: ListRoute ──
  print('--- Test 3: ListRoute ---');
  final routes = await api.listRoutes();
  print('[OK] ${routes.length} routes received:');
  for (final r in routes) {
    print('  peer=${r.peerId} ipv4=${r.ipv4Addr} ipv6=${r.ipv6Addr} '
        'host=${r.hostname} next_hop=${r.nextHopPeerId} '
        'cost=${r.cost} latency=${r.latencyMs}ms '
        'direct=${r.isDirect} udp_nat=${r.udpNatType} '
        'version=${r.version} cidrs=${r.proxyCidrs}');

    // Validate
    assert(r.peerId > 0, 'route peer_id should be > 0');
    assert(r.ipv4Addr.isNotEmpty, 'route ipv4 should not be empty');
    assert(r.hostname.isNotEmpty, 'route hostname should not be empty');
  }
  print('[OK] All Route fields validated\n');

  // ── Summary ──
  print('=== ALL TESTS PASSED ===');
  print('  NodeInfo: peer_id=${nodeInfo?.peerId}, '
      'ip=${nodeInfo?.virtualIpv4}, host=${nodeInfo?.hostname}');
  print('  Peers: ${conns.length} connections to '
      '${conns.map((c) => c.peerId).toSet().length} unique peers');
  print('  Routes: ${routes.length} routes, '
      '${routes.where((r) => r.isDirect).length} direct');

  await api.close();
  exit(0);
}
