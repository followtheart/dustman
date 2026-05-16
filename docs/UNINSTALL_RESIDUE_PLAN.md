# 卸载残留清理 — 功能设计

> 对应 [REQUIREMENTS.md §3.2](REQUIREMENTS.md) v0.2 第一项「卸载残留扫描」。
> 替换 `lib/presentation/screens/home_screen.dart` 中第二个 `PlaceholderScreen`。
> 配套架构原则沿用 [ARCHITECTURE.md](ARCHITECTURE.md) 的三层分层与 `JunkScanner` 抽象。

---

## 1. 问题描述

Windows 程序卸载后，常见残留来源：

| 类型 | 位置 | 典型表现 |
|---|---|---|
| 安装目录碎片 | `Program Files\*`、`Program Files (x86)\*` | 空目录或仅剩 `uninst.dat`、`Log.txt` |
| 用户配置 / 缓存 | `%APPDATA%\<厂商>`、`%LOCALAPPDATA%\<厂商>`、`%PROGRAMDATA%\<厂商>` | 卸载器默认保留以便重装时还原 |
| 注册表条目 | `HKLM\SOFTWARE\<Publisher>`、`HKCU\SOFTWARE\<Publisher>` | 卸载脚本疏漏 |
| 开始菜单失效快捷方式 | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\*.lnk` | 目标不存在 |
| Installer 缓存 | `C:\Windows\Installer\$PatchCache$` | MSI 安装包缓存碎片（本期不动） |

这些残留**普通垃圾扫描不会涉及**（它们不在 Temp / Cache 下），但日积月累动辄数 GB。
难点在于：判断"哪些是孤儿"远比"哪些是临时文件"更主观，**误删代价高**（用户配置 / 游戏存档）。

## 2. 设计目标与非目标

### 2.1 目标
- 列出当前系统**已卸载但仍有残留**的程序候选；
- 每条候选附带**信心分级**与**证据链**（为什么判定为残留），用户可决策；
- 删除走**回收站**，注册表项删除前**自动导出 .reg 备份**；
- 扫描总耗时 < 3 秒（SSD）/ < 8 秒（HDD）。

### 2.2 非目标（本期不做）
- 自动卸载已安装程序（交给 Windows "应用与功能"）；
- 注册表"瘦身/优化"（无技术依据，与项目 §5 噱头功能边界冲突）；
- 浏览器扩展、计划任务、服务 (`services.msc`) 的残留；
- 跨用户 profile (`C:\Users\<other>`) 扫描。

## 3. 数据来源

### 3.1 已安装程序集合（基准）

枚举三处注册表 Uninstall 列表，合并去重：

| 路径 | 视图 | 范围 |
|---|---|---|
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` | 64-bit | 全机 64 位 |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` | 32-bit (`KEY_WOW64_32KEY`) | 全机 32 位 |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` | 默认 | 当前用户 |

每项关注字段：`DisplayName`、`Publisher`、`InstallLocation`、`UninstallString`、`SystemComponent`（=1 时排除）、`ParentKeyName`（非空时为补丁，排除）。

### 3.2 残留候选源

| Scanner | 扫描范围 | 仅扫一级目录 |
|---|---|---|
| `FilesystemResidueScanner` | `Program Files`、`Program Files (x86)`、`%APPDATA%`、`%LOCALAPPDATA%`、`%PROGRAMDATA%` | 是 |
| `RegistryResidueScanner` | `HKLM\SOFTWARE\*`、`HKCU\SOFTWARE\*`（两个视图） | 是 |
| `DeadShortcutScanner` | `%APPDATA%\...\Start Menu\Programs`、`%PROGRAMDATA%\...\Start Menu\Programs` | 否（递归 .lnk） |

只扫一级是关键控量手段：避免把单个程序的几千个子文件全部列成残留。

## 4. 核心算法：孤儿判定

### 4.1 文件系统候选 → 残留

对每个一级子目录 `D`：

1. **白名单过滤**（直接跳过）：
   `Common Files`、`Internet Explorer`、`Windows Defender`、`Microsoft`、`WindowsApps`、`ModifiableWindowsApps`、`Mozilla`（如未卸载 Firefox）、`Google`（同 Chrome）等系统/活跃厂商目录。
2. **匹配已安装程序**（命中则非残留）：
   - `InstallLocation` ⊇ `D` 或 `D` ⊇ `InstallLocation`；
   - `DisplayName` 或 `Publisher` 模糊匹配 `basename(D)`（去空格、去标点、忽略大小写）。
