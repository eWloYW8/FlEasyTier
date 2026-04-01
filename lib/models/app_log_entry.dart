enum AppLogLevel {
  info,
  warning,
  error,
}

class AppLogEntry {
  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String message;
  final String? detail;

  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.detail,
  });

  String get levelLabel => switch (level) {
        AppLogLevel.info => 'Info',
        AppLogLevel.warning => 'Warn',
        AppLogLevel.error => 'Error',
      };

  String toPlainText() {
    final time = timestamp.toIso8601String();
    final base = '[$time] [$category] [$levelLabel] $message';
    if (detail == null || detail!.trim().isEmpty) return base;
    return '$base\n$detail';
  }
}
