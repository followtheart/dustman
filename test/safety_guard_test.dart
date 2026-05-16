@TestOn('windows')
library;

import 'package:dustman/core/utils/safety_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafetyGuard (Windows-only)', () {
    test('blocks System32', () {
      expect(
        SafetyGuard.isSafeToDelete(r'C:\Windows\System32\drivers\etc\hosts'),
        isFalse,
      );
    });

    test('blocks recycle bin meta dir', () {
      expect(
        SafetyGuard.isSafeToDelete(r'C:\$Recycle.Bin\S-1-5-21-foo'),
        isFalse,
      );
    });

    test('allows temp files', () {
      expect(
        SafetyGuard.isSafeToDelete(r'C:\Users\me\AppData\Local\Temp\foo.tmp'),
        isTrue,
      );
    });
  });
}