3. **未命中 → 候选残留**，再按下表算信心：

| 信心 | 触发条件 | 默认勾选 |
|---|---|---|
| **high** | 空目录，或目录大小 < 256 KB 且无 `.exe`/`.dll` | ✓ |
| **medium** | 1MB ≤ 大小 < 50MB，含少量 dll/data，最后修改 > 90 天 | ✗ |
| **low** | 其它（含可执行、大体积、近期修改） | ✗（仅展示） |

### 4.2 注册表候选 → 残留

对 `HKLM\SOFTWARE\*` 与 `HKCU\SOFTWARE\*` 的一级 Publisher 键 `P`：

1. **黑名单守门**（永不删除）：
   `Microsoft`、`Windows`、`Classes`、`Clients`、`RegisteredApplications`、`Policies`、`Intel`、`AMD`、`NVIDIA`、`Realtek`、`Khronos`、`ODBC`、`Wow6432Node` 自身等。
2. **匹配已安装程序**：任何已安装程序的 `Publisher` 模糊命中 `P`。
3. **未命中且子键总数 ≤ 16、值总数 ≤ 64** → 候选残留；
4. 信心：
   - **high**：Publisher 键下所有产品键的 `(LastWriteTime)` 都 > 1 年；
   - **medium**：6 个月以内，或子键数较多；
   - **low**：含可疑共享字符串（路径、CLSID）。

注：注册表"LastWriteTime"通过 `RegQueryInfoKeyW` 取得，比文件 mtime 更可靠。

### 4.3 失效快捷方式

对每个 `.lnk`：

1. 用 `IShellLinkW` + `IPersistFileW`（win32 包）解析目标 `Target`、`Arguments`、`WorkingDirectory`；
2. `Target` 是绝对路径且 `!File.exists(Target)`（且非 UNC、非 MSI advertised shortcut）→ 高信心残留；
3. 默认勾选。

## 5. 数据模型

新增 `lib/domain/entities/`：

```dart
class InstalledProgram {
  final String displayName;
  final String? publisher;
  final String? installLocation;   // 已规范化的绝对路径
  final String registryKeyPath;    // 来源键，便于追溯
  final bool systemComponent;
  // 模糊匹配键（小写、去标点）
  String get matchKey;
}

enum ResidueKind { fileDir, registryKey, deadShortcut }
enum ResidueConfidence { high, medium, low }

class ResidueItem {
  final String name;
  final String path;                   // 文件路径 / 注册表完整路径 / .lnk 路径
  final int size;                      // 字节，注册表项按估算字节计
  final ResidueKind kind;
  final ResidueConfidence confidence;
  final String reason;                 // 一句话总结
  final List<String> evidence;         // 详细证据（展开面板用）
  final DateTime? lastModified;
}

class ResidueCleanReport extends CleanReport {
  final String? registryBackupDir;     // 本次操作的 .reg 备份目录
}
```

## 6. 架构落地

```
lib/
├── domain/
│   ├── entities/
│   │   ├── installed_program.dart            (新)
│   │   └── residue_item.dart                 (新)
│   └── scanners/
│       └── residue_scanner.dart              (新，参考 JunkScanner 接口)
├── data/
│   ├── platform/
│   │   ├── registry_reader.dart              (新，封装 RegOpenKeyEx 等)
│   │   ├── shortcut_resolver.dart            (新，封装 IShellLinkW)
│   │   └── installed_programs.dart           (新，枚举已装程序)
│   ├── scanners/
│   │   ├── filesystem_residue_scanner.dart   (新)
│   │   ├── registry_residue_scanner.dart     (新)
│   │   └── dead_shortcut_scanner.dart        (新)
│   └── services/
│       ├── residue_cleaner_service.dart      (新)
│       └── registry_backup_service.dart      (新，导出 .reg)
├── core/
│   └── utils/
│       └── registry_safety_guard.dart        (新，对应 SafetyGuard)
└── presentation/
    ├── providers/
    │   └── residue_provider.dart             (新，参考 ScanProvider)
    ├── screens/
    │   └── uninstall_residue_screen.dart     (新)
    └── widgets/
        ├── residue_item_tile.dart            (新)
        └── confidence_chip.dart              (新)
```

### 6.1 `ResidueScanner` 抽象

刻意**不复用** `JunkScanner`，因为：
- 输出实体不同（`ResidueItem` 含信心、证据，`JunkItem` 不需要）；
- 清理流程不同（文件 → 回收站；注册表 → 备份 + 删除）；
- 选择粒度不同：垃圾清理勾分类，残留清理勾**单项**。

