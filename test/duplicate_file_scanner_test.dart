import 'dart:io';

import 'package:dustman/data/scanners/duplicate_file_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DuplicateFileScanner', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dustman_dup_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('groups files with identical content', () async {
      final payload = List<int>.filled(2048, 7);
      File(p.join(tmp.path, 'a.bin')).writeAsBytesSync(payload);
      File(p.join(tmp.path, 'b.bin')).writeAsBytesSync(payload);
      // 不同内容相同长度 → SHA1 区分开
      final other = List<int>.filled(2048, 3);
      File(p.join(tmp.path, 'c.bin')).writeAsBytesSync(other);

      final scanner = const DuplicateFileScanner(minBytes: 1024);
      final groups = await scanner.scan([tmp.path]).toList();

      expect(groups.length, 1);
      expect(groups.first.count, 2);
      expect(groups.first.size, 2048);
      expect(
        groups.first.paths.map((e) => p.basename(e)).toSet(),
        {'a.bin', 'b.bin'},
      );
    });

    test('ignores files smaller than minBytes', () async {
      File(p.join(tmp.path, 'a.txt')).writeAsBytesSync(List.filled(10, 1));
      File(p.join(tmp.path, 'b.txt')).writeAsBytesSync(List.filled(10, 1));

      final scanner = const DuplicateFileScanner(minBytes: 1024);
      final groups = await scanner.scan([tmp.path]).toList();
      expect(groups, isEmpty);
    });

    test('handles unique sizes without hashing', () async {
      File(p.join(tmp.path, 'a.bin')).writeAsBytesSync(List.filled(2048, 1));
      File(p.join(tmp.path, 'b.bin')).writeAsBytesSync(List.filled(4096, 1));

      final scanner = const DuplicateFileScanner(minBytes: 1024);
      final groups = await scanner.scan([tmp.path]).toList();
      expect(groups, isEmpty);
    });

    test('reports progress callbacks', () async {
      final payload = List<int>.filled(2048, 5);
      File(p.join(tmp.path, 'a.bin')).writeAsBytesSync(payload);
      File(p.join(tmp.path, 'b.bin')).writeAsBytesSync(payload);

      final progresses = <int>[];
      final scanner = const DuplicateFileScanner(minBytes: 1024);
      await scanner
          .scan([tmp.path], onProgress: (p) => progresses.add(p.filesIndexed))
          .toList();
      expect(progresses, isNotEmpty);
      expect(progresses.last, greaterThanOrEqualTo(2));
    });
  });
}
