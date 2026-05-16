import 'package:dustman/domain/entities/installed_program.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InstalledProgram.matchKey', () {
    test('strips whitespace and punctuation', () {
      final p = InstalledProgram(
        displayName: 'Adobe AIR (32-bit)',
        registryKeyPath: r'HKLM\SOFTWARE\...\Adobe AIR',
      );
      expect(p.matchKey, 'adobeair32bit');
    });

    test('publisherKey is normalized too', () {
      final p = InstalledProgram(
        displayName: 'Foo',
        publisher: 'Adobe Inc.',
        registryKeyPath: 'k',
      );
      expect(p.publisherKey, 'adobeinc');
    });

    test('publisherKey is null when publisher missing', () {
      final p = InstalledProgram(displayName: 'Foo', registryKeyPath: 'k');
      expect(p.publisherKey, isNull);
    });
  });

  group('InstalledProgramIndex.matchesPath', () {
    test('matches by basename fuzzy match', () {
      final idx = InstalledProgramIndex([
        InstalledProgram(displayName: 'Adobe AIR', registryKeyPath: 'k'),
      ]);
      expect(idx.matchesPath(r'C:\Program Files\AdobeAIR'), isTrue);
      expect(idx.matchesPath(r'C:\Program Files\Adobe AIR'), isTrue);
    });

    test('does not match short noise', () {
      final idx = InstalledProgramIndex([
        InstalledProgram(displayName: 'Asus', registryKeyPath: 'k'),
      ]);
      // 不能让 "as" → "asus" 命中
      expect(idx.matchesPath(r'C:\Program Files\AS'), isFalse);
    });

    test('matches by install location containment (forward)', () {
      final idx = InstalledProgramIndex([
        InstalledProgram(
          displayName: 'Unrelated Name',
          installLocation: r'c:\program files\acme corp',
          registryKeyPath: 'k',
        ),
      ]);
      expect(
        idx.matchesPath(r'C:\Program Files\Acme Corp\plugin'),
        isTrue,
      );
    });

    test('matches by install location containment (reverse)', () {
      final idx = InstalledProgramIndex([
        InstalledProgram(
          displayName: 'Unrelated',
          installLocation: r'c:\program files\acme corp\bin',
          registryKeyPath: 'k',
        ),
      ]);
      expect(
        idx.matchesPath(r'C:\Program Files\Acme Corp'),
        isTrue,
      );
    });

    test('returns false for unknown directory', () {
      final idx = InstalledProgramIndex([
        InstalledProgram(displayName: 'Adobe AIR', registryKeyPath: 'k'),
      ]);
      expect(idx.matchesPath(r'C:\Program Files\OrphanCorp'), isFalse);
    });

    test('matches by publisher key', () {
      final idx = InstalledProgramIndex([
        InstalledProgram(
          displayName: 'Photoshop',
          publisher: 'Adobe',
          registryKeyPath: 'k',
        ),
      ]);
      expect(
        idx.matchesPublisherKey('Adobe'),
        isTrue,
      );
    });
  });
}
