/// EasyTier RPC client — connects to easytier-core's RPC portal via TCP,
/// frames messages, correlates request/response by transaction_id,
/// and handles message fragmentation/reassembly.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'rpc_types.dart';
import 'wire_protocol.dart';

/// Exception thrown on RPC-level errors.
class RpcException implements Exception {
  final String message;
  const RpcException(this.message);
  @override
  String toString() => 'RpcException: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// RpcClient
// ═══════════════════════════════════════════════════════════════════════════

class RpcClient {
  final String host;
  final int port;

  Socket? _socket;
  bool _connected = false;
  int _nextTxId = Random().nextInt(1 << 30);

  /// Pending requests: transactionId → completer for the reassembled body.
  final Map<int, Completer<RpcResponse>> _pending = {};

  /// Fragment reassembly buffer: transactionId → list of body pieces.
  final Map<int, _FragmentBuffer> _fragments = {};

  /// Incoming TCP byte buffer.
  final BytesBuilder _recvBuf = BytesBuilder(copy: false);
  int _recvLen = 0;

  RpcClient({this.host = '127.0.0.1', required this.port});

  bool get connected => _connected;

  // ── Connect ──

  Future<void> connect() async {
    if (_connected) return;
    _socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    _connected = true;
    _recvBuf.clear();
    _recvLen = 0;

    _socket!.listen(
      _onData,
      onError: (e) => _disconnect('Socket error: $e'),
      onDone: () => _disconnect('Connection closed by peer'),
      cancelOnError: false,
    );
  }

  void _disconnect(String reason) {
    _connected = false;
    _socket?.destroy();
    _socket = null;
    _recvBuf.clear();
    _recvLen = 0;

    // Fail all pending requests
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(RpcException(reason));
    }
    _pending.clear();
    _fragments.clear();
  }

  Future<void> close() async {
    _disconnect('Client closed');
  }

  // ── Send RPC request ──

  /// Send an RPC request and wait for the response.
  ///
  /// [descriptor] identifies the service method.
  /// [requestPayload] is the serialized inner request message
  /// (e.g., ListPeerRequest).
  Future<Uint8List> call(
    RpcDescriptor descriptor,
    Uint8List requestPayload, {
    int timeoutMs = 5000,
  }) async {
    if (!_connected) {
      await connect();
    }

    final txId = _nextTxId++;

    // Build RpcRequest
    final rpcReq = RpcRequest(request: requestPayload, timeoutMs: timeoutMs);
    final rpcReqBytes = rpcReq.encode();

    // Build RpcPacket
    final packet = RpcPacket(
      fromPeer: 1,
      toPeer: 1,
      transactionId: txId,
      descriptor: descriptor,
      body: rpcReqBytes,
      isRequest: true,
      totalPieces: 1,
      pieceIdx: 0,
      compressionInfo: const RpcCompressionInfo(
        algo: compressionNone,
        acceptedAlgo: compressionNone, // Don't request Zstd — we can't decompress
      ),
    );

    final packetBytes = packet.encode();

    // Frame for TCP
    final frame = encodeFrame(
      fromPeerId: 1,
      toPeerId: 1,
      packetType: packetTypeRpcReq,
      payload: packetBytes,
    );

    // Register pending
    final completer = Completer<RpcResponse>();
    _pending[txId] = completer;

    // Send — retry once on failure (socket may have gone stale)
    try {
      _socket!.add(frame);
    } catch (_) {
      _pending.remove(txId);
      _disconnect('Send failed');
      // Reconnect and retry once
      try {
        await connect();
        _pending[txId] = completer;
        _socket!.add(frame);
      } catch (e) {
        _pending.remove(txId);
        _disconnect('Retry send failed: $e');
        rethrow;
      }
    }

    // Wait with timeout
    try {
      final resp = await completer.future
          .timeout(Duration(milliseconds: timeoutMs + 2000));
      if (resp.hasError) {
        throw RpcException(resp.error!.message);
      }
      return resp.response;
    } on TimeoutException {
      _pending.remove(txId);
      throw const RpcException('Request timed out');
    }
  }

  // ── Receive handling ──

  void _onData(Uint8List data) {
    // Append to receive buffer
    // We need a contiguous buffer for frame parsing
    if (_recvLen == 0) {
      _recvBuf.add(data);
      _recvLen += data.length;
    } else {
      _recvBuf.add(data);
      _recvLen += data.length;
    }

    // Consolidate into a single buffer for parsing
    final consolidated = _recvBuf.toBytes();
    _recvBuf.clear();
    _recvLen = 0;

    int offset = 0;
    while (offset < consolidated.length) {
      final remaining = consolidated.length - offset;
      final (frame, consumed) =
          tryDecodeFrame(consolidated, offset, remaining);

      if (consumed == 0) {
        // Not enough data — save remainder
        final leftover =
            Uint8List.sublistView(consolidated, offset, consolidated.length);
        _recvBuf.add(leftover);
        _recvLen = leftover.length;
        break;
      }

      offset += consumed;

      if (frame == null) continue; // malformed, skip
      if (frame.packetType != packetTypeRpcResp) continue; // not RPC response

      _handleRpcResponse(frame.payload);
    }
  }

  void _handleRpcResponse(Uint8List payload) {
    final RpcPacket packet;
    try {
      packet = RpcPacket.fromBytes(payload);
    } catch (_) {
      return; // malformed
    }

    final txId = packet.transactionId;

    // Handle fragmentation
    if (packet.totalPieces > 1) {
      final frag = _fragments.putIfAbsent(
          txId, () => _FragmentBuffer(packet.totalPieces));
      frag.addPiece(packet.pieceIdx, packet.body);

      // Store descriptor/compression from first piece
      if (packet.pieceIdx == 0) {
        frag.compressionInfo = packet.compressionInfo;
      }

      if (!frag.isComplete) return;

      // Reassemble
      final reassembled = frag.reassemble();
      _fragments.remove(txId);
      _deliverResponse(txId, reassembled, frag.compressionInfo);
    } else {
      _deliverResponse(txId, packet.body, packet.compressionInfo);
    }
  }

  void _deliverResponse(
    int txId,
    Uint8List body,
    RpcCompressionInfo? compInfo,
  ) {
    // Check if compression was used
    if (compInfo != null && compInfo.algo == compressionZstd) {
      // We requested no Zstd, but server may still send it.
      // In that case we fail gracefully.
      final completer = _pending.remove(txId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
            const RpcException('Server sent Zstd-compressed response'));
      }
      return;
    }

    final RpcResponse resp;
    try {
      resp = RpcResponse.fromBytes(body);
    } catch (e) {
      final completer = _pending.remove(txId);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(RpcException('Failed to decode response: $e'));
      }
      return;
    }

    final completer = _pending.remove(txId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(resp);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Fragment reassembly buffer
// ═══════════════════════════════════════════════════════════════════════════

class _FragmentBuffer {
  final int totalPieces;
  final Map<int, Uint8List> pieces = {};
  RpcCompressionInfo? compressionInfo;

  _FragmentBuffer(this.totalPieces);

  void addPiece(int idx, Uint8List data) {
    pieces[idx] = data;
  }

  bool get isComplete => pieces.length >= totalPieces;

  Uint8List reassemble() {
    final builder = BytesBuilder(copy: false);
    for (int i = 0; i < totalPieces; i++) {
      final piece = pieces[i];
      if (piece != null) builder.add(piece);
    }
    return builder.toBytes();
  }
}
