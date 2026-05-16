import 'package:dustman/data/platform/installed_programs.dart';
import 'package:dustman/domain/entities/installed_program.dart';
import 'package:dustman/domain/entities/junk_item.dart';
import 'package:dustman/domain/entities/residue_item.dart';
import 'package:dustman/domain/scanners/residue_scanner.dart';
import 'package:dustman/presentation/providers/residue_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScanner implements ResidueScanner {
  _FakeScanner(this.kind, this._items);

  @override
  final ResidueKind kind;
  final List<ResidueItem> _items;

  @override
  Stream<ResidueItem> scan(InstalledProgramIndex index) async* {
    for (final it in _items) {
      yield it;
    }
  }
}

class _EmptyRepo extends InstalledProgramsRepository {
  @override
  Future<InstalledProgramIndex> build() async =>
      InstalledProgramIndex(const []);
}

ResidueItem _fakeItem(
  String id, {
  ResidueKind kind = ResidueKind.fileDir,
  ResidueConfidence conf = ResidueConfidence.high,
  int size = 1024,
}) =>
    ResidueItem(
      id: id,
      name: id,
      path: id,
      size: size,
      kind: kind,
      confidence: conf,
      reason: 'fake',
    );

void main() {
  group('ResidueProvider', () {
    test('state transitions: idle → scanning → scanned', () async {
      final provider = ResidueProvider(
        scanners: [
          _FakeScanner(
            ResidueKind.fileDir,
            [_fakeItem('a'), _fakeItem('b')],
          ),
        ],
        installedRepository: _EmptyRepo(),
        cleaner: (_) async => ResidueCleanReport.empty(),
      );
      expect(provider.status, ResidueStatus.idle);
      final f = provider.scan();
      expect(provider.status, ResidueStatus.scanning);
      await f;
      expect(provider.status, ResidueStatus.scanned);
      expect(provider.totalCandidates, 2);
    });

    test('high-confidence items are selected by default', () async {
      final provider = ResidueProvider(
        scanners: [
          _FakeScanner(ResidueKind.fileDir, [
            _fakeItem('high', conf: ResidueConfidence.high),
            _fakeItem('low', conf: ResidueConfidence.low),
          ]),
        ],
        installedRepository: _EmptyRepo(),
        cleaner: (_) async => ResidueCleanReport.empty(),
      );
      await provider.scan();
      expect(provider.isSelected('high'), isTrue);
      expect(provider.isSelected('low'), isFalse);
      expect(provider.selectedCount, 1);
    });

    test('toggleAll for one kind only', () async {
      final provider = ResidueProvider(
        scanners: [
          _FakeScanner(ResidueKind.fileDir, [
            _fakeItem('fs-1', conf: ResidueConfidence.low),
            _fakeItem('fs-2', conf: ResidueConfidence.low),
          ]),
          _FakeScanner(ResidueKind.registryKey, [
            _fakeItem('reg-1', kind: ResidueKind.registryKey,
                conf: ResidueConfidence.low),
          ]),
        ],
        installedRepository: _EmptyRepo(),
        cleaner: (_) async => ResidueCleanReport.empty(),
      );
      await provider.scan();
      provider.toggleAll(ResidueKind.fileDir, true);
      expect(provider.isSelected('fs-1'), isTrue);
      expect(provider.isSelected('fs-2'), isTrue);
      expect(provider.isSelected('reg-1'), isFalse);
    });

    test('cleanSelected delegates to cleaner and removes successful items',
        () async {
      var captured = <ResidueItem>[];
      final provider = ResidueProvider(
        scanners: [
          _FakeScanner(ResidueKind.fileDir, [
            _fakeItem('ok', size: 100),
            _fakeItem('fail', size: 200),
          ]),
        ],
        installedRepository: _EmptyRepo(),
        cleaner: (items) async {
          captured = items;
          return ResidueCleanReport(
            bytesFreed: 100,
            itemsDeleted: 1,
            failures: [CleanFailure('fail', 'permission denied')],
          );
        },
      );
      await provider.scan();
      // 强行勾选 fail（默认它已是 high → 已勾选）
      provider.toggleItem('fail', true);
      await provider.cleanSelected();

      expect(captured.map((it) => it.id), unorderedEquals(['ok', 'fail']));
      expect(provider.status, ResidueStatus.reported);
      expect(provider.lastReport!.bytesFreed, 100);
      // 'ok' 应已删除，'fail' 因失败保留
      final remaining =
          provider.itemsByKind[ResidueKind.fileDir]!.map((it) => it.id);
      expect(remaining, ['fail']);
    });

    test('removeItem drops the entry and its selection', () async {
      final provider = ResidueProvider(
        scanners: [
          _FakeScanner(ResidueKind.fileDir, [_fakeItem('x')]),
        ],
        installedRepository: _EmptyRepo(),
        cleaner: (_) async => ResidueCleanReport.empty(),
      );
      await provider.scan();
      expect(provider.itemsByKind[ResidueKind.fileDir]!, hasLength(1));
      provider.removeItem('x');
      expect(provider.itemsByKind[ResidueKind.fileDir]!, isEmpty);
      expect(provider.isSelected('x'), isFalse);
    });
  });
}
