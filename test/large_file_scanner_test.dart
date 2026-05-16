import 'dart:io';

import 'package:dustman/data/scanners/large_file_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LargeFileScanner', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dustman_large_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('returns only files larger than minBytes', () async {
      final small = File(p.join(tmp.path, 'small.txt'))
        ..writeAsBytesSync(List.filled(100, 0));
      final big = File(p.join(tmp.path, 'big.bin'))
        ..writeAsBytesSync(List.filled(2048, 0));

      final scanner = const LargeFileScanner(minBytes: 1024);
      final items = await scanner.scan(tmp.path).toList();

      expect(items.length, 1);
      expect(items.first.path, big.path);
      expect(items.first.size, 2048);
      expect(items.first.extension, '.bin');
      // touch to avoid lint unused
      expect(small.existsSync(), true);
    });

    test('filters by extension when provided', () async {
      File(p.join(tmp.path, 'a.iso'))..writeAsBytesSync(List.filled(2048, 0));
      File(p.join(tmp.path, 'b.zip'))..writeAsBytesSync(List.filled(2048, 0));
      File(p.join(tmp.path, 'c.bin'))..writeAsBytesSync(List.filled(2048, 0));

      final scanner = const LargeFileScanner(
        minBytes: 1024,
        extensions: {'.iso', '.zip'},
      );
      final items = await scanner.scan(tmp.path).toList();
      final names = items.map((e) => p.basename(e.path)).toSet();
      expect(names, {'a.iso', 'b.zip'});
    });

    test('returns empty for nonexistent root', () async {
      final scanner = const LargeFileScanner(minBytes: 0);
      final items =
          await scanner.scan(p.join(tmp.path, 'nope')).toList();
      expect(items, isEmpty);
    });
  });
}
