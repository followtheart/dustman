import 'package:dustman/data/services/uninstaller_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UninstallerService._splitCommand', () {
    test('quoted exe with trailing args', () {
      final (exe, args) = UninstallerService.splitCommandForTest(
        r'"C:\Program Files\Foo\unins000.exe" /SILENT /NORESTART',
      );
      expect(exe, r'C:\Program Files\Foo\unins000.exe');
      expect(args, '/SILENT /NORESTART');
    });

    test('quoted exe without args', () {
      final (exe, args) = UninstallerService.splitCommandForTest(
        r'"C:\App\uninst.exe"',
      );
      expect(exe, r'C:\App\uninst.exe');
      expect(args, '');
    });

    test('unquoted exe with args', () {
      final (exe, args) = UninstallerService.splitCommandForTest(
        r'C:\Windows\foo.exe /q',
      );
      expect(exe, r'C:\Windows\foo.exe');
      expect(args, '/q');
    });

    test('MsiExec style command', () {
      final (exe, args) = UninstallerService.splitCommandForTest(
        'MsiExec.exe /X{12345678-1234-1234-1234-123456789012}',
      );
      expect(exe, 'MsiExec.exe');
      expect(args, '/X{12345678-1234-1234-1234-123456789012}');
    });

    test('empty input', () {
      final (exe, args) = UninstallerService.splitCommandForTest('');
      expect(exe, '');
      expect(args, '');
    });

    test('whitespace input', () {
      final (exe, args) = UninstallerService.splitCommandForTest('   ');
      expect(exe, '');
      expect(args, '');
    });
  });
}
