# Dustman 架构设计

## 1. 总体分层

采用简化的 Clean Architecture（三层），自上而下单向依赖：

```
┌─────────────────────────────────────────────┐
│  presentation/                              │
│    screens / widgets / providers (ChangeNotifier)
├─────────────────────────────────────────────┤
│  domain/                                    │
│    entities / scanner 抽象接口
├─────────────────────────────────────────────┤
│  data/                                      │
│    scanners 实现 / services / platform 桥接
└─────────────────────────────────────────────┘
```

**依赖方向**：`presentation → domain ← data`。
domain 层不依赖任何具体 IO / Flutter API，便于在纯 Dart 环境中单元测试。

## 2. 目录结构

```
dustman/
├── docs/                       # 设计文档
├── lib/
│   ├── main.dart               # 入口
│   ├── app.dart                # MaterialApp & MultiProvider
│   ├── core/
│   │   ├── constants/          # 常量（应用名、白名单等）
│   │   ├── theme/              # Material 3 主题
│   │   └── utils/              # 格式化、日志
│   ├── domain/
│   │   ├── entities/           # JunkItem / JunkCategory / ScanProgress
│   │   └── scanners/           # JunkScanner 抽象基类
│   ├── data/
│   │   ├── platform/           # Windows 路径常量、Win32 包装
│   │   ├── scanners/           # 6 个具体 Scanner 实现
│   │   └── services/           # CleanerService / RecycleBinService
│   └── presentation/
│       ├── providers/          # ScanProvider / ThemeProvider
│       ├── screens/            # Home / JunkClean / Settings 等
│       └── widgets/            # SidebarNav / CategoryTile 等
├── test/                       # 单元测试
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

> Windows 原生运行时目录 `windows/` 由 `flutter create --platforms=windows .`
> 在首次构建时生成，不纳入仓库初始提交。

## 3. 核心抽象

### 3.1 JunkScanner（domain 层）

所有清理类别共享同一份接口，便于注册表式管理与并行调度：

```dart
abstract class JunkScanner {
  JunkCategoryType get type;              // 分类枚举
  String get displayName;                 // 中文展示名
  String get description;                 // 用途说明（UI 展示）
  bool get requiresElevation;             // 是否需要管理员

  Stream<JunkItem> scan();                // 流式产出扫描结果
  Future<CleanReport> clean(List<JunkItem> items); // 执行清理
}
```

不同实现：
- `TempFilesScanner` — 扫 `%TEMP%`、`C:\Windows\Temp`；
- `BrowserCacheScanner` — Chrome/Edge/Firefox cache 目录；
- `WindowsLogsScanner` — `C:\Windows\Logs`、`*.dmp`、`*.log`；
- `ThumbnailCacheScanner` — `%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db`；
- `RecycleBinScanner` — 调用 Win32 `SHQueryRecycleBin` / `SHEmptyRecycleBin`；
- `DnsCacheScanner` — 通过 `ipconfig /flushdns` 子进程清空。

### 3.2 ScanProvider（presentation 层）

`ChangeNotifier`，聚合所有 Scanner，对外暴露：

- `Map<JunkCategoryType, CategoryState> states`；
- `Future<void> scanAll()` / `scanCategory(type)`；
- `Future<void> cleanSelected()`；
- `int get totalReclaimableBytes`。

UI 通过 `Selector` / `Consumer` 订阅局部状态，避免无关重建。

### 3.3 白名单与安全策略

`SafetyGuard`（在 core/）统一守门：
- 路径必须位于已声明的根目录之下（Temp 目录、缓存目录）；
- 黑名单：`Windows\System32`、`Windows\SysWOW64`、当前用户 `Documents`、`Desktop`；
- 删除前再次 `File.exists()`，避免 TOCTOU；
- 失败计入 `CleanReport.failures` 而非抛异常中断整体流程。

## 4. 状态管理（Provider）

```
MultiProvider
  ├── ChangeNotifierProvider<ThemeProvider>
  └── ChangeNotifierProvider<ScanProvider>
```

`ScanProvider` 内部用 `Map<JunkCategoryType, CategoryState>` 维护状态，
更新单一分类时通过 `notifyListeners()` 触发，UI 端用 `Selector` 精准订阅。

## 5. 并发模型

| 场景 | 实现 |
|---|---|
| 单分类扫描 | `async*` Stream，逐项 yield，UI `StreamBuilder` 增量渲染 |
| 全量扫描 | `Future.wait` 并行多个 Scanner（每个内部本身已是 async） |
| 大目录递归 | `Directory.list()` 异步流，避免内存爆炸 |
| CPU 密集（重复文件 hash，二期） | `Isolate.run` 抛到独立 Isolate |

## 6. Windows 平台集成

通过 [`win32`](https://pub.dev/packages/win32) 包以 FFI 方式直接调用 Windows API，
无需自己写 C++ 插件。涉及的 API：

| 能力 | API |
|---|---|
| 查询回收站大小 | `SHQueryRecycleBinW` |
| 清空回收站 | `SHEmptyRecycleBinW` |
| 移入回收站删除 | `SHFileOperationW` + `FOF_ALLOWUNDO` |
| 已知文件夹路径 | `SHGetKnownFolderPath` |
| 检测管理员权限 | `IsUserAnAdmin` (shell32) |

平台判断：所有 Win32 调用包在 `if (Platform.isWindows)` 守卫内，
非 Windows 平台返回空结果，保证代码可在 Linux CI 上 `dart analyze` 通过。

## 7. 错误处理

- 扫描层：单个文件 stat 失败 → 跳过 + 记日志，不冒泡；
- 清理层：单文件删除失败 → 计入 `CleanReport.failures`，附错误码；
- UI 层：Provider 暴露 `error` 字段，由 `SnackBar` 统一提示。

## 8. 日志

`AppLogger`（core/utils）封装 `developer.log`，并按日切割文件到
`%APPDATA%\Dustman\logs\`。生产构建仅记录 WARN+，DEBUG 仅在 `--dart-define=DEBUG=true` 时启用。

## 9. 测试策略

| 层 | 测试方式 |
|---|---|
| utils / formatter | 纯单元测试（`test/` 目录） |
| Scanner | 使用 `MemoryFileSystem`（package:file） mock，断言扫描产出 |
| Provider | `ChangeNotifier` + fake scanner，验证状态转移 |
| Widget | `flutter_test` golden test（二期） |

## 10. 构建与分发

- 开发：`flutter run -d windows`；
- 发布：`flutter build windows --release`，产物在 `build\windows\x64\runner\Release\`；
- 打包：使用 [`msix`](https://pub.dev/packages/msix) 生成 MSIX 安装包，
  或直接 zip 整个 Release 目录作为绿色版。
