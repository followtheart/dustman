import 'dart:io';

import 'package:dustman/data/scanners/filesystem_residue_scanner.dart';
import 'package:dustman/domain/entities/installed_program.dart';
import 'package:dustman/domain/entities/residue_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FilesystemResidueScanner', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dustman_fs_residue_');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('detects empty orphan dir as high-confidence', () async {
      final orphan = Directory(p.join(tmp.path, 'OrphanCorp'));
      await orphan.create();

      final scanner = FilesystemResidueScanner(roots: [tmp.path]);
      final index = InstalledProgramIndex(const []);
      final items = await scanner.scan(index).toList();

      expect(items, hasLength(1));
      expect(items.first.name, 'OrphanCorp');
      expect(items.first.confidence, ResidueConfidence.high);
      expect(items.first.kind, ResidueKind.fileDir);
      expect(items.first.size, 0);
    });

    test('skips whitelisted dirs', () async {
      await Directory(p.join(tmp.path, 'Common Files')).create();
      await Directory(p.join(tmp.path, 'Microsoft')).create();
      await Directory(p.join(tmp.path, 'OrphanCorp')).create();

      final scanner = FilesystemResidueScanner(roots: [tmp.path]);
      final items =
          await scanner.scan(InstalledProgramIndex(const [])).toList();
      expect(items.map((i) => i.name), ['OrphanCorp']);
    });

    test('skips dir that matches an installed program by name', () async {
      await Directory(p.join(tmp.path, 'Adobe AIR')).create();
      await Directory(p.join(tmp.path, 'OtherCorp')).create();

      final index = InstalledProgramIndex([
        InstalledProgram(
          displayName: 'Adobe AIR',
          registryKeyPath: 'k',
        ),
      ]);

      final scanner = FilesystemResidueScanner(roots: [tmp.path]);
      final items = await scanner.scan(index).toList();
      expect(items.map((i) => i.name), ['OtherCorp']);
    });

    test('classifies as low confidence when contains exe', () async {
      final orphan = Directory(p.join(tmp.path, 'BigOrphan'));
      await orphan.create();
      // 写一个 100MB-ish 的 .exe（实际写小一点，配合大小阈值另外的逻辑）
      final exe = File(p.join(orphan.path, 'binary.exe'));
      await exe.writeAsBytes(List.filled(60 * 1024 * 1024, 0));

      final scanner = FilesystemResidueScanner(roots: [tmp.path]);
      final items =
          await scanner.scan(InstalledProgramIndex(const [])).toList();
      expect(items, hasLength(1));
      expect(items.first.confidence, ResidueConfidence.low);
    });

    test('small dir without exe is high confidence', () async {
      final orphan = Directory(p.join(tmp.path, 'TinyOrphan'));
      await orphan.create();
      final f = File(p.join(orphan.path, 'config.ini'));
      await f.writeAsString('foo=bar');

      final scanner = FilesystemResidueScanner(roots: [tmp.path]);
      final items =
          await scanner.scan(InstalledProgramIndex(const [])).toList();
      expect(items, hasLength(1));
      expect(items.first.confidence, ResidueConfidence.high);
    });

    test('emits no items for nonexistent root', () async {
      final scanner = FilesystemResidueScanner(
        roots: [p.join(tmp.path, 'does-not-exist')],
      );
      final items =
          await scanner.scan(InstalledProgramIndex(const [])).toList();
      expect(items, isEmpty);
    });
  });
}
