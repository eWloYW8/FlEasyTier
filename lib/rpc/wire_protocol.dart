/// TCP wire protocol for EasyTier:
///
/// ```
/// [TCPTunnelHeader 4 bytes] [PeerManagerHeader 16 bytes] [Payload ...]
/// ```
///
/// All multi-byte integers are little-endian.
library;

import 'dart:typed_data';

// ── Constants ──

const int tcpTunnelHeaderSize = 4;
const int peerManagerHeaderSize = 16;
const int totalHeaderSize = tcpTunnelHeaderSize + peerManagerHeaderSize;

/// PacketType values (u8).
const int packetTypeRpcReq = 8;
const int packetTypeRpcResp = 9;

// ═══════════════════════════════════════════════════════════════════════════
// Encode a frame for sending over TCP
// ═══════════════════════════════════════════════════════════════════════════

/// Build a complete TCP frame:
/// `[tcp_len:u32le] [from:u32le] [to:u32le] [type:u8] [flags:u8]
///  [fwd:u8] [reserved:u8] [payload_len:u32le] [payload...]`
Uint8List encodeFrame({
  required int fromPeerId,
  required int toPeerId,
  required int packetType,
  required Uint8List payload,
}) {
  final payloadLen = payload.length;
  final totalLen = peerManagerHeaderSize + payloadLen;
  final frame = Uint8List(tcpTunnelHeaderSize + totalLen);
  final bd = ByteData.sublistView(frame);

  // TCPTunnelHeader
  bd.setUint32(0, totalLen, Endian.little);

  // PeerManagerHeader
  bd.setUint32(4, fromPeerId, Endian.little);
  bd.setUint32(8, toPeerId, Endian.little);
  frame[12] = packetType; // packet_type
  frame[13] = 0; // flags
  frame[14] = 1; // forward_counter
  frame[15] = 0; // reserved
  bd.setUint32(16, payloadLen, Endian.little);

  // Payload
  frame.setRange(totalHeaderSize, totalHeaderSize + payloadLen, payload);
  return frame;
}

// ═══════════════════════════════════════════════════════════════════════════
// Decode a frame received from TCP
// ═══════════════════════════════════════════════════════════════════════════

class DecodedFrame {
  final int fromPeerId;
  final int toPeerId;
  final int packetType;
  final int flags;
  final Uint8List payload;

  const DecodedFrame({
    required this.fromPeerId,
    required this.toPeerId,
    required this.packetType,
    required this.flags,
    required this.payload,
  });
}

/// Try to extract one complete frame from the buffer.
///
/// Returns `(frame, bytesConsumed)` or `(null, 0)` if not enough data.
(DecodedFrame?, int) tryDecodeFrame(Uint8List buffer, int offset, int length) {
  if (length < tcpTunnelHeaderSize) return (null, 0);

  final bd = ByteData.sublistView(buffer, offset, offset + length);
  final totalLen = bd.getUint32(0, Endian.little);

  final frameSize = tcpTunnelHeaderSize + totalLen;
  if (length < frameSize) return (null, 0);

  if (totalLen < peerManagerHeaderSize) {
    // Malformed — skip this frame
    return (null, frameSize);
  }

  final fromPeer = bd.getUint32(4, Endian.little);
  final toPeer = bd.getUint32(8, Endian.little);
  final packetType = buffer[offset + 12];
  final flags = buffer[offset + 13];
  final payloadLen = bd.getUint32(16, Endian.little);

  final payloadStart = offset + totalHeaderSize;
  final payloadEnd = payloadStart + payloadLen;
  final clampedEnd = payloadEnd.clamp(0, buffer.length);

  final payload = Uint8List.sublistView(buffer, payloadStart, clampedEnd);

  return (
    DecodedFrame(
      fromPeerId: fromPeer,
      toPeerId: toPeer,
      packetType: packetType,
      flags: flags,
      payload: payload,
    ),
    frameSize,
  );
}
