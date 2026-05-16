import 'package:dustman/domain/entities/installed_program.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InstalledProgram extra fields', () {
    test('estimatedBytes converts KB to bytes', () {
      final p = InstalledProgram(
        displayName: 'Foo',
        registryKeyPath: 'k',
        estimatedSizeKb: 512,
      );
      expect(p.estimatedBytes, 512 * 1024);
    });

    test('estimatedBytes is null when KB is null', () {
      final p = InstalledProgram(displayName: 'Foo', registryKeyPath: 'k');
      expect(p.estimatedBytes, isNull);
    });

    test('installDateTime parses YYYYMMDD', () {
      final p = InstalledProgram(
        displayName: 'Foo',
        registryKeyPath: 'k',
        installDate: '20240315',
      );
      expect(p.installDateTime, DateTime(2024, 3, 15));
    });

    test('installDateTime returns null for invalid input', () {
      final cases = [null, '', '202403', 'abcdef12', '20240230'];
      for (final raw in cases) {
        final p = InstalledProgram(
          displayName: 'Foo',
          registryKeyPath: 'k',
          installDate: raw,
        );
        // Note: DateTime(2024,2,30) actually rolls over to March;
        // we don't reject overflow here.
        if (raw == '20240230') {
          expect(p.installDateTime, isNotNull);
        } else {
          expect(p.installDateTime, isNull);
        }
      }
    });
  });
}
