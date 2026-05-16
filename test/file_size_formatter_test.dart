import 'package:dustman/core/utils/file_size_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileSizeFormatter', () {
    test('returns 0 B for non-positive input', () {
      expect(FileSizeFormatter.format(0), '0 B');
      expect(FileSizeFormatter.format(-100), '0 B');
    });

    test('uses bytes without decimals', () {
      expect(FileSizeFormatter.format(512), '512 B');
    });

    test('escalates to higher units', () {
      expect(FileSizeFormatter.format(1024), '1.00 KB');
      expect(FileSizeFormatter.format(1024 * 1024), '1.00 MB');
      expect(FileSizeFormatter.format(1024 * 1024 * 1024), '1.00 GB');
    });

    test('respects fractionDigits', () {
      expect(
        FileSizeFormatter.format(1536, fractionDigits: 1),
        '1.5 KB',
      );
    });
  });
}
