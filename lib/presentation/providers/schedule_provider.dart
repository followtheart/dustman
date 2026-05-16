import 'package:flutter/foundation.dart';

import '../../data/services/settings_store.dart';

enum ScheduleInterval {
  daily(1, 'schedule.intervalDaily'),
  weekly(7, 'schedule.intervalWeekly'),
  monthly(30, 'schedule.intervalMonthly');

  const ScheduleInterval(this.days, this.i18nKey);
  final int days;
  final String i18nKey;
}

/// 定期清理提醒。仅在用户主动启动 App 时检查；不做后台任务。
class ScheduleProvider extends ChangeNotifier {
  static const _kEnabled = 'schedule.enabled';
  static const _kInterval = 'schedule.interval';
  static const _kLastRunMs = 'schedule.lastRunMs';
  static const _kLastSkipMs = 'schedule.lastSkipMs';

  bool _enabled = false;
  ScheduleInterval _interval = ScheduleInterval.weekly;
  DateTime? _lastRun;
  DateTime? _lastSkip;

  bool get enabled => _enabled;
  ScheduleInterval get interval => _interval;
  DateTime? get lastRun => _lastRun;

  /// 距离上次提醒的天数（floor）。无记录时返回 null。
  int? get daysSinceLastRun {
    final lr = _lastRun;
    if (lr == null) return null;
    return DateTime.now().difference(lr).inDays;
  }

  /// 是否应该立刻弹提醒。规则：
  ///  - 未启用 / lastRun 在阈值内 → false
  ///  - 当前距离 lastSkip 不到 24h → false（用户刚刚 “稍后”）
  bool get isDue {
    if (!_enabled) return false;
    final now = DateTime.now();
    if (_lastSkip != null && now.difference(_lastSkip!) < const Duration(hours: 24)) {
      return false;
    }
    final lr = _lastRun;
    if (lr == null) return true;
    return now.difference(lr).inDays >= _interval.days;
  }

  Future<void> load() async {
    final store = SettingsStore.instance;
    _enabled = (await store.getBool(_kEnabled)) ?? false;
    final iv = await store.getString(_kInterval);
    _interval = ScheduleInterval.values
        .firstWhere((e) => e.name == iv, orElse: () => ScheduleInterval.weekly);
    final lr = await store.getInt(_kLastRunMs);
    if (lr != null && lr > 0) {
      _lastRun = DateTime.fromMillisecondsSinceEpoch(lr);
    }
    final ls = await store.getInt(_kLastSkipMs);
    if (ls != null && ls > 0) {
      _lastSkip = DateTime.fromMillisecondsSinceEpoch(ls);
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    if (_enabled == v) return;
    _enabled = v;
    notifyListeners();
    await SettingsStore.instance.setBool(_kEnabled, v);
  }

  Future<void> setInterval(ScheduleInterval interval) async {
    if (_interval == interval) return;
    _interval = interval;
    notifyListeners();
    await SettingsStore.instance.setString(_kInterval, interval.name);
  }

  /// 用户点击 "立即扫描" 后调用，记录当前时间。
  Future<void> markRanNow() async {
    _lastRun = DateTime.now();
    _lastSkip = null;
    notifyListeners();
    await SettingsStore.instance
        .setInt(_kLastRunMs, _lastRun!.millisecondsSinceEpoch);
    await SettingsStore.instance.remove(_kLastSkipMs);
  }

  /// 用户选择 "稍后"，24h 内不再提醒。
  Future<void> snooze() async {
    _lastSkip = DateTime.now();
    notifyListeners();
    await SettingsStore.instance
        .setInt(_kLastSkipMs, _lastSkip!.millisecondsSinceEpoch);
  }
}
