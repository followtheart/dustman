import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/scanners/browser_cache_scanner.dart';
import 'data/scanners/dns_cache_scanner.dart';
import 'data/scanners/recycle_bin_scanner.dart';
import 'data/scanners/temp_files_scanner.dart';
import 'data/scanners/thumbnail_cache_scanner.dart';
import 'data/scanners/windows_logs_scanner.dart';
import 'presentation/providers/scan_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/home_screen.dart';

class DustmanApp extends StatelessWidget {
  const DustmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scanners = [
      TempFilesScanner(),
      BrowserCacheScanner(),
      WindowsLogsScanner(),
      ThumbnailCacheScanner(),
      RecycleBinScanner(),
      DnsCacheScanner(),
    ];

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
        ChangeNotifierProvider(create: (_) => ScanProvider(scanners)),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Dustman',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeProvider.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
