import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/services/settings_store.dart';

/// 应用语言。'zh' / 'en'，跟随系统时为 'system'。
class LocaleProvider extends ChangeNotifier {
  static const _key = 'locale';
  static const _supported = ['zh', 'en'];

  String _stored = 'system';

  /// 用户设置；可能是 'system' / 'zh' / 'en'。
  String get stored => _stored;

  /// 实际应用的语言代码 'zh' 或 'en'。
  String get effective {
    if (_stored == 'system') {
      final code = PlatformDispatcher.instance.locale.languageCode;
      return _supported.contains(code) ? code : 'zh';
    }
    return _stored;
  }

  Future<void> load() async {
    final v = await SettingsStore.instance.getString(_key);
    if (v != null && (v == 'system' || _supported.contains(v))) {
      _stored = v;
      notifyListeners();
    }
  }

  Future<void> setLocale(String code) async {
    if (_stored == code) return;
    _stored = code;
    notifyListeners();
    await SettingsStore.instance.setString(_key, code);
  }

  Locale? get materialLocale {
    if (_stored == 'system') return null;
    return _stored == 'en' ? const Locale('en', 'US') : const Locale('zh', 'CN');
  }

  /// 当前是否运行在测试或其它非桌面平台 —— 仅用于诊断显示。
  bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}
