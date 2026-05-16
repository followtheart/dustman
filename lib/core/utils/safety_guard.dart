import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import 'logger.dart';

/// 删除前的最后一道守门人。所有 Scanner 在执行 `File.delete` 前必须经过 `isSafeToDelete`。
class SafetyGuard {
  SafetyGuard._();

  static bool isSafeToDelete(String absolutePath) {
    final normalized = p.normalize(absolutePath).toLowerCase();

    for (final seg in AppConstants.protectedPathSegments) {
      if (normalized.contains(seg)) {
        AppLogger.warn(
          'blocked by protected segment "$seg": $absolutePath',
          tag: 'SafetyGuard',
        );
        return false;
      }
    }

    final home = Platform.environment['USERPROFILE'];
    if (home != null) {
      final lowerHome = home.toLowerCase();
      for (final sub in AppConstants.userProtectedSubdirs) {
        final guarded = p.join(lowerHome, sub.toLowerCase());
        if (normalized == guarded || p.isWithin(guarded, normalized)) {
          AppLogger.warn(
            'blocked by user-protected dir "$sub": $absolutePath',
            tag: 'SafetyGuard',
          );
          return false;
        }
      }
    }
    return true;
  }
}
