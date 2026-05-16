import 'dart:developer' as developer;

enum LogLevel { debug, info, warn, error }

class AppLogger {
  AppLogger._();

  static LogLevel minLevel = LogLevel.info;

  static void debug(String msg, {String? tag}) =>
      _log(LogLevel.debug, msg, tag: tag);
  static void info(String msg, {String? tag}) =>
      _log(LogLevel.info, msg, tag: tag);
  static void warn(String msg, {String? tag}) =>
      _log(LogLevel.warn, msg, tag: tag);
  static void error(String msg, {Object? error, StackTrace? stack, String? tag}) =>
      _log(LogLevel.error, msg, error: error, stack: stack, tag: tag);

  static void _log(
    LogLevel level,
    String msg, {
    String? tag,
    Object? error,
    StackTrace? stack,
  }) {
    if (level.index < minLevel.index) return;
    developer.log(
      msg,
      name: tag ?? 'dustman',
      level: _levelValue(level),
      error: error,
      stackTrace: stack,
    );
  }

  static int _levelValue(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      };
}
