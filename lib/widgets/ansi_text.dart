/// Lightweight ANSI SGR escape code parser → Flutter TextSpan.
///
/// Supports: reset, bold, dim, italic, underline, standard 8/bright 8
/// foreground & background colors, and 256-color mode (38;5;N / 48;5;N).
library;

import 'package:flutter/widgets.dart';

import '../utils/color_compat.dart';

// ── Standard terminal color palette (dark-background friendly) ──

const _baseColors = <Color>[
  Color(0xFF3B4252), // 0 black
  Color(0xFFBF616A), // 1 red
  Color(0xFFA3BE8C), // 2 green
  Color(0xFFEBCB8B), // 3 yellow
  Color(0xFF81A1C1), // 4 blue
  Color(0xFFB48EAD), // 5 magenta
  Color(0xFF88C0D0), // 6 cyan
  Color(0xFFD8DEE9), // 7 white
];

const _brightColors = <Color>[
  Color(0xFF4C566A), // 8  bright black
  Color(0xFFD08770), // 9  bright red
  Color(0xFFA3BE8C), // 10 bright green
  Color(0xFFEBCB8B), // 11 bright yellow
  Color(0xFF5E81AC), // 12 bright blue
  Color(0xFFB48EAD), // 13 bright magenta
  Color(0xFF8FBCBB), // 14 bright cyan
  Color(0xFFECEFF4), // 15 bright white
];

// 6×6×6 color cube for 256-color mode (indices 16..231)
Color _cubeColor(int index) {
  final i = index - 16;
  final r = (i ~/ 36) * 51;
  final g = ((i % 36) ~/ 6) * 51;
  final b = (i % 6) * 51;
  return Color.fromARGB(255, r, g, b);
}

// Grayscale ramp for 256-color mode (indices 232..255)
Color _grayColor(int index) {
  final v = 8 + (index - 232) * 10;
  return Color.fromARGB(255, v, v, v);
}

Color? _color256(int n) {
  if (n < 0 || n > 255) return null;
  if (n < 8) return _baseColors[n];
  if (n < 16) return _brightColors[n - 8];
  if (n < 232) return _cubeColor(n);
  return _grayColor(n);
}

// ── SGR state ──

class _SgrState {
  Color? fg;
  Color? bg;
  bool bold = false;
  bool dim = false;
  bool italic = false;
  bool underline = false;

  _SgrState copy() => _SgrState()
    ..fg = fg
    ..bg = bg
    ..bold = bold
    ..dim = dim
    ..italic = italic
    ..underline = underline;
}

// ── Parser ──

final _ansiRe = RegExp(r'\x1b\[([0-9;]*)m');

/// Strip all ANSI escape sequences from [text].
String stripAnsi(String text) => text.replaceAll(_ansiRe, '');

/// Parse ANSI-colored [text] into a list of [TextSpan]s.
///
/// [defaultColor] is used when no foreground color is set.
List<TextSpan> parseAnsi(String text, {Color? defaultColor}) {
  final spans = <TextSpan>[];
  final state = _SgrState();
  int pos = 0;

  for (final match in _ansiRe.allMatches(text)) {
    // Text before this escape
    if (match.start > pos) {
      spans.add(
        _buildSpan(text.substring(pos, match.start), state, defaultColor),
      );
    }
    // Apply SGR parameters
    _applySgr(state, match.group(1) ?? '');
    pos = match.end;
  }

  // Trailing text
  if (pos < text.length) {
    spans.add(_buildSpan(text.substring(pos), state, defaultColor));
  }

  return spans;
}

TextSpan _buildSpan(String text, _SgrState s, Color? defaultColor) {
  var fg = s.fg ?? defaultColor;
  if (s.dim && fg != null) {
    fg = withAlphaFactor(fg, 0.55);
  }

  return TextSpan(
    text: text,
    style: TextStyle(
      color: fg,
      backgroundColor: s.bg,
      fontWeight: s.bold ? FontWeight.bold : null,
      fontStyle: s.italic ? FontStyle.italic : null,
      decoration: s.underline ? TextDecoration.underline : null,
    ),
  );
}

void _applySgr(_SgrState s, String params) {
  if (params.isEmpty) {
    _reset(s);
    return;
  }

  final codes = params.split(';').map((p) => int.tryParse(p) ?? 0).toList();
  int i = 0;

  while (i < codes.length) {
    final c = codes[i];
    switch (c) {
      case 0:
        _reset(s);
      case 1:
        s.bold = true;
      case 2:
        s.dim = true;
      case 3:
        s.italic = true;
      case 4:
        s.underline = true;
      case 22:
        s.bold = false;
        s.dim = false;
      case 23:
        s.italic = false;
      case 24:
        s.underline = false;
      case >= 30 && <= 37:
        s.fg = _baseColors[c - 30];
      case 38:
        // 256-color foreground: 38;5;N
        if (i + 2 < codes.length && codes[i + 1] == 5) {
          s.fg = _color256(codes[i + 2]);
          i += 2;
        }
      case 39:
        s.fg = null;
      case >= 40 && <= 47:
        s.bg = _baseColors[c - 40];
      case 48:
        // 256-color background: 48;5;N
        if (i + 2 < codes.length && codes[i + 1] == 5) {
          s.bg = _color256(codes[i + 2]);
          i += 2;
        }
      case 49:
        s.bg = null;
      case >= 90 && <= 97:
        s.fg = _brightColors[c - 90];
      case >= 100 && <= 107:
        s.bg = _brightColors[c - 100];
    }
    i++;
  }
}

void _reset(_SgrState s) {
  s.fg = null;
  s.bg = null;
  s.bold = false;
  s.dim = false;
  s.italic = false;
  s.underline = false;
}
