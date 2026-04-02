/// EasyTier RPC message types — hand-coded protobuf encode/decode.
library;

import 'dart:typed_data';

import 'protobuf.dart';

// ── Compression algorithm enum ──

const int compressionNone = 1;
const int compressionZstd = 2;

// ═══════════════════════════════════════════════════════════════════════════
// RpcDescriptor
// ═══════════════════════════════════════════════════════════════════════════

class RpcDescriptor {
  final String domainName;
  final String protoName;
  final String serviceName;
  final int methodIndex;

  const RpcDescriptor({
    this.domainName = '',
    required this.protoName,
    required this.serviceName,
    required this.methodIndex,
  });

  Uint8List encode() {
    final w = ProtoWriter();
    w.writeString(1, domainName);
    w.writeString(2, protoName);
    w.writeString(3, serviceName);
    w.writeUint32(4, methodIndex);
    return w.finish();
  }

  factory RpcDescriptor.fromFields(ProtoFields f) => RpcDescriptor(
    domainName: f.getString(1),
    protoName: f.getString(2),
    serviceName: f.getString(3),
    methodIndex: f.getVarint(4),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// RpcCompressionInfo
// ═══════════════════════════════════════════════════════════════════════════

class RpcCompressionInfo {
  final int algo;
  final int acceptedAlgo;

  const RpcCompressionInfo({
    this.algo = compressionNone,
    this.acceptedAlgo = compressionNone,
  });

  Uint8List encode() {
    final w = ProtoWriter();
    w.writeEnum(1, algo);
    w.writeEnum(2, acceptedAlgo);
    return w.finish();
  }

  factory RpcCompressionInfo.fromFields(ProtoFields f) => RpcCompressionInfo(
    algo: f.getVarint(1, compressionNone),
    acceptedAlgo: f.getVarint(2, compressionNone),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// RpcPacket
// ═══════════════════════════════════════════════════════════════════════════

class RpcPacket {
  final int fromPeer;
  final int toPeer;
  final int transactionId;
  final RpcDescriptor? descriptor;
  final Uint8List body;
  final bool isRequest;
  final int totalPieces;
  final int pieceIdx;
  final int traceId;
  final RpcCompressionInfo? compressionInfo;

  const RpcPacket({
    this.fromPeer = 1,
    this.toPeer = 1,
    this.transactionId = 0,
    this.descriptor,
    required this.body,
    this.isRequest = true,
    this.totalPieces = 1,
    this.pieceIdx = 0,
    this.traceId = 0,
    this.compressionInfo,
  });

  Uint8List encode() {
    final w = ProtoWriter();
    w.writeUint32(1, fromPeer);
    w.writeUint32(2, toPeer);
    w.writeInt64(3, transactionId);
    if (descriptor != null) {
      w.writeMessageBytes(4, descriptor!.encode());
    }
    w.writeBytes(5, body);
    w.writeBool(6, isRequest);
    w.writeUint32(7, totalPieces);
    w.writeUint32(8, pieceIdx);
    w.writeInt32(9, traceId);
    if (compressionInfo != null) {
      w.writeMessageBytes(10, compressionInfo!.encode());
    }
    return w.finish();
  }

  factory RpcPacket.fromBytes(Uint8List data) {
    final f = ProtoReader.decode(data);
    final descFields = f.getMessage(4);
    final compFields = f.getMessage(10);
    return RpcPacket(
      fromPeer: f.getVarint(1, 1),
      toPeer: f.getVarint(2, 1),
      transactionId: f.getVarint(3),
      descriptor: descFields != null
          ? RpcDescriptor.fromFields(descFields)
          : null,
      body: f.getBytes(5),
      isRequest: f.getBool(6),
      totalPieces: f.getVarint(7, 1),
      pieceIdx: f.getVarint(8),
      traceId: f.getVarint(9),
      compressionInfo: compFields != null
          ? RpcCompressionInfo.fromFields(compFields)
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RpcRequest (what goes inside RpcPacket.body for requests)
// ═══════════════════════════════════════════════════════════════════════════

class RpcRequest {
  final Uint8List request;
  final int timeoutMs;

  const RpcRequest({required this.request, this.timeoutMs = 5000});

  Uint8List encode() {
    final w = ProtoWriter();
    w.writeBytesAlways(2, request); // field 2, always write even if empty
    w.writeInt32(3, timeoutMs);
    return w.finish();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RpcResponse (decoded from RpcPacket.body for responses)
// ═══════════════════════════════════════════════════════════════════════════

class RpcResponse {
  final Uint8List response;
  final RpcError? error;
  final int runtimeUs;

  const RpcResponse({required this.response, this.error, this.runtimeUs = 0});

  bool get hasError => error != null;

  factory RpcResponse.fromBytes(Uint8List data) {
    final f = ProtoReader.decode(data);
    final errFields = f.getMessage(2);
    return RpcResponse(
      response: f.getBytes(1),
      error: errFields != null ? RpcError.fromFields(errFields) : null,
      runtimeUs: f.getVarint(3),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// RpcError (simplified — we just extract the error message)
// ═══════════════════════════════════════════════════════════════════════════

class RpcError {
  final String message;
  final int errorKind; // field number from the oneof

  const RpcError({required this.message, required this.errorKind});

  factory RpcError.fromFields(ProtoFields f) {
    // Error has a oneof with fields 1-8, each containing an error message.
    // We check each and extract the message string from the first found.
    for (int i = 1; i <= 8; i++) {
      if (f.has(i)) {
        final inner = f.getMessage(i);
        final msg = inner?.getString(1) ?? 'Unknown error (kind $i)';
        return RpcError(message: msg, errorKind: i);
      }
    }
    return const RpcError(message: 'Unknown error', errorKind: 0);
  }

  @override
  String toString() => 'RpcError($errorKind): $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Service descriptors
// ═══════════════════════════════════════════════════════════════════════════

/// EasyTier RPC service method descriptors.
///
/// IMPORTANT:
/// - `protoName` and `serviceName` are both the protobuf service name
///   (the server registers services with proto_name = service proto_name).
/// - `methodIndex` is **1-based** (generated enum starts at idx+1).
abstract final class EtRpc {
  // PeerManageRpc — methods: ListPeer=1, ListRoute=2, DumpRoute=3,
  //   ListForeignNetwork=4, ListGlobalForeignNetwork=5, ShowNodeInfo=6,
  //   GetForeignNetworkSummary=7
  static const listPeer = RpcDescriptor(
    protoName: 'PeerManageRpc',
    serviceName: 'PeerManageRpc',
    methodIndex: 1,
  );
  static const listRoute = RpcDescriptor(
    protoName: 'PeerManageRpc',
    serviceName: 'PeerManageRpc',
    methodIndex: 2,
  );
  static const dumpRoute = RpcDescriptor(
    protoName: 'PeerManageRpc',
    serviceName: 'PeerManageRpc',
    methodIndex: 3,
  );
  static const listForeignNetwork = RpcDescriptor(
    protoName: 'PeerManageRpc',
    serviceName: 'PeerManageRpc',
    methodIndex: 4,
  );
  static const listGlobalForeignNetwork = RpcDescriptor(
    protoName: 'PeerManageRpc',
    serviceName: 'PeerManageRpc',
    methodIndex: 5,
  );
  static const showNodeInfo = RpcDescriptor(
    protoName: 'PeerManageRpc',
    serviceName: 'PeerManageRpc',
    methodIndex: 6,
  );

  // ConnectorManageRpc — ListConnector=1
  static const listConnector = RpcDescriptor(
    protoName: 'ConnectorManageRpc',
    serviceName: 'ConnectorManageRpc',
    methodIndex: 1,
  );

  // VpnPortalRpc — GetVpnPortalInfo=1
  static const getVpnPortalInfo = RpcDescriptor(
    protoName: 'VpnPortalRpc',
    serviceName: 'VpnPortalRpc',
    methodIndex: 1,
  );

  // StatsRpc — GetStats=1, GetPrometheusStats=2
  static const getStats = RpcDescriptor(
    protoName: 'StatsRpc',
    serviceName: 'StatsRpc',
    methodIndex: 1,
  );

  // LoggerRpc — SetLoggerConfig=1, GetLoggerConfig=2
  static const setLoggerConfig = RpcDescriptor(
    protoName: 'LoggerRpc',
    serviceName: 'LoggerRpc',
    methodIndex: 1,
  );
  static const getLoggerConfig = RpcDescriptor(
    protoName: 'LoggerRpc',
    serviceName: 'LoggerRpc',
    methodIndex: 2,
  );
}
