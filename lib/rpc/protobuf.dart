/// Minimal protobuf wire-format reader/writer.
///
/// Supports varint, length-delimited, and 32/64-bit fixed fields —
/// enough to encode/decode EasyTier RPC messages without protoc.
library;

import 'dart:convert';
import 'dart:typed_data';

// ── Wire types ──

const int wtVarint = 0;
const int wtFixed64 = 1;
const int wtLengthDelimited = 2;
const int wtFixed32 = 5;

// ═══════════════════════════════════════════════════════════════════════════
// Writer
// ═══════════════════════════════════════════════════════════════════════════

class ProtoWriter {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  Uint8List finish() => _buf.toBytes();

  int get length => _buf.length;

  // ── Tag ──

  void _writeTag(int fieldNumber, int wireType) {
    _writeVarint((fieldNumber << 3) | wireType);
  }

  // ── Varint ──

  void _writeVarint(int value) {
    // Encode as unsigned varint. For negative int64, use all 10 bytes.
    var v = value;
    while (v > 0x7f || v < 0) {
      _buf.addByte((v & 0x7f) | 0x80);
      // Logical right shift for unsigned behavior
      v = (v >> 7) & 0x01ffffffffffffff;
    }
    _buf.addByte(v & 0x7f);
  }

  void writeUint32(int fieldNumber, int value) {
    if (value == 0) return; // default omit
    _writeTag(fieldNumber, wtVarint);
    _writeVarint(value);
  }

  void writeUint64(int fieldNumber, int value) {
    if (value == 0) return;
    _writeTag(fieldNumber, wtVarint);
    _writeVarint(value);
  }

  void writeInt32(int fieldNumber, int value) {
    if (value == 0) return;
    _writeTag(fieldNumber, wtVarint);
    _writeVarint(value);
  }

  void writeInt64(int fieldNumber, int value) {
    if (value == 0) return;
    _writeTag(fieldNumber, wtVarint);
    _writeVarint(value);
  }

  void writeBool(int fieldNumber, bool value) {
    if (!value) return;
    _writeTag(fieldNumber, wtVarint);
    _buf.addByte(1);
  }

  void writeEnum(int fieldNumber, int value) {
    if (value == 0) return;
    _writeTag(fieldNumber, wtVarint);
    _writeVarint(value);
  }

  // ── Force-write (even if default value) ──

  void writeUint32Always(int fieldNumber, int value) {
    _writeTag(fieldNumber, wtVarint);
    _writeVarint(value);
  }

  void writeBoolAlways(int fieldNumber, bool value) {
    _writeTag(fieldNumber, wtVarint);
    _buf.addByte(value ? 1 : 0);
  }

  // ── Length-delimited ──

  void writeBytes(int fieldNumber, Uint8List value) {
    if (value.isEmpty) return;
    _writeTag(fieldNumber, wtLengthDelimited);
    _writeVarint(value.length);
    _buf.add(value);
  }

  void writeBytesAlways(int fieldNumber, Uint8List value) {
    _writeTag(fieldNumber, wtLengthDelimited);
    _writeVarint(value.length);
    _buf.add(value);
  }

  void writeString(int fieldNumber, String value) {
    if (value.isEmpty) return;
    final bytes = utf8.encode(value);
    _writeTag(fieldNumber, wtLengthDelimited);
    _writeVarint(bytes.length);
    _buf.add(bytes);
  }

  /// Write a sub-message. Encodes [writer]'s output as length-delimited.
  void writeMessage(int fieldNumber, ProtoWriter writer) {
    final bytes = writer.finish();
    if (bytes.isEmpty) return;
    _writeTag(fieldNumber, wtLengthDelimited);
    _writeVarint(bytes.length);
    _buf.add(bytes);
  }

