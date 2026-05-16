import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/utils/app_paths.dart';
import '../core/utils/file_size_formatter.dart';
import '../data/scanners/browser_cache_scanner.dart';
import '../data/scanners/dns_cache_scanner.dart';
import '../data/scanners/recycle_bin_scanner.dart';
import '../data/scanners/temp_files_scanner.dart';
import '../data/scanners/thumbnail_cache_scanner.dart';
import '../data/scanners/windows_logs_scanner.dart';
import '../domain/entities/junk_category.dart';
import '../domain/entities/junk_item.dart';
import '../domain/scanners/junk_scanner.dart';

/// 命令行模式入口。返回 `null` 表示这不是 CLI 调用、应继续启动 GUI；
/// 返回非 null 表示已经处理完毕，应以该退出码结束进程。
Future<int?> tryRunCli(List<String> args) async {
  if (args.isEmpty) return null;
  final cmd = args.first;
  if (cmd == '--help' || cmd == '-h' || cmd == 'help') {
    _printHelp(stdout);
    return 0;
  }
  if (cmd == 'scan') {
    return _runScan(args.skip(1).toList());
  }
  if (cmd == 'clean') {
    return _runClean(args.skip(1).toList());
  }
  if (cmd == '--version' || cmd == '-v' || cmd == 'version') {
    stdout.writeln('dustman 0.3.0');
    return 0;
  }
  // 没匹配到任何 CLI 子命令 → 当作 GUI 启动忽略
  return null;
}

void _printHelp(IOSink out) {
  out
    ..writeln('Dustman — Windows disk cleaner')
    ..writeln('')
    ..writeln('Usage:')
    ..writeln('  dustman.exe                        Launch the GUI')
    ..writeln('  dustman.exe scan [options]         Scan junk categories and print result')
    ..writeln('  dustman.exe clean [options]        Scan + delete (move to Recycle Bin)')
    ..writeln('  dustman.exe --help')
    ..writeln('  dustman.exe --version')
    ..writeln('')
    ..writeln('Scan/clean options:')
    ..writeln('  --json                  Emit JSON to stdout (default: text)')
    ..writeln('  --category=<id,…>       Restrict to comma-separated categories.')
    ..writeln('                          Available: temp, browser-cache, windows-logs,')
    ..writeln('                                     thumbnail-cache, recycle-bin, dns-cache')
    ..writeln('  --yes                   (clean only) skip the confirmation prompt')
    ..writeln('')
    ..writeln('Examples:')
    ..writeln('  dustman.exe scan --json')
    ..writeln('  dustman.exe scan --category=temp,browser-cache')
    ..writeln('  dustman.exe clean --category=temp --yes');
}

const _allScanners = <String, JunkScanner Function()>{
  'temp': TempFilesScanner.new,
  'browser-cache': BrowserCacheScanner.new,
  'windows-logs': WindowsLogsScanner.new,
  'thumbnail-cache': ThumbnailCacheScanner.new,
  'recycle-bin': RecycleBinScanner.new,
  'dns-cache': DnsCacheScanner.new,
};

Future<int> _runScan(List<String> args) async {
  final opt = _parseOptions(args);
  if (opt == null) return 64;
  final scanners = _resolveScanners(opt.categories);
  final results = await _scan(scanners);
  if (opt.json) {
    stdout.writeln(_jsonScanReport(results));
  } else {
    _printText(results);
  }
  return 0;
}

Future<int> _runClean(List<String> args) async {
  final opt = _parseOptions(args);
  if (opt == null) return 64;
  final scanners = _resolveScanners(opt.categories);
  final results = await _scan(scanners);

  if (!opt.yes) {
    final totalBytes =
        results.values.fold<int>(0, (s, list) => s + list.fold<int>(0, (t, it) => t + it.size));
    stdout.writeln(
      'Will move ${results.values.fold<int>(0, (s, l) => s + l.length)} item(s) '
      '/ ${FileSizeFormatter.format(totalBytes)} to the Recycle Bin.',
    );
    stdout.write('Proceed? [y/N] ');
    final line = stdin.readLineSync()?.trim().toLowerCase();
    if (line != 'y' && line != 'yes') {
      stdout.writeln('Aborted.');
      return 1;
    }
  }

  final cleanReports = <String, Map<String, dynamic>>{};
  for (final entry in results.entries) {
    if (entry.value.isEmpty) continue;
    final scanner = scanners.firstWhere((s) => _idFor(s.type) == entry.key);
    final report = await scanner.clean(entry.value);
    cleanReports[entry.key] = {
      'itemsDeleted': report.itemsDeleted,
      'bytesFreed': report.bytesFreed,
      'failures': [
        for (final f in report.failures)
          {'path': f.path, 'reason': f.reason},
      ],
    };
  }
  if (opt.json) {
    stdout.writeln(json.encode({
      'mode': 'clean',
      'portable': AppPaths.isPortable,
      'dataDir': AppPaths.dataDir,
      'results': cleanReports,
    }));
  } else {
    var freed = 0;
    var deleted = 0;
    cleanReports.forEach((id, r) {
      stdout.writeln(
        '  $id: ${r['itemsDeleted']} item(s), '
        '${FileSizeFormatter.format(r['bytesFreed'] as int)} freed, '
        '${(r['failures'] as List).length} failure(s)',
      );
      freed += r['bytesFreed'] as int;
      deleted += r['itemsDeleted'] as int;
    });
    stdout.writeln('---');
    stdout.writeln('Total: $deleted items, ${FileSizeFormatter.format(freed)} freed.');
  }
  return 0;
}

