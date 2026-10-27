import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jazyk aplikácie – podľa neho sa zobrazujú a hľadajú potraviny
/// a v ňom odpovedá AI.
enum AppLanguage {
  sk('Slovenčina', '🇸🇰', 'Slovak'),
  cs('Čeština', '🇨🇿', 'Czech'),
  en('English', '🇬🇧', 'English');

  const AppLanguage(this.label, this.flag, this.englishName);
  final String label;
  final String flag;

  /// Názov jazyka po anglicky (pre prompt do AI).
  final String englishName;

  /// Aktuálne zvolený jazyk.
  static AppLanguage get current => AppLanguageController.instance.value;
}

/// Drží zvolený jazyk a ukladá ho do telefónu.
class AppLanguageController extends ValueNotifier<AppLanguage> {
  AppLanguageController._() : super(AppLanguage.sk);
  static final instance = AppLanguageController._();

  static const _key = 'app_language';

  /// Načíta uložený jazyk (volá sa pri štarte aplikácie).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    value = AppLanguage.values.firstWhere(
      (l) => l.name == saved,
      orElse: () => AppLanguage.sk,
    );
  }

  Future<void> set(AppLanguage language) async {
    value = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, language.name);
  }
}
