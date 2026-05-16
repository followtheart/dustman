import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'cli/cli_runner.dart';
import 'core/utils/app_paths.dart';

Future<void> main(List<String> args) async {
  // 触发数据目录初始化（决定后续偏好 / 日志的写入位置）。
  // 在 CLI 与 GUI 路径上都需要。
  AppPaths.dataDir;

  // CLI 模式：识别到子命令则直接处理并退出，绝不弹窗。
  final cliExit = await tryRunCli(args);
  if (cliExit != null) {
    exit(cliExit);
  }

  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Dustman',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const DustmanApp());
}
