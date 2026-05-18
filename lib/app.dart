import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/edition.dart';
import 'core/i18n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'data/fileclaw/auth_repository.dart';
import 'data/fileclaw/auth_store.dart';
import 'data/fileclaw/cloud_client.dart';
import 'data/fileclaw/tool_runtime/regmcp_tools.dart';
import 'data/scanners/browser_cache_scanner.dart';
import 'data/scanners/dead_shortcut_scanner.dart';
import 'data/scanners/dns_cache_scanner.dart';
import 'data/scanners/filesystem_residue_scanner.dart';
import 'data/scanners/recycle_bin_scanner.dart';
import 'data/scanners/registry_residue_scanner.dart';
import 'data/scanners/temp_files_scanner.dart';
import 'data/scanners/thumbnail_cache_scanner.dart';
import 'data/scanners/windows_logs_scanner.dart';
import 'domain/scanners/junk_scanner.dart';
import 'domain/scanners/residue_scanner.dart';
import 'presentation/providers/ai_provider.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/billing_provider.dart';
import 'presentation/providers/disk_treemap_provider.dart';
import 'presentation/providers/duplicate_provider.dart';
import 'presentation/providers/installed_programs_provider.dart';
import 'presentation/providers/large_file_provider.dart';
import 'presentation/providers/locale_provider.dart';
import 'presentation/providers/residue_provider.dart';
import 'presentation/providers/scan_provider.dart';
import 'presentation/providers/schedule_provider.dart';
import 'presentation/providers/startup_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/screens/home_screen.dart';

/// FileClaw 云侧基础 URL。
/// TODO(v0.4): 后续改成由设置页 / `--dart-define=DUSTMAN_CLOUD_URL=...` 控制。
const String _kFileClawBaseUrl = String.fromEnvironment(
  'DUSTMAN_CLOUD_URL',
  defaultValue: 'http://localhost:8000',
);

class DustmanApp extends StatelessWidget {
  const DustmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scanners = <JunkScanner>[
      TempFilesScanner(),
      BrowserCacheScanner(),
      WindowsLogsScanner(),
      ThumbnailCacheScanner(),
      RecycleBinScanner(),
      DnsCacheScanner(),
    ];

    final residueScanners = <ResidueScanner>[
      FilesystemResidueScanner(),
      RegistryResidueScanner(),
      DeadShortcutScanner(),
    ];

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()..load()),
        ChangeNotifierProvider(create: (_) => ScanProvider(scanners)),
        ChangeNotifierProvider(
          create: (_) => ResidueProvider(scanners: residueScanners),
        ),
        ChangeNotifierProvider(create: (_) => LargeFileProvider()),
        ChangeNotifierProvider(create: (_) => DuplicateProvider()),
        ChangeNotifierProvider(create: (_) => StartupProvider()),
        ChangeNotifierProvider(create: (_) => DiskTreemapProvider()),
        ChangeNotifierProvider(create: (_) => InstalledProgramsProvider()),
        // 仅 Pro 版装配 FileClaw 相关 Provider。kIsPro 是编译期常量，
        // Community 构建会被 Dart AOT 树摇剔除整个 if 分支。
        if (kIsPro) ..._proProviders(),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return LocalizationScope(
            localeCode: localeProvider.effective,
            child: MaterialApp(
              title: 'Dustman',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: themeProvider.themeMode,
              locale: localeProvider.materialLocale,
              home: const HomeScreen(),
            ),
          );
        },
      ),
    );
  }

  /// 仅 Pro 构建调用。装配 FileClaw 所有 Provider，并把 regmcp 工具注册到全局表。
  List<ChangeNotifierProvider> _proProviders() {
    final client = CloudClient(baseUrl: _kFileClawBaseUrl);
    final store = AuthStore();
    final repo = AuthRepository(client: client, store: store);
    final authProvider = AuthProvider(repo)..bootstrap();

    // 注册端侧只读工具。重复调用幂等。
    registerRegMcpTools();

    return [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<AiProvider>(
        create: (_) => AiProvider(
          baseUrl: _kFileClawBaseUrl,
          // 复用 CloudClient 持有的 accessToken（同一进程内）
          accessTokenProvider: () => client.currentAccessToken ?? '',
        ),
      ),
      ChangeNotifierProvider<BillingProvider>(
        create: (_) => BillingProvider(client),
      ),
    ];
  }
}
