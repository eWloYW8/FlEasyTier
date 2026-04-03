enum AppLanguage {
  system,
  english,
  chinese;

  static AppLanguage fromName(String? value) {
    return AppLanguage.values.where((item) => item.name == value).firstOrNull ??
        AppLanguage.system;
  }
}
