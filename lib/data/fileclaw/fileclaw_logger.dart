import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/app_paths.dart';
import '../../core/utils/logger.dart';

/// FileClaw 专用审计日志。
///
/// 每行一条 JSON，便于追溯：哪些 AI 会话调用了哪些工具、参数是什么、
/// 用户是否同意写工具、最终结果。文件按日切割：
///   `<AppData>\Dustman\logs\fileclaw-YYYY-MM-DD.log`
///   绿色版：`<exe_dir>\data\logs\fileclaw-YYYY-MM-DD.log`
///
/// 写文件失败仅记到主日志，不抛回 AiSession。
class FileClawLogger {
  FileClawLogger._();

  static const _tag = 'FileClaw';

  static void writeEvent(Map<String, Object?> event) {
    try {
      final line = jsonEncode({
        'ts': DateTime.now().toUtc().toIso8601String(),
        ...event,
      });
      final file = File(_currentLogPath());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } on FileSystemException catch (e) {
      AppLogger.warn('fileclaw log write failed: ${e.message}', tag: _tag);
    } on Object catch (e) {
      AppLogger.warn('fileclaw log unexpected: $e', tag: _tag);
    }
  }

  static String _currentLogPath() {
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return p.join(AppPaths.logDir, 'fileclaw-$stamp.log');
  }
}
