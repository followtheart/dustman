/// Dustman 发行版次（社区版 / 付费版）。
///
/// **决策来源**：[docs/V0_4_PLAN.md §10.5](../../docs/V0_4_PLAN.md)。
///
/// - **Community**：v0.3 全部能力，**完全不含** FileClaw / 账户 / 支付代码。
/// - **Pro**：在 Community 基础上叠加 FileClaw AI 操作建议、账户、会员订阅。
///
/// 通过编译期 `--dart-define` 选择版次：
/// ```
/// flutter build windows --release --dart-define=DUSTMAN_EDITION=community
/// flutter build windows --release --dart-define=DUSTMAN_EDITION=pro
/// ```
///
/// 由于 [kEditionRaw] 是 `const String.fromEnvironment`，Dart 编译器在 release
/// 构建下会**树摇（tree-shake）**掉 `Edition.isPro` 为 false 分支引用的代码 ——
/// Community 版二进制中不应包含任何 fileclaw / billing / endpoint 字符串。
///
/// 验收：
/// ```
/// strings build\windows\x64\runner\Release\dustman.exe | grep -i fileclaw
/// # Community 构建应返回空。
/// ```
library;

/// 原始定义值，仅本文件内部使用。
const String _kEditionRaw = String.fromEnvironment(
  'DUSTMAN_EDITION',
  defaultValue: 'community',
);

/// 当前构建版次。
const Edition kEdition = _kEditionRaw == 'pro' ? Edition.pro : Edition.community;

enum Edition {
  community,
  pro;

  /// 是否为付费版。等价于 `kEdition == Edition.pro`，
  /// 写成 `Edition.pro == kEdition` 的展开形式便于 Dart 常量折叠。
  bool get isPro => this == Edition.pro;

  /// 在 UI 与日志中展示的标签。
  String get label => switch (this) {
        Edition.community => 'Community',
        Edition.pro => 'Pro',
      };
}

/// 便捷常量：编译期布尔，可直接用于 `if` 条件以触发 tree-shaking。
const bool kIsPro = kEdition == Edition.pro;