```dart
abstract class ResidueScanner {
  ResidueKind get kind;
  Stream<ResidueItem> scan(InstalledProgramIndex index);
}
```

`InstalledProgramIndex` 由 `installed_programs.dart` 一次构建后传给所有 scanner，避免重复枚举。

### 6.2 入口接线

`lib/app.dart` 增加 `ResidueProvider`；`home_screen.dart` 第二个 `PlaceholderScreen` 替换为 `UninstallResidueScreen`。

## 7. UI 设计

### 7.1 屏幕结构

```
┌── AppBar: 卸载残留 ──────────── [扫描] [清理(N 项 / X MB)] ─┐
│                                                            │
│  ┌─ 概览卡：发现 32 个候选 / 估算可释放 1.2 GB ─┐           │
│  │  按信心：高 8 · 中 14 · 低 10                │           │
│  └──────────────────────────────────────────────┘           │
│                                                            │
│  ┌─ Tab: 文件系统(20) · 注册表(9) · 失效快捷方式(3) ──┐    │
│  │                                                    │    │
│  │  ▣ Adobe AIR              C:\Program Files\Adobe   │    │
│  │     大小 12 MB · 高信心 · 未匹配到任何已安装程序   │    │
│  │     [展开证据 ▾]                                   │    │
│  │                                                    │    │
│  │  □ ASUS                   HKLM\SOFTWARE\ASUS       │    │
│  │     16 项子键 · 中信心 · 最近修改 2023-07           │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```

### 7.2 交互细节
- 每条 tile：复选框 + 名称 + 路径 + 大小 + `ConfidenceChip`（颜色 high=primary、medium=tertiary、low=outline）；
- 展开面板：列 `evidence` 数组（"InstallLocation 未命中"、"无可执行文件"、"上次修改 2 年前"…）；
- 单项右键菜单：`在资源管理器中显示`、`复制路径`、`从清理列表移除`；
- 注册表项的"路径"列展示完整 `HKLM\SOFTWARE\...`，点击可一键复制到剪贴板；
- 清理前弹窗：明示"将移入回收站"+"将导出注册表备份到 %APPDATA%\Dustman\backups\…"；
- 清理后报告卡：`已释放 X / 备份位于 ... / 失败 N`，备份路径**可点击打开**。

## 8. 安全策略

### 8.1 文件系统：复用 `SafetyGuard`
现有 `core/utils/safety_guard.dart` 的 `protectedPathSegments` 已覆盖 `System32`、`SysWOW64`、`WindowsApps`。需追加：

```dart
// app_constants.dart
static const protectedPathSegments = [
  ...existing...,
  r'\windows\',                          // 任何 Windows\ 下都不动
  r'\program files\common files',
  r'\program files (x86)\common files',
  r'\program files\internet explorer',
  r'\program files\windows defender',
  r'\program files\windows nt',
];
```

### 8.2 注册表：新增 `RegistrySafetyGuard`

```dart
class RegistrySafetyGuard {
  static const _protectedRoots = [
    r'HKLM\SOFTWARE\Microsoft',
    r'HKLM\SOFTWARE\Wow6432Node\Microsoft',
    r'HKLM\SOFTWARE\Classes',
    r'HKLM\SOFTWARE\Clients',
    r'HKLM\SOFTWARE\Policies',
    r'HKLM\SOFTWARE\RegisteredApplications',
    r'HKLM\SYSTEM',
    r'HKLM\SECURITY',
    r'HKLM\SAM',
    r'HKCU\SOFTWARE\Microsoft',
    r'HKCU\SOFTWARE\Classes',
    r'HKCU\SOFTWARE\Policies',
  ];
  static bool isSafeToDelete(String fullKeyPath);
}
```

清理流程：`备份 → SafetyGuard 二次校验 → RegDeleteTree`。

### 8.3 备份机制

`RegistryBackupService.exportKey(fullPath)`：
1. 拼装 `reg.exe export "<full>" <outFile> /y`（或直接 `RegSaveKeyEx`）；
2. 写入 `%APPDATA%\Dustman\backups\<yyyyMMdd-HHmmss>\<sanitized>.reg`；
3. 备份失败则**取消该项删除**并记入失败报告。

文件系统残留默认用 `SHFileOperationW + FOF_ALLOWUNDO`（已在 ARCHITECTURE.md §6 列出），即移入回收站。

## 9. 性能与并发

