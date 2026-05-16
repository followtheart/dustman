import 'package:dustman/core/utils/registry_safety_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegistrySafetyGuard', () {
    test('blocks HKLM\\SOFTWARE\\Microsoft', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'HKLM\SOFTWARE\Microsoft'),
        isFalse,
      );
      expect(
        RegistrySafetyGuard.isSafeToDelete(
            r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion'),
        isFalse,
      );
    });

    test('blocks SYSTEM / SECURITY / SAM', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'HKLM\SYSTEM\CurrentControlSet'),
        isFalse,
      );
      expect(RegistrySafetyGuard.isSafeToDelete(r'HKLM\SECURITY'), isFalse);
      expect(RegistrySafetyGuard.isSafeToDelete(r'HKLM\SAM'), isFalse);
    });

    test('blocks too-shallow paths', () {
      expect(RegistrySafetyGuard.isSafeToDelete(r'HKLM'), isFalse);
      expect(RegistrySafetyGuard.isSafeToDelete(r'HKLM\SOFTWARE'), isFalse);
      expect(RegistrySafetyGuard.isSafeToDelete(r''), isFalse);
    });

    test('blocks non-SOFTWARE roots', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'HKLM\HARDWARE\foo'),
        isFalse,
      );
    });

    test('blocks HKEY_CLASSES_ROOT-style or unknown roots', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'HKCR\foo'),
        isFalse,
      );
    });

    test('allows non-protected publisher under HKLM\\SOFTWARE', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'HKLM\SOFTWARE\Adobe'),
        isTrue,
      );
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'HKCU\SOFTWARE\Foo\Bar'),
        isTrue,
      );
    });

    test('case-insensitive matching', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(r'hklm\software\microsoft'),
        isFalse,
      );
    });

    test('blocks Wow6432Node\\Microsoft variant', () {
      expect(
        RegistrySafetyGuard.isSafeToDelete(
            r'HKLM\SOFTWARE\Wow6432Node\Microsoft\Foo'),
        isFalse,
      );
    });
  });
}
