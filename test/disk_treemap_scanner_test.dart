import 'dart:io';

import 'package:dustman/data/scanners/disk_treemap_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DiskTreemapScanner', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dustman_treemap_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('aggregates sizes recursively', () async {
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      File(p.join(tmp.path, 'a.bin')).writeAsBytesSync(List.filled(100, 0));
      File(p.join(sub.path, 'b.bin')).writeAsBytesSync(List.filled(200, 0));
      File(p.join(sub.path, 'c.bin')).writeAsBytesSync(List.filled(50, 0));

      final node = await DiskTreemapScanner().scan(tmp.path);
      expect(node, isNotNull);
      expect(node!.isDirectory, isTrue);
      expect(node.size, 350);

      // 找到 sub 子节点
      final subNode = node.children!.firstWhere((c) => c.name == 'sub');
      expect(subNode.size, 250);
      expect(subNode.isDirectory, isTrue);
      expect(subNode.children!.length, 2);

      // 检查 children 已按 size 降序
      for (var i = 1; i < node.children!.length; i++) {
        expect(
          node.children![i - 1].size >= node.children![i].size,
          isTrue,
        );
      }
    });

    test('returns null for nonexistent root', () async {
      final node = await DiskTreemapScanner().scan(p.join(tmp.path, 'nope'));
      expect(node, isNull);
    });

    test('respects maxDepth (still aggregates size, omits children)', () async {
      final a = Directory(p.join(tmp.path, 'a'))..createSync();
      final b = Directory(p.join(a.path, 'b'))..createSync();
      File(p.join(b.path, 'leaf.bin')).writeAsBytesSync(List.filled(123, 0));

      final node = await DiskTreemapScanner(maxDepth: 1).scan(tmp.path);
      expect(node!.size, 123);
      final aNode = node.children!.firstWhere((c) => c.name == 'a');
      // 在 depth 1，'a' 已经超出 maxDepth，children should be null
      expect(aNode.children, isNull);
      expect(aNode.size, 123);
    });
  });
}
