import 'package:flutter/material.dart';

enum JunkCategoryType {
  tempFiles,
  browserCache,
  windowsLogs,
  thumbnailCache,
  recycleBin,
  dnsCache,
}

extension JunkCategoryTypeUi on JunkCategoryType {
  String get displayName => switch (this) {
        JunkCategoryType.tempFiles => '临时文件',
        JunkCategoryType.browserCache => '浏览器缓存',
        JunkCategoryType.windowsLogs => '系统日志与崩溃转储',
        JunkCategoryType.thumbnailCache => '缩略图缓存',
        JunkCategoryType.recycleBin => '回收站',
        JunkCategoryType.dnsCache => 'DNS 缓存',
      };

  String get description => switch (this) {
        JunkCategoryType.tempFiles =>
          '应用与系统在 %TEMP% 和 Windows\\Temp 留下的临时文件，绝大多数可安全删除。',
        JunkCategoryType.browserCache =>
          'Chrome / Edge / Firefox 的离线缓存。清理后首次访问网站会稍慢，登录态不受影响。',
        JunkCategoryType.windowsLogs =>
          'Windows 日志、setup 日志、内存崩溃转储（*.dmp）。一般非开发者无需保留。',
        JunkCategoryType.thumbnailCache =>
          '资源管理器为图片/视频生成的缩略图数据库，删除后会自动重建。',
        JunkCategoryType.recycleBin =>
          '系统回收站。清空后文件不可通过常规方式恢复。',
        JunkCategoryType.dnsCache =>
          '解析过的域名缓存。清空可解决偶发的"域名解析错误"问题。',
      };

  IconData get icon => switch (this) {
        JunkCategoryType.tempFiles => Icons.folder_zip_outlined,
        JunkCategoryType.browserCache => Icons.public_outlined,
        JunkCategoryType.windowsLogs => Icons.description_outlined,
        JunkCategoryType.thumbnailCache => Icons.image_outlined,
        JunkCategoryType.recycleBin => Icons.delete_outline,
        JunkCategoryType.dnsCache => Icons.dns_outlined,
      };
}
