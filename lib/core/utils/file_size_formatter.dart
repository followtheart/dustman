class FileSizeFormatter {
  FileSizeFormatter._();

  static const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

  /// 将字节数格式化为人类可读字符串，如 `1.23 MB`。
  static String format(int bytes, {int fractionDigits = 2}) {
    if (bytes <= 0) return '0 B';
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < _units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final digits = unitIndex == 0 ? 0 : fractionDigits;
    return '${size.toStringAsFixed(digits)} ${_units[unitIndex]}';
  }
}
