import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String _keyFontScale = 'font_scale';
  static const String _keyIsDarkMode = 'is_dark_mode';
  static const String _keyTtsVolume = 'tts_volume';

  final ValueNotifier<double> fontScaleNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> ttsVolumeNotifier = ValueNotifier<double>(1.0);

  double get fontScale => fontScaleNotifier.value;
  bool get isDarkMode => isDarkModeNotifier.value;
  double get ttsVolume => ttsVolumeNotifier.value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    var fontScale = prefs.getDouble(_keyFontScale);
    final isDark = prefs.getBool(_keyIsDarkMode);
    final ttsVolume = prefs.getDouble(_keyTtsVolume);

    fontScale ??= 1.0;
    fontScaleNotifier.value = fontScale.clamp(1.0, 1.5);
    isDarkModeNotifier.value = isDark ?? false;
    ttsVolumeNotifier.value = (ttsVolume ?? 1.0).clamp(0.0, 1.0);
  }

  Future<void> setFontScale(double value) async {
    final v = value.clamp(1.0, 1.5);
    fontScaleNotifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontScale, v);
  }

  Future<void> cycleFontScale() async {
    const steps = [1.0, 1.2, 1.4];
    final currentIndex = steps.indexWhere(
      (s) => (s - fontScaleNotifier.value).abs() < 0.001,
    );
    final nextIndex = currentIndex == -1
        ? 0
        : (currentIndex + 1) % steps.length;
    await setFontScale(steps[nextIndex]);
  }

  Future<void> setDarkMode(bool value) async {
    isDarkModeNotifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsDarkMode, value);
  }

  Future<void> setTtsVolume(double value) async {
    final v = value.clamp(0.0, 1.0);
    ttsVolumeNotifier.value = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTtsVolume, v);
  }

  Future<void> volumeUp() async {
    await setTtsVolume(ttsVolumeNotifier.value + 0.1);
  }

  Future<void> volumeDown() async {
    await setTtsVolume(ttsVolumeNotifier.value - 0.1);
  }
}
