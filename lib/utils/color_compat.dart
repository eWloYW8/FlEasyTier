// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

Color withAlphaFactor(Color color, double alpha) {
  final normalized = alpha.clamp(0.0, 1.0);
  return color.withAlpha((normalized * 255).round());
}

int colorToArgb32(Color color) {
  return (color.alpha << 24) |
      (color.red << 16) |
      (color.green << 8) |
      color.blue;
}