  /// Write pre-encoded sub-message bytes.
  void writeMessageBytes(int fieldNumber, Uint8List value) {
    if (value.isEmpty) return;
    _writeTag(fieldNumber, wtLengthDelimited);
    _writeVarint(value.length);
    _buf.add(value);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reader
// ═══════════════════════════════════════════════════════════════════════════

/// Decoded protobuf fields as a map: fieldNumber → value(s).
///
/// Values are:
/// - `int` for varint fields
/// - `Uint8List` for length-delimited (bytes/string/message)
/// - `double` for fixed64 (as raw bits)
///
/// Repeated fields produce a `List`.
class ProtoFields {
  final Map<int, dynamic> _fields = {};

  void _add(int fieldNumber, dynamic value) {
    final existing = _fields[fieldNumber];
    if (existing == null) {
      _fields[fieldNumber] = value;
    } else if (existing is List<dynamic> && existing is! Uint8List) {
      existing.add(value);
    } else {
      _fields[fieldNumber] = <dynamic>[existing, value];
    }
  }

  // ── Accessors ──

  int getVarint(int fieldNumber, [int defaultValue = 0]) {
    final v = _fields[fieldNumber];
    if (v is int) return v;
    return defaultValue;
  }

  bool getBool(int fieldNumber, [bool defaultValue = false]) {
    final v = _fields[fieldNumber];
    if (v is int) return v != 0;
    return defaultValue;
  }

  Uint8List getBytes(int fieldNumber) {
    final v = _fields[fieldNumber];
    if (v is Uint8List) return v;
    return Uint8List(0);
  }

  String getString(int fieldNumber, [String defaultValue = '']) {
    final v = _fields[fieldNumber];
    if (v is Uint8List) return utf8.decode(v, allowMalformed: true);
    return defaultValue;
  }

  /// Decode a nested message from a length-delimited field.
  ProtoFields? getMessage(int fieldNumber) {
    final v = _fields[fieldNumber];
    if (v is Uint8List && v.isNotEmpty) return ProtoReader.decode(v);
    return null;
  }

  /// Get all values for a repeated field.
  List<Uint8List> getRepeatedBytes(int fieldNumber) {
    final v = _fields[fieldNumber];
    if (v is Uint8List) return [v];
    if (v is List) return v.whereType<Uint8List>().toList();
    return [];
  }

  List<ProtoFields> getRepeatedMessage(int fieldNumber) {
    return getRepeatedBytes(fieldNumber)
        .map((b) => ProtoReader.decode(b))
        .toList();
  }

  List<String> getRepeatedString(int fieldNumber) {
    return getRepeatedBytes(fieldNumber)
        .map((b) => utf8.decode(b, allowMalformed: true))
        .toList();
  }

  bool has(int fieldNumber) => _fields.containsKey(fieldNumber);
}

class ProtoReader {
  final Uint8List _data;
  int _pos = 0;

  ProtoReader(this._data);

  bool get hasMore => _pos < _data.length;

  int _readVarint() {
    int result = 0;
    int shift = 0;
    while (_pos < _data.length) {
      final b = _data[_pos++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift >= 64) break; // malformed
    }
    return result;
  }

  Uint8List _readBytes(int length) {
    final end = (_pos + length).clamp(0, _data.length);
    final result = Uint8List.sublistView(_data, _pos, end);
    _pos = end;
    return result;
  }

  /// Decode all fields from the buffer.
  static ProtoFields decode(Uint8List data) {
    final reader = ProtoReader(data);
    final fields = ProtoFields();

    while (reader.hasMore) {
      final tag = reader._readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      if (fieldNumber == 0) break; // invalid

      switch (wireType) {
        case wtVarint:
          fields._add(fieldNumber, reader._readVarint());
        case wtFixed64:
          fields._add(fieldNumber, reader._readBytes(8));
        case wtLengthDelimited:
          final len = reader._readVarint();
          fields._add(fieldNumber, reader._readBytes(len));
        case wtFixed32:
          fields._add(fieldNumber, reader._readBytes(4));
        default:
          break; // unknown wire type — skip not possible, break
      }
    }

    return fields;
  }
}