Future<Map<String, List<JunkItem>>> _scan(List<JunkScanner> scanners) async {
  final out = <String, List<JunkItem>>{};
  for (final s in scanners) {
    final id = _idFor(s.type);
    final items = <JunkItem>[];
    try {
      await for (final it in s.scan()) {
        items.add(it);
      }
    } on Object catch (e) {
      stderr.writeln('[warn] $id scan failed: $e');
    }
    out[id] = items;
  }
  return out;
}

String _jsonScanReport(Map<String, List<JunkItem>> results) {
  final byCategory = <String, Map<String, dynamic>>{};
  var totalBytes = 0;
  var totalItems = 0;
  results.forEach((id, items) {
    final bytes = items.fold<int>(0, (s, it) => s + it.size);
    totalBytes += bytes;
    totalItems += items.length;
    byCategory[id] = {
      'items': items.length,
      'bytes': bytes,
      'humanSize': FileSizeFormatter.format(bytes),
      'samples': [
        for (final it in items.take(20))
          {
            'path': it.path,
            'size': it.size,
            'isDirectory': it.isDirectory,
            'isVirtual': it.isVirtual,
            if (it.note != null) 'note': it.note,
          },
      ],
    };
  });
  return json.encode({
    'mode': 'scan',
    'portable': AppPaths.isPortable,
    'dataDir': AppPaths.dataDir,
    'total': {
      'items': totalItems,
      'bytes': totalBytes,
      'humanSize': FileSizeFormatter.format(totalBytes),
    },
    'categories': byCategory,
  });
}

void _printText(Map<String, List<JunkItem>> results) {
  var totalBytes = 0;
  var totalItems = 0;
  results.forEach((id, items) {
    final bytes = items.fold<int>(0, (s, it) => s + it.size);
    totalBytes += bytes;
    totalItems += items.length;
    stdout.writeln(
      '  $id: ${items.length} item(s), ${FileSizeFormatter.format(bytes)}',
    );
  });
  stdout.writeln('---');
  stdout.writeln(
    'Total: $totalItems items, ${FileSizeFormatter.format(totalBytes)} reclaimable.',
  );
}

String _idFor(JunkCategoryType type) => switch (type) {
      JunkCategoryType.tempFiles => 'temp',
      JunkCategoryType.browserCache => 'browser-cache',
      JunkCategoryType.windowsLogs => 'windows-logs',
      JunkCategoryType.thumbnailCache => 'thumbnail-cache',
      JunkCategoryType.recycleBin => 'recycle-bin',
      JunkCategoryType.dnsCache => 'dns-cache',
    };

List<JunkScanner> _resolveScanners(List<String> ids) {
  if (ids.isEmpty) {
    return [for (final factory in _allScanners.values) factory()];
  }
  final out = <JunkScanner>[];
  for (final id in ids) {
    final factory = _allScanners[id];
    if (factory == null) {
      stderr.writeln('[warn] unknown category: $id');
      continue;
    }
    out.add(factory());
  }
  return out;
}

class _CliOptions {
  _CliOptions({
    required this.json,
    required this.categories,
    required this.yes,
  });
  final bool json;
  final List<String> categories;
  final bool yes;
}

_CliOptions? _parseOptions(List<String> args) {
  var jsonOut = false;
  var yes = false;
  final categories = <String>[];
  for (final a in args) {
    if (a == '--json') {
      jsonOut = true;
    } else if (a == '--yes' || a == '-y') {
      yes = true;
    } else if (a.startsWith('--category=')) {
      final v = a.substring('--category='.length);
      for (final id in v.split(',')) {
        final t = id.trim();
        if (t.isNotEmpty) categories.add(t);
      }
    } else {
      stderr.writeln('Unknown option: $a');
      _printHelp(stderr);
      return null;
    }
  }
  return _CliOptions(json: jsonOut, categories: categories, yes: yes);
}