| 阶段 | 实现 | 预算 |
|---|---|---|
| 已安装程序枚举（一次） | 同步注册表枚举（3 个键 × 平均 300 子键） | < 200 ms |
| 文件系统扫描 | `Future.wait`：5 个根并行 `Directory.list(recursive: false)` | < 1 s |
| 注册表扫描 | 两个 view × 两个根 = 4 个并行 `RegEnumKeyEx` | < 500 ms |
| 失效快捷方式 | 并行解析 ≤ 200 个 `.lnk`（`Future.wait` 分批 20） | < 1 s |

无需 `Isolate`：扫描全部是 IO bound，单 isolate `async` 足够；后续若启用「大目录大小统计」再下沉到 isolate。

## 10. 测试策略

| 层 | 用例 | 工具 |
|---|---|---|
| `InstalledProgram.matchKey` | 模糊匹配："Adobe AIR" ≈ "AdobeAIR"、"Microsoft Edge" 不匹配 "EdgeBrowser" | 纯单测 |
| `FilesystemResidueScanner` | `MemoryFileSystem` 构造三类目录，注入伪程序列表，断言产出与信心 | `package:file` |
| `RegistrySafetyGuard` | 表驱动黑名单命中 / 不命中 | 纯单测 |
| `ResidueProvider` | fake scanner，验证 idle → scanning → scanned → cleaning → reported | `flutter_test` |
| `ShortcutResolver` | Win32 接口难单测，由人工 + 集成校验 | — |

新增 5 个测试文件，目标行覆盖率 > 70%。

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 误删用户尚需的配置 | 数据丢失 | 默认 medium/low 不勾选；统一移入回收站 |
| 误删注册表关键键 | 系统异常 | 双重黑名单 + 必出 .reg 备份才允许删除 |
| 模糊匹配漏判（未识别为已装） | 误报为残留 | 至少需要 2 条证据 + 信心降级展示 |
| 32/64 位视图差异 | 漏扫 32 位程序 | 显式 `KEY_WOW64_64KEY` 与 `KEY_WOW64_32KEY` 双扫 |
| UNC / 网络盘 `.lnk` 慢 | 扫描卡顿 | 仅本地盘 target 才判活；网络盘直接跳过 |
| 用户重命名 Program Files | 路径错配 | 通过 `SHGetKnownFolderPath(FOLDERID_ProgramFiles)` 取实际路径 |
| 注册表 `RegDeleteTree` 需管理员 | HKLM 删除失败 | 命中 HKLM 项时 UI 提示需 UAC 重启；HKCU 项可直接删 |

## 12. 里程碑拆分

| 阶段 | 交付 | 估时 |
|---|---|---|
| **M1 数据层** | `RegistryReader`、`InstalledPrograms` 枚举 + 单测 | 1.0d |
| **M2 文件残留** | `FilesystemResidueScanner` + 信心分级 + 单测 | 1.0d |
| **M3 注册表残留** | `RegistryResidueScanner` + `RegistrySafetyGuard` + 备份服务 | 1.5d |
| **M4 快捷方式** | `ShortcutResolver` + `DeadShortcutScanner` | 0.5d |
| **M5 UI** | `ResidueProvider` + `UninstallResidueScreen` + tile/chip | 1.5d |
| **M6 接线 & QA** | 接 `app.dart`、真机自测、文档更新 | 0.5d |
| **合计** | | **≈ 6 d** |

## 13. 后续扩展（v0.3+）

- 「程序卸载器」：调用 `UninstallString` 一键卸载；
- 残留与已安装程序的**反向视图**：选中某程序 → 高亮所有疑似关联残留；
- 在线"共享白名单"（社区维护的已知系统厂商列表，可订阅更新）；
- 命令行：`dustman.exe residue scan --json` 输出供脚本审计。

---

## 附：与现有架构的契合点

| 现有约定 | 本期遵守方式 |
|---|---|
| 三层依赖方向 `presentation → domain ← data` | 完整遵守，新建文件全部对号入座 |
| Scanner 流式 `Stream<...>` | `ResidueScanner.scan()` 同样产出 `Stream<ResidueItem>` |
| 单项错误不冒泡 | 文件 stat、注册表查询失败一律降级跳过 + warn |
| 清理走回收站 | `SHFileOperationW + FOF_ALLOWUNDO`；注册表则前置备份 |
| 日志统一 `AppLogger` | 新增 tag：`ResidueScanner` / `RegistryBackup` |
| 平台守卫 `Platform.isWindows` | 所有 Win32 调用包在守卫内 |
